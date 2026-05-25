import Foundation
import SwiftData

enum AIAvailability: Equatable, Sendable {
    case unknown
    case available
    case unavailable(String)
}

/// 全局 AI 错误（v2-multi-category 新增）：与 per-cat 业务错误区分。
/// API Key / 网络 / 配额等问题影响所有 cat，UI 顶部 sticky banner 显示一条。
enum GlobalAIError: Equatable, Sendable {
    case invalidAPIKey
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
/// v2-multi-category: 内部状态全 per-cat（states dict）；旧 `service.dailyDigest` 等 API 保留作为 .ai cat
/// 的 backward-compat view，让旧测试与 Phase 5 前的旧 UI 代码零侵入。
@MainActor
final class RefreshService: ObservableObject {
    /// 单例。两套机制并存：
    /// - `shared` 提供全局可达入口（AppDelegate.applicationDidFinishLaunching 启动期调用）
    /// - `@StateObject` 在 SwiftUI View 层承担状态订阅（生命周期由 SwiftUI 管）
    /// 实际运行期同一个实例。测试通过 `init(rss:ai:prefs:)` 创建独立实例不影响生产。
    static let shared = RefreshService()

    // MARK: - Published state (v2: per-cat dict + global flags)

    /// per-cat 状态字典。任何 cat 内字段变化都触发 @Published 通知（SwiftUI view 自动重渲染）。
    /// setter internal 而非 private —— 测试通过 @testable import 直接 set state；
    /// 生产代码应走 mutate(_:_:) helper 或 backward-compat properties，不直接改 dict。
    @Published var states: [AINewsBar.Category: CategoryState] =
        Dictionary(uniqueKeysWithValues: AINewsBar.Category.allCases.map { ($0, CategoryState()) })

    /// 摘要 pipeline 是否在跑（瞬时 UI flag，与 cat 无关——同时只有一个 cat 在 refresh，
    /// 因为 timer 顺序遍历 + per-cat inflight 互斥）。Phase 5 UI 可显示 progress。
    @Published var isSummarizing = false

    /// 全局 AI 错误（如 API Key 错 / 网络错）。与 per-cat aiAvailability 区分：
    /// global error 影响所有 cat，UI 顶部 sticky banner；per-cat error 在 tab 内 banner。
    @Published var globalAIError: GlobalAIError?

    /// 跨日 guard 专用日期（全局事件，不分 cat）。
    /// 与 lastRefreshDate 分离：旧实现复用 lastRefreshDate 做跨日判断会被 refresh() 末尾抹掉信号。
    var lastResetCheckDate: Date?

    // MARK: - Backward-compat .ai cat shortcut properties
    //
    // 旧测试 `service.dailyDigest` / 旧 UI 代码 `service.aiAvailability` 等访问，
    // computed property 读 states[.ai]；SwiftUI 通过 @Published states 的变更通知自动重渲染。
    // 写入通过 mutate(.ai)；setter 与 states[.ai] 等价。
    // Phase 5 UI 切换到 selectedTab 时，UI 应直接读 service.state(for: cat) 不再走这些 shortcut。

    var dailyDigest: String? {
        get { states[.ai]?.dailyDigest }
        set { mutate(.ai) { $0.dailyDigest = newValue } }
    }
    var recommendedArticleIDs: [UUID] {
        get { states[.ai]?.recommendedArticleIDs ?? [] }
        set { mutate(.ai) { $0.recommendedArticleIDs = newValue } }
    }
    var aiAvailability: AIAvailability {
        get { states[.ai]?.aiAvailability ?? .unknown }
        set { mutate(.ai) { $0.aiAvailability = newValue } }
    }
    var lastDigestDate: Date? {
        get { states[.ai]?.lastDigestDate }
        set { mutate(.ai) { $0.lastDigestDate = newValue } }
    }
    var lastRecommendDate: Date? {
        get { states[.ai]?.lastRecommendDate }
        set { mutate(.ai) { $0.lastRecommendDate = newValue } }
    }
    var lastRefreshDate: Date? {
        get { states[.ai]?.lastRefreshDate }
        set { mutate(.ai) { $0.lastRefreshDate = newValue } }
    }
    var lastError: String? {
        get { states[.ai]?.lastError }
        set { mutate(.ai) { $0.lastError = newValue } }
    }
    var lastFetchErrorCount: Int {
        get { states[.ai]?.lastFetchErrorCount ?? 0 }
        set { mutate(.ai) { $0.lastFetchErrorCount = newValue } }
    }
    var isRefreshing: Bool { states[.ai]?.isRefreshing ?? false }
    var isRegeneratingRecommend: Bool { states[.ai]?.isRegeneratingRecommend ?? false }
    var isRegeneratingDigest: Bool { states[.ai]?.isRegeneratingDigest ?? false }

    // MARK: - State accessors (v2 推荐 API)

    func state(for cat: AINewsBar.Category) -> CategoryState {
        states[cat] ?? CategoryState()
    }

    private func mutate(_ cat: AINewsBar.Category, _ block: (inout CategoryState) -> Void) {
        var state = states[cat] ?? CategoryState()
        block(&state)
        states[cat] = state
    }

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

    /// 正在运行摘要 pipeline 的 cat 数。`isSummarizing` 是公开 UI flag，
    /// 但 v2 允许 cross-cat refresh 并发，不能让先结束的 cat 把全局 Bool 提前清掉。
    private var activeSummaryPipelineCount = 0

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

    func configure(with context: ModelContext, usage: (any UsageRecording)? = nil) {
        modelContext = context
        self.usage = usage
        loadPersistedStateAllCats()
        guard !configured else { return }
        configured = true
        scheduleTimer()
    }

    /// 主动清理 timer 和 inflight tasks。测试 tearDown 显式调用。
    /// Swift 5.9 工具链不支持 @MainActor isolated deinit，无法在 deinit 兜底。
    func stop() {
        timer?.invalidate()
        timer = nil
        for (_, task) in refreshTasks { task.cancel() }
        refreshTasks.removeAll()
        activeSummaryPipelineCount = 0
        isSummarizing = false
        configured = false
    }

    /// 后台启动入口（AppDelegate 调用）。
    /// v2: 首启 (firstLaunchAfterSchemaUpgrade=true) 仅刷新 AI cat（首屏 27 源全抓体验差）；
    /// 后续走 refreshAllCatsSequentially 顺序遍历三 cat。
    func launchBackgroundRefreshIfNeeded() {
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

    /// 三 cat 顺序刷新（timer fire 与首启非首次都走此路径，避免 token QPS 峰值）。
    /// v2.1: 跳过 `prefs.loadAutoRefreshEnabled(for:) == false` 的 cat 省 token。
    /// force refresh / lazy first-tab-switch / 手动 refresh 不走此路径，不受开关影响。
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
    func postUnreadCount(context: ModelContext) {
        let articles = context.safeFetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.isRead == false })
        )
        let count = articles.filter { $0.accepted == true }.count
        NotificationCenter.default.post(name: .unreadCountChanged, object: count)
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
        defer { mutate(cat) { $0.isRefreshing = false } }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        cleanupOldArticles(context: context, category: cat, before: startOfToday)

        let catRaw = cat.rawValue
        let feeds = context.safeFetch(
            FetchDescriptor<Feed>(predicate: #Predicate {
                $0.isEnabled == true && $0.category == catRaw
            })
        )

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
        let newArticles = mergeNewArticles(
            cat: cat,
            rawResults: rawResults,
            existingURLs: existingURLs,
            startOfToday: startOfToday
        )

        if !newArticles.isEmpty {
            newArticles.forEach { context.insert($0) }
            guard context.safeSave() else {
                mutate(cat) { $0.lastError = "数据库保存失败，跳过本次刷新" }
                return
            }
        }

        mutate(cat) {
            $0.lastFetchErrorCount = fetchErrors.count
            if !fetchErrors.isEmpty && newArticles.isEmpty { $0.lastError = fetchErrors.first }
            $0.lastRefreshDate = Date()
        }
        postUnreadCount(context: context)

        // v2: Filter Stage 在 Summary 前（仅财报 cat 启用，其他 cat noop）
        await runFilterStage(cat: cat, context: context)

        await processAI(cat: cat, context: context, hasNewArticles: !newArticles.isEmpty)
        usage?.cleanupOlderThan(days: usageRetentionDays)
    }

    // MARK: - Filter Stage (v2-multi-category)

    /// AI Filter：仅对配了 filterPrompt 的 cat 启用（first release：财报）。
    /// fetch accepted==nil && filterFailCount<3 → FilterPipeline → 写回 accepted / 累加 filterFailCount。
    private func runFilterStage(cat: AINewsBar.Category, context: ModelContext) async {
        let config = CategoryConfig.for(cat)
        guard let filterPrompt = config.filterPrompt else { return }

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
            return
        }
        guard !pending.isEmpty else { return }
        guard let (apiKey, model) = currentCredentials(cat: cat) else { return }

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
                    article.filterFailCount += 1
                    if article.filterFailCount >= filterMaxFailures {
                        article.accepted = false
                        Log.write("[Filter][\(catRaw)] permanently rejecting after \(filterMaxFailures) failures: \(article.title.prefix(30))")
                    }
                }
            }
            if persistSucceeded {
                do {
                    try context.safeSaveOrThrow()
                } catch {
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
    }

    // MARK: - Force regenerate (per-cat)

    func forceRegenerateRecommend(_ cat: AINewsBar.Category = .ai) async {
        resetCrossedDayStateIfNeeded()
        if let existing = refreshTasks[cat] { await existing.value }

        guard !state(for: cat).isRegeneratingRecommend, let context = modelContext else { return }
        guard let (apiKey, model) = currentCredentials(cat: cat) else { return }
        mutate(cat) { $0.isRegeneratingRecommend = true }
        defer { mutate(cat) { $0.isRegeneratingRecommend = false } }

        let snapshot = ArticleSnapshot.capture(from: context, category: cat)
        await runRecommend(cat: cat, snapshot: snapshot, apiKey: apiKey, model: model)
    }

    func forceRegenerateDigest(_ cat: AINewsBar.Category = .ai) async {
        resetCrossedDayStateIfNeeded()
        if let existing = refreshTasks[cat] { await existing.value }

        guard !state(for: cat).isRegeneratingDigest, let context = modelContext else { return }
        guard let (apiKey, model) = currentCredentials(cat: cat) else { return }
        mutate(cat) { $0.isRegeneratingDigest = true }
        defer { mutate(cat) { $0.isRegeneratingDigest = false } }

        let snapshot = ArticleSnapshot.capture(from: context, category: cat)
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
        guard let (apiKey, model) = currentCredentials(cat: cat) else { return }

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
            beginSummaryPipeline()
            let result = await summaryPipeline.run(tasks: pendingTasks, apiKey: apiKey, model: model)
            endSummaryPipeline()
            if let globalError = result.globalError {
                self.globalAIError = globalError
            }
            commitSummaries(cat: cat, result: result, model: model, context: context)
            coverage = result.completionRate >= coverageThreshold
            if !coverage && !result.failedIds.isEmpty {
                mutate(cat) {
                    $0.aiAvailability = .unavailable("摘要调用多数失败 (\(result.failedIds.count)/\(result.total))")
                }
            }
        }

        let snapshot = ArticleSnapshot.capture(from: context, category: cat)
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
        prefs.saveRecommendArticleCount(outcome.articleCount, for: cat)
        usage?.record(scene: .recommend, category: cat, model: model, info: outcome.usage)
    }

    private func commit(cat: AINewsBar.Category, digest outcome: DigestEngine.Outcome, model: String) {
        mutate(cat) {
            $0.dailyDigest = outcome.content
            $0.lastDigestDate = outcome.generatedAt
            $0.digestArticleCount = outcome.articleCount
        }
        prefs.saveDigest(content: outcome.content, date: outcome.generatedAt, for: cat)
        prefs.saveDigestArticleCount(outcome.articleCount, for: cat)
        usage?.record(scene: .digest, category: cat, model: model, info: outcome.usage)
        // 注意：不重置 aiAvailability —— Recommend 设的 .unavailable 应保留
    }

    /// 摘要原子持久化：safeSaveOrThrow 失败回滚内存 + 设 .unavailable + token 记 success=false。
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
                if let alive = try? context.safeFetchOrThrow(
                    FetchDescriptor<Article>(predicate: #Predicate { ids.contains($0.id) })
                ) {
                    for article in alive where map[article.id] != nil { article.aiSummary = nil }
                    _ = context.safeSave()
                }
                mutate(cat) { $0.aiAvailability = .unavailable("摘要保存失败") }
                Log.write("[Summary][\(cat.rawValue)] commit failed: \(error)")
                persistSucceeded = false
            }
        }

        for item in result.completed {
            usage?.record(
                scene: .summary, category: cat, model: model,
                input: item.usage.inputTokens, output: item.usage.outputTokens,
                success: persistSucceeded
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

    /// per-cat credentials 查询。API Key 缺失时同时设 globalAIError + per-cat aiAvailability。
    private func currentCredentials(cat: AINewsBar.Category) -> (apiKey: String, model: String)? {
        let key = prefs.getAPIKey() ?? ""
        guard !key.isEmpty else {
            globalAIError = .invalidAPIKey
            mutate(cat) { $0.aiAvailability = .unavailable("未配置 API Key") }
            return nil
        }
        // API Key 存在时清 global error（之前可能因 key 缺失设过）
        if globalAIError == .invalidAPIKey { globalAIError = nil }
        return (key, prefs.getModel())
    }

    private func applyGlobalAIErrorIfNeeded(_ error: Error) {
        if let mapped = GlobalAIError.from(error) {
            globalAIError = mapped
        }
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

    private func beginSummaryPipeline() {
        activeSummaryPipelineCount += 1
        isSummarizing = true
    }

    private func endSummaryPipeline() {
        activeSummaryPipelineCount = max(0, activeSummaryPipelineCount - 1)
        isSummarizing = activeSummaryPipelineCount > 0
    }

    /// 跨日全 cat 重置：lastResetCheckDate 不在今天时执行。
    /// 调用点：refresh / forceRegenerate* / refreshIfNeeded / timer / NSWorkspace 唤醒。幂等。
    func resetCrossedDayStateIfNeeded() {
        guard let context = modelContext else { return }
        if let last = lastResetCheckDate, Calendar.current.isDateInToday(last) { return }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        cleanupOldArticles(context: context, before: startOfToday)

        let shouldClearState: Bool
        if let last = lastResetCheckDate {
            shouldClearState = !Calendar.current.isDateInToday(last)
        } else {
            // 首次启动没有 lastResetCheckDate：只清旧文章，避免同日重启把今天的
            // persisted digest/recommend 清掉。若内存状态明确来自昨天，则仍按跨日清理。
            shouldClearState = AINewsBar.Category.allCases.contains { cat in
                let s = state(for: cat)
                return [s.lastRefreshDate, s.lastDigestDate, s.lastRecommendDate]
                    .compactMap { $0 }
                    .contains { !Calendar.current.isDateInToday($0) }
            }
        }

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

    /// per-cat 清旧文章（runRefresh 内用，仅清该 cat）
    private func cleanupOldArticles(context: ModelContext, category: AINewsBar.Category, before date: Date) {
        let catRaw = category.rawValue
        let old = context.safeFetch(
            FetchDescriptor<Article>(predicate: #Predicate {
                $0.category == catRaw && $0.publishedAt < date
            })
        )
        old.forEach { context.delete($0) }
        if !old.isEmpty { context.safeSave() }
    }

    /// 全 cat 清旧文章（跨日重置内用）
    private func cleanupOldArticles(context: ModelContext, before date: Date) {
        let old = context.safeFetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.publishedAt < date })
        )
        old.forEach { context.delete($0) }
        if !old.isEmpty { context.safeSave() }
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
                case 401, 403:
                    return .invalidAPIKey
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
