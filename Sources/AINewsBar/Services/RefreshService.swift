import Foundation
import SwiftData

enum AIAvailability: Equatable, Sendable {
    case unknown
    case available
    case unavailable(String)
}

/// 全局 AI 错误（v2-multi-category 新增）：与 per-cat 业务错误区分。
/// API Key / 网络 / 配额等问题影响所有 cat，UI 顶部 sticky banner 显示一条。
///
/// H4: 拆分 invalidAPIKey vs forbidden —— DashScope 401 是 key 错，403 常见是
/// "key 有效但模型未授权"（用户开通了 qwen-plus 没开通 qwen3.6-plus）。一锅炖会让
/// 用户去设置看 key 在那里却被告知"未配置"，怀疑代码 bug。
enum GlobalAIError: Equatable, Sendable {
    case invalidAPIKey       // HTTP 401
    case forbidden           // HTTP 403 —— 模型未授权 / 账号权限不足
    case networkUnreachable
    case quotaExceeded
    case other(String)
}

/// v2-multi-category: 单 cat 的 UI 状态聚合。改为 struct 值类型，
/// 让 RefreshService 通过 `mutate(_:_:)` 集中触发 @Published states 字典变更通知。
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

/// 编排者（Facade）：聚合 @Published UI 状态、调度 RSS / Pipeline / Engine / FilterPipeline、原子提交持久化
/// v2-multi-category: 状态全 per-cat（states dict）。生产 UI 一律走 `state(for:)`；
/// 改 state 走 `mutate(_:_:)`（内部）或 `markAvailability(_:for:)`（公开）；
/// 测试走 `_testMutate(for:_:)`（DEBUG-only）。
@MainActor
final class RefreshService: ObservableObject {
    /// 单例。两套机制并存：
    /// - `shared` 提供全局可达入口（AppDelegate.applicationDidFinishLaunching 启动期调用）
    /// - `@StateObject` 在 SwiftUI View 层承担状态订阅（生命周期由 SwiftUI 管）
    /// 实际运行期同一个实例。测试通过 `init(rss:ai:prefs:)` 创建独立实例不影响生产。
    static let shared = RefreshService()

    // MARK: - Published state (v2: per-cat dict + global flags)

    /// per-cat 状态字典。setter 私有：任何外部修改必须走 `mutate` / `markAvailability`
    /// / `_testMutate`（DEBUG），杜绝绕过单一变更点直接改 dict 的可能。
    @Published private(set) var states: [AINewsBar.Category: CategoryState] =
        Dictionary(uniqueKeysWithValues: AINewsBar.Category.allCases.map { ($0, CategoryState()) })

    /// 摘要 pipeline 是否在跑（全局兼容 flag）。UI 新代码优先使用
    /// `isSummarizing(category:)`，避免一个 tab 的 AI 处理禁用所有 tab。
    @Published var isSummarizing = false

    /// 全局 AI 错误（如 API Key 错 / 网络错）。与 per-cat aiAvailability 区分：
    /// global error 影响所有 cat，UI 顶部 sticky banner；per-cat error 在 tab 内 banner。
    @Published var globalAIError: GlobalAIError?

    /// 启动期非 AI 错误（如 RSS 内置源 syncInto 失败 / store 初始化重大问题）。
    /// 与 globalAIError 分离：
    /// - 复用 globalAIError 会让任何一次 AI 成功 (`clearGlobalAIErrorAfterAISuccess`)
    ///   被静默清除，错误"自愈"但根因仍在；UI 也会显示成"AI 不可用"误导用户。
    /// - startupError 不被 AI 路径触碰，sticky 到重启或显式 reset。
    @Published var startupError: String?

    /// 跨日 guard 专用日期（全局事件，不分 cat）。
    /// 与 lastRefreshDate 分离：旧实现复用 lastRefreshDate 做跨日判断会被 refresh() 末尾抹掉信号。
    var lastResetCheckDate: Date?

    // MARK: - State accessors (v2 推荐 API)

    func state(for cat: AINewsBar.Category) -> CategoryState {
        states[cat] ?? CategoryState()
    }

    func isSummarizing(category cat: AINewsBar.Category) -> Bool {
        activeSummaryPipelineCats.contains(cat)
    }

    /// 公开 setter：让 View 标记 per-cat AI 可用性（API Key 测试成功/失败等场景）。
    /// 仅暴露 aiAvailability 这一个字段，其他字段一律走内部 mutate。
    func markAvailability(_ availability: AIAvailability, for cat: AINewsBar.Category) {
        mutate(cat) { $0.aiAvailability = availability }
    }

    /// 单一变更点。约定：block 内**禁止递归调 mutate**（哪怕跨 cat），否则
    /// `states[cat] = state` 会触发多次 @Published 通知，导致 SwiftUI 多次重渲。
    /// 当前所有 caller 都是简单字段赋值，无递归路径。
    private func mutate(_ cat: AINewsBar.Category, _ block: (inout CategoryState) -> Void) {
        var state = states[cat] ?? CategoryState()
        block(&state)
        states[cat] = state
    }

    #if DEBUG
    /// 测试专用：用 closure 修改指定 cat 的 state，走 mutate 路径保证 @Published 通知触发。
    /// 不让测试直接 set states[cat] —— 单一变更点（mutate）也是 SwiftUI 订阅的唯一信号源。
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

    // MARK: - Mutable

    private var timer: Timer?
    private var modelContext: ModelContext?
    private var configured = false

    /// per-cat inflight task。同 cat 的 refresh 复用 task；cross-cat 可并发（DashScope 30 QPS 安全）
    /// force* 入口也 await 同 cat 的 task 完成，避免 auto+force 并发 commit 互相覆盖
    private var refreshTasks: [AINewsBar.Category: Task<Void, Never>] = [:]

    /// 正在运行摘要 pipeline 的 cat 集合。全局 `isSummarizing` 从集合派生，保留旧 API；
    /// UI 可查询当前 cat，避免 cross-cat 并发时误禁用其他 tab。
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

    /// 注入依赖 + 恢复持久化状态。**不再启动 timer**（P2-B：configure 与
    /// "启动后台 timer" 解耦，让 AppDelegate 在 BuiltInFeeds.syncInto 成功后
    /// 才调 launchBackgroundRefreshIfNeeded 启动 timer，避免 sync 失败时 timer
    /// 仍一小时一次清空"最后刷新时间"）。
    func configure(with context: ModelContext, usage: (any UsageRecording)? = nil) {
        modelContext = context
        self.usage = usage
        loadPersistedStateAllCats()
    }

    /// 主动清理 timer 和 inflight tasks。测试 tearDown 显式调用。
    /// Swift 5.9 工具链不支持 @MainActor isolated deinit，无法在 deinit 兜底。
    func stop() {
        timer?.invalidate()
        timer = nil
        for (_, task) in refreshTasks { task.cancel() }
        refreshTasks.removeAll()
        activeSummaryPipelineCats.removeAll()
        isSummarizing = false
        configured = false
    }

    /// 后台启动入口（AppDelegate 在 BuiltInFeeds.syncInto 成功后调用）。
    /// **副作用**：启动 hourly timer（首次调用）+ 触发首轮刷新。
    /// v2: 首启 (firstLaunchAfterSchemaUpgrade=true) 仅刷新 AI cat（首屏 27 源全抓体验差）；
    /// 后续走 refreshAllCatsSequentially 三 cat 顺序。
    func launchBackgroundRefreshIfNeeded() {
        // P2-B: timer 在此启动（不再 configure 里启）；sync 失败 AppDelegate 不
        // 调本方法 → timer 永不启动，杜绝"sync 失败但 hourly timer 仍跑空"
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

    /// 系统从睡眠唤醒后的兜底入口：先做跨日重置，再顺序触发三 cat 刷新。
    /// 这是后台自动刷新语义，仍尊重 per-cat auto-refresh 开关。
    func handleSystemWake() async {
        resetCrossedDayStateIfNeeded()
        await refreshAllCatsSequentially()
    }

    /// 用户更新 credential（API Key / 模型）并测试成功后调用。
    ///
    /// **onboarding 断点修复**（P2 第五轮 review）：
    /// 旧流程在首启无 key 时仍跑 RSS 阶段并 set lastRefreshDate，AI 阶段因
    /// `ensureCredentials` 失败退出。用户后续在设置页填 key 并测试成功，
    /// 此时 `refreshIfNeeded` 因 lastRefreshDate < 30 分钟 skip；tab lazy
    /// refresh 也因 lastRefreshDate 非 nil 不触发 —— AI tab 摘要/推荐空白要等
    /// timer fire 或手动刷新，体验断裂。
    ///
    /// 本方法两步：
    /// 1. 清 credential 相关错误：globalAIError + per-cat aiAvailability=.unavailable
    ///    重置为 .unknown（让下次 refresh 自然重判，不预设 .available 避免与真实
    ///    状态分裂）。non-credential unavailable（如"摘要调用多数失败"）不在此清除。
    /// 2. 顺序 await refresh(_:) 三 cat：refresh 路径绕过 staleThreshold；
    ///    per-cat refreshTasks inflight 复用保证与其他入口安全共存。
    ///
    /// caller (APISettingsView) 一般 fire-and-forget：用户不必在设置页等三 cat 跑完，
    /// 关菜单回主 UI 时各 cat AI pipeline 已经在跑或即将完成。
    func applyCredentialChange() async {
        globalAIError = nil
        for cat in AINewsBar.Category.allCases {
            if case .unavailable = state(for: cat).aiAvailability {
                mutate(cat) { $0.aiAvailability = .unknown }
            }
        }
        for cat in AINewsBar.Category.allCases {
            await refresh(cat)
        }
    }

    /// 三 cat 顺序刷新（timer fire / 首启非首次 / 系统唤醒 三个入口走此路径）。
    ///
    /// **可靠性优先**（P2 review）：后台自动路径不再 cross-cat 并发；
    /// 旧实现峰值 QPS 3×5=15，靠"DashScope 30 QPS"这个 provider 不变量保护，
    /// 不变量一旦变（限速调整 / 同一 key 多端共享）整次刷新失败。
    /// 顺序方案峰值仅 5（cat 内部 SummaryPipeline 并发不变），最坏冷启动从
    /// ~30s 拉长到 ~1-2 分钟，但后台用户不在等屏幕，可接受。
    ///
    /// v2.1: 跳过 `prefs.loadAutoRefreshEnabled(for:) == false` 的 cat 省 token。
    /// 手动单 cat refresh / force refresh / lazy first-tab-switch 不走此路径，
    /// 保留 cat 内并发即可（用户在等响应）。
    /// 同 cat 不会双发：refresh(_:) 内部 refreshTasks inflight 复用机制保证幂等。
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

    /// 旧无 cat 签名 fallback to .ai（保持旧 caller 调用兼容）
    func refreshIfNeeded() async {
        await refreshIfNeeded(.ai)
    }

    /// v2: 全局未读计数（三 cat 累加，仅算 accepted=true）。menu bar 图标 badge 显示此值。
    /// per-cat badge（如 "AI (3)"）由 CategoryTabBar 内 @Query 独立 count。
    /// 必须 filter accepted=true：filter 拒绝/待筛的文章不应计入 (财报/新闻 cat 否则 badge 虚高)。
    ///
    /// P3 review：fetch 失败**不能**广播 count=0 —— badge 是用户可见状态，错发 0
    /// 会让用户以为"全读完了"。改 strict fetch + 失败 log 不发通知，保留上一次 badge 值。
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

    /// 刷新指定 cat。per-cat inflight 复用避免双 commit；旧 `refresh()` fallback to .ai。
    func refresh(_ cat: AINewsBar.Category = .ai) async {
        resetCrossedDayStateIfNeeded()

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

        // H3: 用 defer + 局部 capture 兜底 lastFetchErrorCount。
        // 旧实现把"set lastFetchErrorCount"放在入库后；入库失败 return
        // 时永远不执行，Footer 显示历史值（让用户以为 0 失败但实际全失败）。
        // 任何 fetchAll 成功路径都先 capture 到 capturedErrors，defer 保证写入。
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
            // P2-A: cleanup 失败必须 rollback + 中止；旧"尽力而为"会留 pending delete
            // 给后续 insert/AI 路径，commit 时一并 save 可能拖垮整次刷新或污染状态
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
            existingURLs = Set(try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate { $0.category == catRaw })
            ).map(\.url))
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

        // v2: Filter Stage 在 Summary 前（仅财报 cat 启用，其他 cat noop）
        guard await runFilterStage(cat: cat, context: context) else {
            Log.write("[Refresh][\(cat.rawValue)] abort AI pipeline because filter stage did not persist")
            return
        }

        await processAI(cat: cat, context: context, hasNewArticles: !newArticles.isEmpty)
        usage?.cleanupOlderThan(days: usageRetentionDays)
    }

    // MARK: - Filter Stage (v2-multi-category)

    /// AI Filter：仅对配了 filterPrompt 的 cat 启用（first release：财报）。
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

        // 写回 Article (用 id 重 fetch alive Article，避免持有跨 await @Model 引用)
        let acceptedSet = Set(result.acceptedIds)
        let rejectedSet = Set(result.rejectedIds)
        let failedSet = Set(result.failedIds)
        let allIds = Array(acceptedSet) + Array(rejectedSet) + Array(failedSet)

        var persistSucceeded = true
        if !allIds.isEmpty {
            let alive: [Article]
            do {
                alive = try context.safeFetchOrThrow(
                    FetchDescriptor<Article>(predicate: #Predicate { allIds.contains($0.id) })
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
                } else if failedSet.contains(article.id) {
                    article.recordFilterFailure(maxBeforeReject: filterMaxFailures)
                    if article.accepted == false {
                        Log.write("[Filter][\(catRaw)] permanently rejecting after \(filterMaxFailures) failures: \(article.title.prefix(30))")
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

        // Token usage: accepted + rejected 都有 usage；failed 不记 token 但记失败次数
        for usageInfo in result.usages {
            usage?.record(scene: .filter, category: cat, model: model,
                          info: usageInfo, success: persistSucceeded)
        }
        for _ in result.failedIds {
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
        if RefreshDecision.shouldRegenerateRecommend(
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
        // 注意：不重置 aiAvailability —— Recommend 设的 .unavailable 应保留
    }

    /// 摘要原子持久化：safeSaveOrThrow 失败用 context.rollback() 撤回内存改动 +
    /// 设 .unavailable + token 记 success=false。
    /// 不再手动 fetch+nil+save"舞蹈"——SwiftData rollback 把内存改动回滚到 last save，
    /// 保证内存/磁盘一致；手动 set nil 再 save 失败可能导致两层永久错位。
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
            // P3-A: 走 helper record(info:success:) 而非 root record(input:output:success:)，
            // 让 persistSucceeded=false 时 token 自动归零（P3-B helper 契约统一）。
            // 旧实现直接拆 inputTokens/outputTokens 调 root API 绕过了归零。
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

    /// v2: 双重去重（existingURLs + seenURLs）；丢 nil pubDate；
    /// article.category 从 feed 派生；未配 filter 或 feed.skipFilter 时 accepted 直接为 true。
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
            // accepted 初值规则（见 Article.accepted 注释）
            let acceptedAtInsert: Bool? = (!needFilter || result.feedSkipFilter) ? true : nil
            for raw in result.articles {
                guard let pubDate = raw.publishedAt,
                      !existingURLs.contains(raw.url),
                      !seenURLs.contains(raw.url),
                      pubDate >= startOfToday else { continue }
                seenURLs.insert(raw.url)
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

    /// M3: 纯查询 —— 读 prefs 返回 credentials；无副作用，可测可复用。
    /// 不设 globalAIError / aiAvailability。caller 若需要"缺 key 时进入失败状态"，
    /// 走 ensureCredentials(cat:)。
    private func currentCredentials() -> (apiKey: String, model: String)? {
        let key = prefs.getAPIKey() ?? ""
        guard !key.isEmpty else { return nil }
        return (key, prefs.getModel())
    }

    /// M3: 命令式 —— 在 currentCredentials 上叠加副作用：缺 key 时设 global +
    /// per-cat unavailable；存在则清掉之前可能被 set 的 invalidAPIKey error。
    /// 名字明示"会改 state"，与 query-only 的 currentCredentials 区分。
    private func ensureCredentials(cat: AINewsBar.Category) -> (apiKey: String, model: String)? {
        guard let creds = currentCredentials() else {
            globalAIError = .invalidAPIKey
            mutate(cat) { $0.aiAvailability = .unavailable("未配置 API Key") }
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

    /// 跨日全 cat 重置：lastResetCheckDate 不在今天时执行。
    /// 调用点：refresh / forceRegenerate* / refreshIfNeeded / timer / NSWorkspace 唤醒。幂等。
    func resetCrossedDayStateIfNeeded() {
        guard let context = modelContext else { return }
        if let last = lastResetCheckDate, Calendar.current.isDateInToday(last) { return }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        // P2-A: cleanup 失败必须 rollback + 不推进 lastResetCheckDate +
        // 不清 UI/prefs。旧 tolerant 路径会让 fetch 失败被当空结果，假装清成功
        // 后推进 guard 到今天 → 当天不再重试跨日清理，旧文章可能继续显示。
        do {
            try cleanupOldArticles(context: context, before: startOfToday)
        } catch {
            context.rollback()
            Log.write("[Refresh] cross-day cleanup failed, abort reset (will retry on next entry): \(error)")
            return
        }

        // 走到这里说明：lastResetCheckDate 要么 nil（首启），要么非今日（真跨日）。
        // 首启 case：loadPersistedState 已把"非今日 prefs"清掉，内存里 lastRefreshDate
        // 等字段要么是今日要么是 nil，复检内存状态永远 false 故无意义。
        // 真跨日 case：必清状态。直接以 lastResetCheckDate != nil 区分：
        //   - nil（首启）：只清磁盘旧文章 + set lastResetCheckDate；不动 prefs/UI 状态
        //   - 非 nil 且非今日（真跨日）：全清
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

    /// per-cat 清旧文章（runRefresh 内用，仅清该 cat）。
    /// 严格版：fetch/save 失败抛出，让 caller 决定 rollback + 中止后续流程。
    /// 旧"尽力而为"语义会留下 pending delete 给后续 insert/AI 路径，最终 commit 时一并 save
    /// 可能拖累或冲突；这里要么成功要么干净中止。
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

    /// 全 cat 清旧文章（跨日重置内用）。
    /// 严格版（与 per-cat 对齐）：失败抛出，让 caller 决定 rollback + 不推进
    /// lastResetCheckDate，避免 tolerant 路径在 fetch 失败时假装清成功 + 推进
    /// guard 导致当天不再重试跨日清理。
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
