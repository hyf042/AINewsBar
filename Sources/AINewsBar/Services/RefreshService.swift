import Foundation
import SwiftData

enum AIAvailability: Equatable, Sendable {
    case unknown
    case available
    case unavailable(String)
}

/// 全局 AI 错误：API Key / 网络 / 配额等影响所有 cat 的问题，UI 顶部 sticky banner 显示一条。
/// 与 per-cat aiAvailability 区分。
/// 401 (invalidAPIKey) 与 403 (forbidden) 必须分开：403 常见是"key 有效但模型未授权"，
/// 一锅炖会让用户在设置看到 key 在那里却被告知"未配置"。
enum GlobalAIError: Equatable, Sendable {
    case invalidAPIKey       // HTTP 401
    case forbidden           // HTTP 403 —— 模型未授权 / 账号权限不足
    case networkUnreachable
    case quotaExceeded
    case other(String)
}

/// 单 cat 的 UI 状态聚合。值类型，所有变更经 RefreshService.mutate(_:_:) 触发 @Published states 通知。
struct CategoryState: Sendable {
    var dailyDigest: String?
    var recommendedArticleIDs: [UUID] = []
    var aiAvailability: AIAvailability = .unknown
    var lastDigestDate: Date?
    var lastRecommendDate: Date?
    var lastRefreshDate: Date?
    var digestArticleCount: Int = 0
    var recommendArticleCount: Int = 0
    var isRefreshing: Bool = false
    var isRegeneratingRecommend: Bool = false
    var isRegeneratingDigest: Bool = false
    var lastError: String?
    var lastFetchErrorCount: Int = 0
}

/// 编排者（Facade）：聚合 per-cat @Published 状态、调度 RSS / Pipeline / Engine / FilterPipeline、原子提交持久化。
/// 状态全 per-cat（states dict）。UI 读走 `state(for:)`；改 state 走 `mutate`（内部）/ `markAvailability`（公开）/ `_testMutate`（DEBUG）。
@MainActor
final class RefreshService: ObservableObject {
    /// `shared` 提供全局入口（AppDelegate 启动期调用）；View 层通过 `@StateObject = .shared`
    /// 承担订阅，运行期同一实例。测试用 `init(rss:ai:prefs:)` 创建独立实例。
    static let shared = RefreshService()

    // MARK: - Published state (per-cat dict + global flags)

    /// per-cat 状态字典。setter 私有：外部修改必须走 mutate / markAvailability / _testMutate。
    @Published private(set) var states: [AINewsBar.Category: CategoryState] =
        Dictionary(uniqueKeysWithValues: AINewsBar.Category.allCases.map { ($0, CategoryState()) })

    /// 全局兼容 flag。新代码优先 `isSummarizing(category:)`，避免一个 tab 的处理禁用所有 tab。
    @Published var isSummarizing = false

    /// 全局 AI 错误（影响所有 cat，UI 顶部 sticky banner）。
    @Published var globalAIError: GlobalAIError?

    /// 启动期非 AI 错误（RSS 内置源 syncInto 失败 / store 初始化问题）。与 globalAIError 分离：
    /// 后者会被任意 AI 成功路径静默清除让根因"自愈"，且 UI 文案会误导成"AI 不可用"。
    @Published var startupError: String?

    /// 跨日 guard 专用日期（全局事件，不分 cat）。与 lastRefreshDate 分离：
    /// 复用 lastRefreshDate 做跨日判断会被 refresh() 末尾抹掉信号。
    var lastResetCheckDate: Date?

    // MARK: - State accessors

    func state(for cat: AINewsBar.Category) -> CategoryState {
        states[cat] ?? CategoryState()
    }

    func isSummarizing(category cat: AINewsBar.Category) -> Bool {
        activeSummaryPipelineCats.contains(cat)
    }

    /// 公开 setter：让 View 标记 per-cat AI 可用性（API Key 测试成功/失败等）。仅暴露 aiAvailability。
    func markAvailability(_ availability: AIAvailability, for cat: AINewsBar.Category) {
        mutate(cat) { $0.aiAvailability = availability }
    }

    /// 单一变更点。约定：block 内禁止递归调 mutate（哪怕跨 cat），否则会触发多次 @Published 通知。
    private func mutate(_ cat: AINewsBar.Category, _ block: (inout CategoryState) -> Void) {
        var state = states[cat] ?? CategoryState()
        block(&state)
        states[cat] = state
    }

    #if DEBUG
    /// 测试专用：走 mutate 路径保证 @Published 通知触发，不让测试直接 set states[cat]。
    func _testMutate(for cat: AINewsBar.Category, _ block: (inout CategoryState) -> Void) {
        mutate(cat, block)
    }
    #endif

    // MARK: - Dependencies (注入)

    private let rss: any RSSFetching
    private let ai: any AISummarizing
    private let prefs: any PreferencesStoring

    // MARK: - Components (内部组合)

    private let summaryPipeline: SummaryPipeline
    private let recommendEngine: RecommendEngine
    private let digestEngine: DigestEngine

    // MARK: - Usage tracking

    private var usage: (any UsageRecording)?

    // MARK: - Tuning

    private let refreshInterval: TimeInterval = 3600
    private let staleThreshold: TimeInterval = 1800
    private let digestRegenerateInterval: TimeInterval = 3 * 3600
    private let summaryDeltaThreshold = 3
    private let maxConcurrentSummaries = 5
    private let coverageThreshold = 0.8
    private let usageRetentionDays = 30
    private let filterMaxFailures = 3

    /// per-cat "未配置 API Key" reason 唯一文案。applyCredentialChange 精确比对这一条，
    /// 不能误清"摘要调用多数失败"等 non-credential 业务错误。
    static let missingCredentialReason = "未配置 API Key"

    // MARK: - Mutable

    private var timer: Timer?
    private var modelContext: ModelContext?
    private var configured = false

    /// per-cat inflight task。同 cat refresh 复用同一 task（含 force* 入口），避免并发 commit 互相覆盖；
    /// cross-cat 可并发。
    private var refreshTasks: [AINewsBar.Category: Task<Void, Never>] = [:]

    /// 正在跑摘要 pipeline 的 cat 集合。全局 isSummarizing 从集合派生。
    private var activeSummaryPipelineCats: Set<AINewsBar.Category> = []

    // MARK: - Init

    init(
        rss: any RSSFetching = RSSService.shared,
        ai: any AISummarizing = BailianService.shared,
        prefs: any PreferencesStoring = PreferencesService.shared
    ) {
        self.rss = rss
        self.ai = ai
        self.prefs = prefs
        self.summaryPipeline = SummaryPipeline(ai: ai, maxConcurrent: 5)
        self.recommendEngine = RecommendEngine(ai: ai)
        self.digestEngine = DigestEngine(ai: ai)
    }

    // MARK: - Public lifecycle

    /// 注入依赖 + 恢复持久化状态。**不启动 timer**：timer 由 launchBackgroundRefreshIfNeeded 启，
    /// 让 AppDelegate 在 BuiltInFeeds.syncInto 成功后才启，避免 sync 失败时 timer 仍清空"最后刷新时间"。
    func configure(with context: ModelContext, usage: (any UsageRecording)? = nil) {
        modelContext = context
        self.usage = usage
        loadPersistedStateAllCats()
    }

    /// 主动清理 timer 和 inflight tasks。测试 tearDown 显式调用
    /// （Swift 5.9 不支持 @MainActor isolated deinit）。
    func stop() {
        timer?.invalidate()
        timer = nil
        for (_, task) in refreshTasks { task.cancel() }
        refreshTasks.removeAll()
        activeSummaryPipelineCats.removeAll()
        isSummarizing = false
        configured = false
    }

    /// 后台启动入口（AppDelegate 在 syncInto 成功后调用）。副作用：首次调用启动 hourly timer + 触发首轮刷新。
    /// 首启（firstLaunchAfterSchemaUpgrade）仅刷 AI cat（首屏 27 源全抓体验差）；后续走三 cat 顺序。
    func launchBackgroundRefreshIfNeeded() {
        if !configured {
            configured = true
            scheduleTimer()
        }

        let isFirstLaunch = UserDefaults.standard.bool(forKey: "firstLaunchAfterSchemaUpgrade")
        if isFirstLaunch {
            UserDefaults.standard.set(false, forKey: "firstLaunchAfterSchemaUpgrade")
            Log.write("[Refresh] first launch after schema upgrade — only refreshing AI cat")
            Task { @MainActor [weak self] in
                await self?.refreshIfNeeded(.ai)
            }
        } else {
            Task { @MainActor [weak self] in
                await self?.refreshAllCatsSequentially()
            }
        }
    }

    /// 系统唤醒兜底入口：跨日重置 + 顺序刷新三 cat（尊重 per-cat auto-refresh 开关）。
    func handleSystemWake() async {
        resetCrossedDayStateIfNeeded()
        await refreshAllCatsSequentially()
    }

    /// skipFilter 开启把旧 pending 翻 accepted=true 后的善后，FeedRowView / BuiltInFeedRowView 共享。
    /// 三步：postUnreadCount 同步 badge → invalidatePerCatCache 让旧 digest/recommend 失效 →
    /// fire-and-forget refresh（invalidate 不清 lastRefreshDate，不主动 refresh 则 AI 派生空着等 stale；
    /// inflight 复用保证不双开 AI）。
    func handleSkipFilterPendingFlipped(for cat: AINewsBar.Category, context: ModelContext) {
        postUnreadCount(context: context)
        invalidatePerCatCache(for: cat)
        let service = self
        Task { await service.refresh(cat) }
    }

    /// 禁用内置源 / 删除自定义源后调用：清掉该 cat 的派生缓存（digest 文本可能含已删源标题；
    /// recommendedArticleIDs 非空会让 shouldRegenerate 误判"已有结果"，旧结果永不清）。
    /// **不清** lastRefreshDate / 错误状态：caller 决定要不要紧接着 refresh。
    func invalidatePerCatCache(for cat: AINewsBar.Category) {
        mutate(cat) {
            $0.dailyDigest = nil
            $0.recommendedArticleIDs = []
            $0.lastDigestDate = nil
            $0.lastRecommendDate = nil
            $0.digestArticleCount = 0
            $0.recommendArticleCount = 0
        }
        prefs.clearDigest(for: cat)
        prefs.clearRecommendState(for: cat)
        Log.write("[Refresh][\(cat.rawValue)] invalidated per-cat cache after feed source change")
    }

    /// 用户更新 credential 并测试成功后调用，修复 onboarding 断点：
    /// 首启无 key 时 refresh 已 set lastRefreshDate，用户后填 key 后 refreshIfNeeded 因 stale 阈值 skip、
    /// tab lazy refresh 也因 lastRefreshDate 非 nil 不触发，AI tab 空白要等 timer 或手动刷新。
    ///
    /// 两步：(1) 清 globalAIError + per-cat aiAvailability reason **完全等于** missingCredentialReason
    /// 的重置为 .unknown（精确匹配，避免误清真业务错误）；(2) 顺序 await refresh 三 cat（绕过 stale）。
    /// caller 一般 fire-and-forget。
    func applyCredentialChange() async {
        globalAIError = nil
        for cat in AINewsBar.Category.allCases {
            if case .unavailable(let reason) = state(for: cat).aiAvailability,
               reason == Self.missingCredentialReason {
                mutate(cat) { $0.aiAvailability = .unknown }
            }
        }
        for cat in AINewsBar.Category.allCases {
            await refresh(cat)
        }
    }

    /// 三 cat 顺序刷新（timer / 首启非首次 / 系统唤醒 三入口）。
    /// 可靠性优先：后台路径不 cross-cat 并发（旧峰值 QPS 3×5=15 靠"30 QPS"不变量保护，不变量一变整次失败）；
    /// 顺序方案峰值仅 5，最坏冷启动 ~1-2 分钟，后台用户不在等屏幕可接受。
    /// 跳过 auto-refresh 关闭的 cat 省 token。同 cat 不双发（refresh inflight 复用保证幂等）。
    private func refreshAllCatsSequentially() async {
        for cat in AINewsBar.Category.allCases {
            guard prefs.loadAutoRefreshEnabled(for: cat) else {
                Log.write("[Refresh][\(cat.rawValue)] auto-refresh disabled, skip")
                continue
            }
            await refreshIfNeeded(cat)
        }
    }

    /// 仅当 stale 时刷新指定 cat。
    func refreshIfNeeded(_ cat: AINewsBar.Category) async {
        resetCrossedDayStateIfNeeded()
        guard let last = state(for: cat).lastRefreshDate else {
            await refresh(cat)
            return
        }
        if Date().timeIntervalSince(last) > staleThreshold {
            await refresh(cat)
        }
    }

    /// 旧无 cat 签名 fallback to .ai。
    func refreshIfNeeded() async {
        await refreshIfNeeded(.ai)
    }

    /// 全局未读计数（三 cat 累加，仅算 accepted=true）。menu bar 图标 badge 显示此值。
    /// 必须 filter accepted=true：filter 拒绝/待筛的文章不计入（否则财报/新闻 badge 虚高）。
    /// fetch 失败**不**广播 count=0（会让用户以为"全读完了"），改 strict fetch + 失败保留上一次值。
    func postUnreadCount(context: ModelContext) {
        do {
            let articles = try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate { $0.isRead == false })
            )
            let count = articles.filter { $0.accepted == true }.count
            NotificationCenter.default.post(name: .unreadCountChanged, object: count)
        } catch {
            Log.write("[Refresh] postUnreadCount fetch failed, keep previous badge: \(error)")
        }
    }

    // MARK: - Main pipeline (per-cat)

    /// 刷新指定 cat。per-cat inflight 复用避免双 commit。
    func refresh(_ cat: AINewsBar.Category = .ai) async {
        resetCrossedDayStateIfNeeded()

        // startupError != nil 意味 syncInto 失败、feed 表可能空：继续刷新只会跑出"0 文章 +
        // lastRefreshDate 更新但 UI 空"且抹掉根因信号。AppDelegate 启动路径已 skip，但
        // MenuBarView.onAppear / lazy tab-switch / handleSystemWake 绕过那层保护，故在 service 层兜底。
        // 放在 resetCrossedDayStateIfNeeded() 之后：跨日清理仍需执行让昨天 digest 失效。
        // force* 不走此路径（已有 snapshot，不依赖 feed 表），不受影响。
        guard startupError == nil else {
            Log.write("[Refresh][\(cat.rawValue)] startupError set, skip refresh to avoid polluting lastRefreshDate")
            return
        }

        if let existing = refreshTasks[cat] {
            await existing.value
            return
        }

        let t = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefresh(cat)
        }
        refreshTasks[cat] = t
        await t.value
        refreshTasks[cat] = nil
    }

    private func runRefresh(_ cat: AINewsBar.Category) async {
        guard !state(for: cat).isRefreshing, let context = modelContext else { return }
        mutate(cat) { $0.isRefreshing = true; $0.lastError = nil }

        // defer + 局部 capture 兜底 lastFetchErrorCount：入库失败 return 时仍写入，
        // 避免 Footer 显示历史值（让用户以为 0 失败但实际全失败）。
        var capturedFetchErrors: [String] = []
        defer {
            mutate(cat) {
                $0.isRefreshing = false
                $0.lastFetchErrorCount = capturedFetchErrors.count
            }
        }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        do {
            try cleanupOldArticles(context: context, category: cat, before: startOfToday)
        } catch {
            // cleanup 失败必须 rollback + 中止：留 pending delete 给后续 insert/AI 路径会污染 commit。
            context.rollback()
            mutate(cat) { $0.lastError = "数据库清理旧文章失败，跳过本次刷新" }
            Log.write("[Refresh][\(cat.rawValue)] cleanup failed, abort: \(error)")
            return
        }

        let catRaw = cat.rawValue
        let feeds: [Feed]
        do {
            feeds = try context.safeFetchOrThrow(
                FetchDescriptor<Feed>(predicate: #Predicate {
                    $0.isEnabled == true && $0.category == catRaw
                })
            )
        } catch {
            mutate(cat) { $0.lastError = "数据库查询订阅源失败，跳过本次刷新" }
            return
        }

        let existingURLs: Set<String>
        do {
            // 用 URLNormalizer 归一化比对（小写 scheme+host、去 fragment、单次尾斜杠；保留 path/query 大小写
            // 与全部 query）。裸字符串会让 "/foo" vs "/foo/" / 大小写 host / #fragment 差异都重复入库。
            existingURLs = Set(try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate { $0.category == catRaw })
            ).map { URLNormalizer.normalize($0.url) })
        } catch {
            mutate(cat) { $0.lastError = "数据库查询失败，跳过本次刷新" }
            return
        }

        let (rawResults, fetchErrors) = await fetchAllFeeds(feeds: feeds)
        capturedFetchErrors = fetchErrors   // defer 读取该值写回 state
        let newArticles = mergeNewArticles(
            cat: cat,
            rawResults: rawResults,
            existingURLs: existingURLs,
            startOfToday: startOfToday
        )

        if !newArticles.isEmpty {
            newArticles.forEach { context.insert($0) }
            do {
                try context.safeSaveOrThrow()
            } catch {
                context.rollback()
                mutate(cat) { $0.lastError = "数据库保存失败，跳过本次刷新" }
                return  // defer 仍会写 lastFetchErrorCount = capturedFetchErrors.count
            }
        }

        mutate(cat) {
            if !fetchErrors.isEmpty && newArticles.isEmpty { $0.lastError = fetchErrors.first }
            $0.lastRefreshDate = Date()
        }
        postUnreadCount(context: context)

        // Filter Stage 在 Summary 前（仅配了 filterPrompt 的 cat 启用，其他 noop）。
        guard await runFilterStage(cat: cat, context: context) else {
            Log.write("[Refresh][\(cat.rawValue)] abort AI pipeline because filter stage did not persist")
            return
        }

        await processAI(cat: cat, context: context, hasNewArticles: !newArticles.isEmpty)
        usage?.cleanupOlderThan(days: usageRetentionDays)
    }

    // MARK: - Filter Stage

    /// AI Filter：仅对配了 filterPrompt 的 cat 启用。
    /// fetch accepted==nil && filterFailCount<3 → FilterPipeline → 写回 accepted / 累加 filterFailCount。
    private func runFilterStage(cat: AINewsBar.Category, context: ModelContext) async -> Bool {
        let config = CategoryConfig.for(cat)
        guard let filterPrompt = config.filterPrompt else { return true }

        let catRaw = cat.rawValue
        let maxFailures = filterMaxFailures
        let pending: [Article]
        do {
            pending = try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate {
                    $0.category == catRaw && $0.accepted == nil && $0.filterFailCount < maxFailures
                })
            )
        } catch {
            Log.write("[Filter][\(catRaw)] fetch pending failed: \(error)")
            mutate(cat) { $0.lastError = "数据库查询失败，跳过筛选" }
            return false
        }
        guard !pending.isEmpty else { return true }
        guard let (apiKey, model) = ensureCredentials(cat: cat) else { return false }

        let tasks = pending.map {
            FilterPipeline.Task(
                id: $0.id, title: $0.title,
                description: $0.content ?? "",
                category: cat
            )
        }
        let pipeline = FilterPipeline(ai: ai, maxConcurrent: 5, promptTemplate: filterPrompt)
        let result = await pipeline.run(tasks: tasks, apiKey: apiKey, model: model)

        // 写回 Article（用 id 重 fetch alive，避免持有跨 await @Model 引用）。
        // 仅 classificationFailedIds 计入 filterFailCount；transientFailedIds（HTTP/网络/credential）
        // 保持 accepted=nil，下轮 refresh 的 pending 谓词会再抓到重试，避免网络抖动永久 reject 财报文章。
        let acceptedSet = Set(result.acceptedIds)
        let rejectedSet = Set(result.rejectedIds)
        let classificationFailedSet = Set(result.classificationFailedIds)
        // transient 不写（accepted/filterFailCount 都不动），省一次 fetch
        let writeIds = Array(acceptedSet) + Array(rejectedSet) + Array(classificationFailedSet)

        var persistSucceeded = true
        if !writeIds.isEmpty {
            let alive: [Article]
            do {
                alive = try context.safeFetchOrThrow(
                    FetchDescriptor<Article>(predicate: #Predicate { writeIds.contains($0.id) })
                )
            } catch {
                mutate(cat) { $0.lastError = "数据库查询失败，跳过筛选结果保存" }
                Log.write("[Filter][\(catRaw)] refetch alive articles failed: \(error)")
                persistSucceeded = false
                alive = []
            }

            for article in alive {
                if acceptedSet.contains(article.id) {
                    article.accepted = true
                } else if rejectedSet.contains(article.id) {
                    article.accepted = false
                } else if classificationFailedSet.contains(article.id) {
                    article.recordFilterFailure(maxBeforeReject: filterMaxFailures)
                    if article.accepted == false {
                        Log.write("[Filter][\(catRaw)] permanently rejecting after \(filterMaxFailures) classification failures: \(article.title.prefix(30))")
                    }
                }
            }
            if persistSucceeded {
                do {
                    try context.safeSaveOrThrow()
                } catch {
                    context.rollback()
                    mutate(cat) { $0.lastError = "筛选结果保存失败" }
                    Log.write("[Filter][\(catRaw)] save failed: \(error)")
                    persistSucceeded = false
                }
            }
        }

        // transient 错误期间至少把 globalAIError 提示用户（不污染 per-cat unavailable，可能下轮自愈）。
        if let transientGlobal = result.firstTransientGlobalError {
            globalAIError = transientGlobal
        }

        // filter 持久化成功后补 postUnreadCount：财报文章入库时 accepted=nil 被过滤掉，
        // 这里 accepted 变 true/false 改变计数，menu bar label 只听通知，不补就 stale。
        if persistSucceeded && !writeIds.isEmpty {
            postUnreadCount(context: context)
        }

        // accepted + rejected 记 token；classificationFailed 与 transientFailed 不记 token；
        // 仅 classificationFailed 记 recordFailure（transient 不算 AI 服务质量损坏）。
        for usageInfo in result.usages {
            usage?.record(scene: .filter, category: cat, model: model,
                          info: usageInfo, success: persistSucceeded)
        }
        for _ in result.classificationFailedIds {
            usage?.recordFailure(scene: .filter, category: cat, model: model)
        }
        return persistSucceeded
    }

    // MARK: - Force regenerate (per-cat)

    func forceRegenerateRecommend(_ cat: AINewsBar.Category = .ai) async {
        resetCrossedDayStateIfNeeded()
        if let existing = refreshTasks[cat] { await existing.value }

        guard !state(for: cat).isRegeneratingRecommend, let context = modelContext else { return }
        guard let (apiKey, model) = ensureCredentials(cat: cat) else { return }
        mutate(cat) { $0.isRegeneratingRecommend = true }
        defer { mutate(cat) { $0.isRegeneratingRecommend = false } }

        let snapshot: ArticleSnapshot
        do {
            snapshot = try ArticleSnapshot.captureOrThrow(from: context, category: cat)
        } catch {
            mutate(cat) { $0.lastError = "数据库查询失败，跳过推荐生成" }
            return
        }
        await runRecommend(cat: cat, snapshot: snapshot, apiKey: apiKey, model: model)
    }

    func forceRegenerateDigest(_ cat: AINewsBar.Category = .ai) async {
        resetCrossedDayStateIfNeeded()
        if let existing = refreshTasks[cat] { await existing.value }

        guard !state(for: cat).isRegeneratingDigest, let context = modelContext else { return }
        guard let (apiKey, model) = ensureCredentials(cat: cat) else { return }
        mutate(cat) { $0.isRegeneratingDigest = true }
        defer { mutate(cat) { $0.isRegeneratingDigest = false } }

        let snapshot: ArticleSnapshot
        do {
            snapshot = try ArticleSnapshot.captureOrThrow(from: context, category: cat)
        } catch {
            mutate(cat) { $0.lastError = "数据库查询失败，跳过摘要生成" }
            return
        }
        await runDigest(cat: cat, snapshot: snapshot, apiKey: apiKey, model: model)
    }

    // MARK: - Private: persisted state

    private func loadPersistedStateAllCats() {
        for cat in AINewsBar.Category.allCases {
            loadPersistedState(cat: cat)
        }
    }

    private func loadPersistedState(cat: AINewsBar.Category) {
        guard let (content, date) = prefs.loadDigest(for: cat) else { return }
        if Calendar.current.isDateInToday(date) {
            mutate(cat) {
                $0.dailyDigest = content
                $0.lastDigestDate = date
                $0.digestArticleCount = prefs.loadDigestArticleCount(for: cat)
                $0.recommendArticleCount = prefs.loadRecommendArticleCount(for: cat)
            }
        } else {
            prefs.clearDigest(for: cat)
            prefs.clearRecommendState(for: cat)
        }
    }

    // MARK: - Private: AI pipeline (per-cat)

    private func processAI(cat: AINewsBar.Category, context: ModelContext, hasNewArticles: Bool) async {
        guard let (apiKey, model) = ensureCredentials(cat: cat) else { return }

        let catRaw = cat.rawValue
        let pendingTasks: [SummaryPipeline.Task]
        do {
            // 仅处理该 cat、accepted=true、aiSummary=nil 的文章
            let pending = try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate {
                    $0.category == catRaw && $0.accepted == true && $0.aiSummary == nil
                })
            )
            pendingTasks = pending.map {
                SummaryPipeline.Task(id: $0.id, title: $0.title, content: $0.content, category: cat)
            }
        } catch {
            mutate(cat) { $0.lastError = "数据库查询失败，跳过本次 AI 处理" }
            return
        }
        let coverage: Bool
        if pendingTasks.isEmpty {
            coverage = true
        } else {
            beginSummaryPipeline(cat)
            let result = await summaryPipeline.run(tasks: pendingTasks, apiKey: apiKey, model: model)
            endSummaryPipeline(cat)
            if let globalError = result.globalError {
                self.globalAIError = globalError
            } else if !result.completed.isEmpty {
                clearGlobalAIErrorAfterAISuccess()
            }
            commitSummaries(cat: cat, result: result, model: model, context: context)
            coverage = result.completionRate >= coverageThreshold
            if !coverage && !result.failedIds.isEmpty {
                mutate(cat) {
                    $0.aiAvailability = .unavailable("摘要调用多数失败 (\(result.failedIds.count)/\(result.total))")
                }
            }
        }

        let snapshot: ArticleSnapshot
        do {
            snapshot = try ArticleSnapshot.captureOrThrow(from: context, category: cat)
        } catch {
            mutate(cat) { $0.lastError = "数据库查询失败，跳过推荐/摘要生成" }
            return
        }
        guard snapshot.summarizedCount >= 3 else { return }

        let s = state(for: cat)
        // coverage gate 同时挡 recommend 与 digest："摘要质量不足就不生成派生内容"。
        // RecommendEngine 用 snapshot.summarized，coverage 不足意味候选含 nil-summary 文章。
        if !coverage {
            Log.write("[Recommend][\(catRaw)] skip — coverage below threshold")
        } else if RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: hasNewArticles,
            isEmpty: s.recommendedArticleIDs.isEmpty,
            currentCount: snapshot.summarizedCount,
            lastCount: s.recommendArticleCount,
            deltaThreshold: summaryDeltaThreshold
        ) {
            await runRecommend(cat: cat, snapshot: snapshot, apiKey: apiKey, model: model)
        } else {
            Log.write("[Recommend][\(catRaw)] skip — delta=\(snapshot.summarizedCount - s.recommendArticleCount), hasNew=\(hasNewArticles)")
        }

        if !coverage {
            Log.write("[Digest][\(catRaw)] skip — coverage below threshold")
        } else if RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: hasNewArticles,
            isPresent: s.dailyDigest != nil,
            lastDate: s.lastDigestDate,
            currentCount: snapshot.summarizedCount,
            lastCount: s.digestArticleCount,
            regenerateInterval: digestRegenerateInterval,
            deltaThreshold: summaryDeltaThreshold
        ) {
            await runDigest(cat: cat, snapshot: snapshot, apiKey: apiKey, model: model)
        } else {
            Log.write("[Digest][\(catRaw)] skip — delta=\(snapshot.summarizedCount - s.digestArticleCount), hasNew=\(hasNewArticles)")
        }
    }

    private func runRecommend(
        cat: AINewsBar.Category, snapshot: ArticleSnapshot,
        apiKey: String, model: String
    ) async {
        do {
            if let outcome = try await recommendEngine.run(
                snapshot: snapshot, category: cat, apiKey: apiKey, model: model
            ) {
                commit(cat: cat, recommend: outcome, model: model)
            }
        } catch {
            applyGlobalAIErrorIfNeeded(error)
            mutate(cat) { $0.aiAvailability = .unavailable(error.localizedDescription) }
            usage?.recordFailure(scene: .recommend, category: cat, model: model)
            Log.write("[Recommend][\(cat.rawValue)] ERROR: \(error)")
        }
    }

    private func runDigest(
        cat: AINewsBar.Category, snapshot: ArticleSnapshot,
        apiKey: String, model: String
    ) async {
        do {
            if let outcome = try await digestEngine.run(
                snapshot: snapshot, category: cat, apiKey: apiKey, model: model
            ) {
                commit(cat: cat, digest: outcome, model: model)
            }
        } catch {
            applyGlobalAIErrorIfNeeded(error)
            mutate(cat) { $0.aiAvailability = .unavailable(error.localizedDescription) }
            usage?.recordFailure(scene: .digest, category: cat, model: model)
            Log.write("[Digest][\(cat.rawValue)] ERROR: \(error)")
        }
    }

    // MARK: - Private: commit (per-cat 原子更新)

    private func commit(cat: AINewsBar.Category, recommend outcome: RecommendEngine.Outcome, model: String) {
        mutate(cat) {
            $0.recommendedArticleIDs = outcome.ids
            $0.lastRecommendDate = outcome.generatedAt
            $0.recommendArticleCount = outcome.articleCount
            $0.aiAvailability = .available
        }
        clearGlobalAIErrorAfterAISuccess()
        prefs.saveRecommendArticleCount(outcome.articleCount, for: cat)
        usage?.record(scene: .recommend, category: cat, model: model, info: outcome.usage)
    }

    private func commit(cat: AINewsBar.Category, digest outcome: DigestEngine.Outcome, model: String) {
        mutate(cat) {
            $0.dailyDigest = outcome.content
            $0.lastDigestDate = outcome.generatedAt
            $0.digestArticleCount = outcome.articleCount
        }
        clearGlobalAIErrorAfterAISuccess()
        prefs.saveDigest(content: outcome.content, date: outcome.generatedAt, for: cat)
        prefs.saveDigestArticleCount(outcome.articleCount, for: cat)
        usage?.record(scene: .digest, category: cat, model: model, info: outcome.usage)
        // 不重置 aiAvailability —— Recommend 设的 .unavailable 应保留
    }

    /// 摘要原子持久化：safeSaveOrThrow 失败用 context.rollback() 撤回内存改动（保证内存/磁盘一致）
    /// + 设 .unavailable + token 记 success=false。
    private func commitSummaries(
        cat: AINewsBar.Category, result: SummaryPipeline.Result, model: String,
        context: ModelContext
    ) {
        let map = Dictionary(uniqueKeysWithValues: result.completed.map { ($0.id, $0) })

        var persistSucceeded = true
        if !map.isEmpty {
            let ids = Array(map.keys)
            do {
                let alive = try context.safeFetchOrThrow(
                    FetchDescriptor<Article>(predicate: #Predicate { ids.contains($0.id) })
                )
                for article in alive {
                    if let item = map[article.id] { article.aiSummary = item.summary }
                }
                try context.safeSaveOrThrow()
            } catch {
                context.rollback()
                mutate(cat) { $0.aiAvailability = .unavailable("摘要保存失败") }
                Log.write("[Summary][\(cat.rawValue)] commit failed, rolled back: \(error)")
                persistSucceeded = false
            }
        }

        for item in result.completed {
            // 走 helper record(info:success:)：persistSucceeded=false 时 token 自动归零。
            usage?.record(
                scene: .summary, category: cat, model: model,
                info: item.usage, success: persistSucceeded
            )
        }
        for _ in result.failedIds {
            usage?.recordFailure(scene: .summary, category: cat, model: model)
        }
    }

    // MARK: - Private: RSS fetch helpers

    private struct FeedResult: Sendable {
        let articles: [RawArticle]
        let feedID: UUID
        let feedTitle: String
        let feedCategory: AINewsBar.Category
        let feedSkipFilter: Bool
        let error: String?
    }

    private func fetchAllFeeds(feeds: [Feed]) async -> (results: [FeedResult], errors: [String]) {
        let rssRef = rss
        var rawResults: [FeedResult] = []
        await withTaskGroup(of: FeedResult.self) { group in
            for feed in feeds {
                let feedID = feed.id
                let feedURL = feed.url
                let feedTitle = feed.title
                let feedCat = AINewsBar.Category.from(rawValue: feed.category)
                let skipFilter = feed.skipFilter
                group.addTask {
                    do {
                        let articles = try await rssRef.fetchRawArticles(feedURL: feedURL)
                        return FeedResult(articles: articles, feedID: feedID, feedTitle: feedTitle,
                                          feedCategory: feedCat, feedSkipFilter: skipFilter, error: nil)
                    } catch {
                        return FeedResult(articles: [], feedID: feedID, feedTitle: feedTitle,
                                          feedCategory: feedCat, feedSkipFilter: skipFilter,
                                          error: "\(feedTitle): \(error.localizedDescription)")
                    }
                }
            }
            for await result in group { rawResults.append(result) }
        }
        let errors = rawResults.compactMap(\.error)
        return (rawResults, errors)
    }

    /// 双重去重（existingURLs + seenURLs）；丢 nil pubDate；article.category 从 feed 派生；
    /// 未配 filter 或 feed.skipFilter 时 accepted 直接为 true。
    private func mergeNewArticles(
        cat: AINewsBar.Category,
        rawResults: [FeedResult],
        existingURLs: Set<String>,
        startOfToday: Date
    ) -> [Article] {
        let config = CategoryConfig.for(cat)
        let needFilter = (config.filterPrompt != nil)
        var newArticles: [Article] = []
        var seenURLs: Set<String> = []
        for result in rawResults {
            let acceptedAtInsert: Bool? = (!needFilter || result.feedSkipFilter) ? true : nil
            for raw in result.articles {
                // 归一化后比对（仅判定"是否同一篇"）；存储仍用原 raw.url 保留追踪参数。
                let key = URLNormalizer.normalize(raw.url)
                guard let pubDate = raw.publishedAt,
                      !existingURLs.contains(key),
                      !seenURLs.contains(key),
                      pubDate >= startOfToday else { continue }
                seenURLs.insert(key)
                newArticles.append(Article(
                    title: raw.title, url: raw.url, content: raw.content,
                    publishedAt: pubDate,
                    feedID: result.feedID, feedTitle: result.feedTitle,
                    category: result.feedCategory,
                    accepted: acceptedAtInsert
                ))
            }
        }
        return newArticles
    }

    // MARK: - Private: misc

    /// 纯查询：读 prefs 返回 credentials，无副作用。缺 key 返回 nil。
    private func currentCredentials() -> (apiKey: String, model: String)? {
        let key = prefs.getAPIKey() ?? ""
        guard !key.isEmpty else { return nil }
        return (key, prefs.getModel())
    }

    /// 命令式：在 currentCredentials 上叠加副作用 —— 缺 key 时设 globalAIError + per-cat unavailable
    /// （reason 用 missingCredentialReason，applyCredentialChange 依赖此字面值精确匹配）；
    /// 存在则清掉之前的 invalidAPIKey error。
    private func ensureCredentials(cat: AINewsBar.Category) -> (apiKey: String, model: String)? {
        guard let creds = currentCredentials() else {
            globalAIError = .invalidAPIKey
            mutate(cat) { $0.aiAvailability = .unavailable(Self.missingCredentialReason) }
            return nil
        }
        if globalAIError == .invalidAPIKey { globalAIError = nil }
        return creds
    }

    private func applyGlobalAIErrorIfNeeded(_ error: Error) {
        if let mapped = GlobalAIError.from(error) {
            globalAIError = mapped
        }
    }

    private func clearGlobalAIErrorAfterAISuccess() {
        globalAIError = nil
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetCrossedDayStateIfNeeded()
                await self?.refreshAllCatsSequentially()
            }
        }
    }

    private func beginSummaryPipeline(_ cat: AINewsBar.Category) {
        activeSummaryPipelineCats.insert(cat)
        isSummarizing = !activeSummaryPipelineCats.isEmpty
    }

    private func endSummaryPipeline(_ cat: AINewsBar.Category) {
        activeSummaryPipelineCats.remove(cat)
        isSummarizing = !activeSummaryPipelineCats.isEmpty
    }

    /// 跨日全 cat 重置：lastResetCheckDate 不在今天时执行。幂等。
    /// 调用点：refresh / forceRegenerate* / refreshIfNeeded / timer / 系统唤醒。
    func resetCrossedDayStateIfNeeded() {
        guard let context = modelContext else { return }
        if let last = lastResetCheckDate, Calendar.current.isDateInToday(last) { return }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        // cleanup 失败必须 rollback + 不推进 lastResetCheckDate：否则 fetch 失败被当空结果假装清成功，
        // 推进 guard 到今天 → 当天不再重试跨日清理，旧文章可能继续显示。
        do {
            try cleanupOldArticles(context: context, before: startOfToday)
        } catch {
            context.rollback()
            Log.write("[Refresh] cross-day cleanup failed, abort reset (will retry on next entry): \(error)")
            return
        }

        // lastResetCheckDate nil（首启）：loadPersistedState 已清非今日 prefs，内存状态无需再清。
        // 非 nil 且非今日（真跨日）：必清状态。故以 lastResetCheckDate != nil 区分。
        let shouldClearState = (lastResetCheckDate != nil)

        if shouldClearState {
            for cat in AINewsBar.Category.allCases {
                mutate(cat) {
                    $0.dailyDigest = nil
                    $0.recommendedArticleIDs = []
                    $0.lastDigestDate = nil
                    $0.lastRecommendDate = nil
                    $0.lastRefreshDate = nil
                    $0.digestArticleCount = 0
                    $0.recommendArticleCount = 0
                }
                prefs.clearDigest(for: cat)
                prefs.clearRecommendState(for: cat)
            }
        }

        postUnreadCount(context: context)
        lastResetCheckDate = Date()
        Log.write("[Refresh] cross-day check complete (clearedState=\(shouldClearState))")
    }

    /// per-cat 清旧文章（runRefresh 内用）。严格版：fetch/save 失败抛出，让 caller rollback + 中止，
    /// 避免留 pending delete 给后续路径。
    private func cleanupOldArticles(
        context: ModelContext, category: AINewsBar.Category, before date: Date
    ) throws {
        let catRaw = category.rawValue
        let old = try context.safeFetchOrThrow(
            FetchDescriptor<Article>(predicate: #Predicate {
                $0.category == catRaw && $0.publishedAt < date
            })
        )
        guard !old.isEmpty else { return }
        old.forEach { context.delete($0) }
        try context.safeSaveOrThrow()
    }

    /// 全 cat 清旧文章（跨日重置内用）。严格版（与 per-cat 对齐）：失败抛出让 caller 不推进 lastResetCheckDate。
    private func cleanupOldArticles(context: ModelContext, before date: Date) throws {
        let old = try context.safeFetchOrThrow(
            FetchDescriptor<Article>(predicate: #Predicate { $0.publishedAt < date })
        )
        guard !old.isEmpty else { return }
        old.forEach { context.delete($0) }
        try context.safeSaveOrThrow()
    }
}

extension Notification.Name {
    static let unreadCountChanged = Notification.Name("unreadCountChanged")
}

extension GlobalAIError {
    static func from(_ error: Error) -> GlobalAIError? {
        if let bailian = error as? BailianError {
            switch bailian {
            case .httpStatus(let code, _):
                switch code {
                case 401:
                    return .invalidAPIKey
                case 403:
                    return .forbidden
                case 429:
                    return .quotaExceeded
                case 500...599:
                    return .other("AI 服务暂时不可用")
                default:
                    return nil
                }
            case .malformedResponse, .insufficientCandidates:
                return nil
            }
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }
        let code = URLError.Code(rawValue: nsError.code)
        switch code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
             .timedOut, .networkConnectionLost, .dnsLookupFailed:
            return .networkUnreachable
        default:
            return nil
        }
    }
}
