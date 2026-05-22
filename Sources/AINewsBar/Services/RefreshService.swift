import Foundation
import SwiftData

enum AIAvailability {
    case unknown
    case available
    case unavailable(String)
}

/// 编排者（Facade）：聚合 @Published UI 状态、调度 RSS / Pipeline / Engine、原子提交持久化
/// 业务逻辑下沉到 SummaryPipeline / RecommendEngine / DigestEngine
@MainActor
final class RefreshService: ObservableObject {
    /// 单例。两套机制并存：
    /// - `shared` 提供全局可达入口（AppDelegate.applicationDidFinishLaunching 启动期调用）
    /// - `@StateObject` 在 SwiftUI View 层承担状态订阅（生命周期由 SwiftUI 管）
    /// 实际运行期同一个实例。测试通过 `init(rss:ai:prefs:)` 创建独立实例不影响生产。
    static let shared = RefreshService()

    // MARK: - Published state

    @Published var isRefreshing = false
    @Published var isSummarizing = false
    @Published var isRegeneratingRecommend = false
    @Published var isRegeneratingDigest = false
    @Published var lastRefreshDate: Date?
    @Published var lastError: String?
    @Published var lastFetchErrorCount: Int = 0
    @Published var dailyDigest: String?
    @Published var recommendedArticleIDs: [UUID] = []
    @Published var aiAvailability: AIAvailability = .unknown
    @Published var lastDigestDate: Date?
    @Published var lastRecommendDate: Date?

    // MARK: - Dependencies (注入)

    private let rss: any RSSFetching
    private let ai: any AISummarizing
    private let prefs: any PreferencesStoring

    // MARK: - Components (内部组合)

    private let summaryPipeline: SummaryPipeline
    private let recommendEngine: RecommendEngine
    private let digestEngine: DigestEngine

    // MARK: - Usage tracking (可选注入，启动后由 configure 装配)

    private var usage: (any UsageRecording)?

    // MARK: - Tuning

    private let refreshInterval: TimeInterval = 3600
    private let staleThreshold: TimeInterval = 1800
    private let digestRegenerateInterval: TimeInterval = 3 * 3600
    private let summaryDeltaThreshold = 3
    private let maxConcurrentSummaries = 5
    private let coverageThreshold = 0.8
    private let usageRetentionDays = 30

    // MARK: - Mutable

    private var timer: Timer?
    private var modelContext: ModelContext?
    private var configured = false
    private var digestArticleCount: Int = 0
    private var recommendArticleCount: Int = 0

    /// 跨日 guard 专用日期（与 lastRefreshDate 分离）
    /// 旧实现复用 lastRefreshDate 做跨日判断，会被 refresh() 末尾的 `lastRefreshDate = Date()` 抹掉跨日信号
    /// 例如：跨过零点后裸调 refresh() → lastRefreshDate 写为今天 → guard 永远 false → 跨日重置永久丢失
    /// 测试通过 @testable import 直接 set（保持 internal 而非 private）
    var lastResetCheckDate: Date?

    /// inflight auto refresh task。多次 refresh() 同时进入时复用，避免重复抓 RSS / 双发 AI / 双 commit
    /// force* 入口也会 await 此 task 完成（避免 auto + force 并发导致 commit 状态错乱）
    private var refreshTask: Task<Void, Never>?

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
        loadPersistedState()
        guard !configured else { return }
        configured = true
        scheduleTimer()
    }

    /// 主动清理 timer 和 inflight task。
    /// 用途：测试 tearDown 显式调用，避免 N 个测试实例的 Timer.scheduledTimer 在 RunLoop 上堆积。
    /// 生产侧 RefreshService.shared 是 singleton 永不释放，不需要主动调用。
    /// 注意：Swift 5.9 工具链不支持 @MainActor isolated deinit，所以无法在 deinit 兜底，
    /// 必须依赖 caller 在销毁实例前显式调 stop()。
    func stop() {
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        configured = false
    }

    func launchBackgroundRefreshIfNeeded() {
        guard !isRefreshing else { return }
        Task { @MainActor [weak self] in
            await self?.refreshIfNeeded()
        }
    }

    func refreshIfNeeded() async {
        // 打开菜单瞬间先做跨日检查 —— 让 UI 立即从昨天的快照切到骨架占位，
        // 否则要等 refresh 完成 digestEngine 才会更新 dailyDigest。
        resetCrossedDayStateIfNeeded()

        guard let lastRefresh = lastRefreshDate else {
            await refresh()
            return
        }
        if Date().timeIntervalSince(lastRefresh) > staleThreshold {
            await refresh()
        }
    }

    func postUnreadCount(context: ModelContext) {
        let count = context.safeFetchCount(
            FetchDescriptor<Article>(predicate: #Predicate { $0.isRead == false })
        )
        NotificationCenter.default.post(name: .unreadCountChanged, object: count)
    }

    // MARK: - Main pipeline

    func refresh() async {
        // 所有 refresh 入口统一前置：避免外部 caller 漏调
        resetCrossedDayStateIfNeeded()

        // inflight 复用：避免双发 AI 与双 commit。已有 task 进行中时复用其结果。
        if let existing = refreshTask {
            await existing.value
            return
        }

        let t = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefresh()
        }
        refreshTask = t
        await t.value
        refreshTask = nil
    }

    private func runRefresh() async {
        guard !isRefreshing, let context = modelContext else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        cleanupOldArticles(context: context, before: startOfToday)

        let feeds = context.safeFetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.isEnabled == true })
        )

        // 严格模式 fetch：失败时不能假空（旧逻辑空集合会让全部抓回文章被当新文章重插，造成重复入库）
        let existingURLs: Set<String>
        do {
            existingURLs = Set(try context.safeFetchOrThrow(FetchDescriptor<Article>()).map(\.url))
        } catch {
            lastError = "数据库查询失败，跳过本次刷新"
            return
        }

        let (rawResults, fetchErrors) = await fetchAllFeeds(feeds: feeds)
        let newArticles = mergeNewArticles(
            rawResults: rawResults,
            existingURLs: existingURLs,
            startOfToday: startOfToday
        )

        if !newArticles.isEmpty {
            newArticles.forEach { context.insert($0) }
            context.safeSave()
        }

        lastFetchErrorCount = fetchErrors.count
        if !fetchErrors.isEmpty && newArticles.isEmpty { lastError = fetchErrors.first }
        lastRefreshDate = Date()
        postUnreadCount(context: context)

        await processAI(context: context, hasNewArticles: !newArticles.isEmpty)
        usage?.cleanupOlderThan(days: usageRetentionDays)
    }

    // MARK: - Force regenerate (外部入口)

    func forceRegenerateRecommend() async {
        // force 路径也必须前置跨日检查 —— 否则用户跨过零点点"重新生成"会基于昨日+今日混合数据生成
        resetCrossedDayStateIfNeeded()
        // 等待 inflight auto refresh 完成，避免 auto + force 并发导致 commit 互相覆盖
        if let existing = refreshTask { await existing.value }

        guard !isRegeneratingRecommend, let context = modelContext else { return }
        guard let (apiKey, model) = currentCredentials() else { return }
        isRegeneratingRecommend = true
        defer { isRegeneratingRecommend = false }

        let snapshot = ArticleSnapshot.capture(from: context)
        await runRecommend(snapshot: snapshot, apiKey: apiKey, model: model)
    }

    func forceRegenerateDigest() async {
        resetCrossedDayStateIfNeeded()
        if let existing = refreshTask { await existing.value }

        guard !isRegeneratingDigest, let context = modelContext else { return }
        guard let (apiKey, model) = currentCredentials() else { return }
        isRegeneratingDigest = true
        defer { isRegeneratingDigest = false }

        let snapshot = ArticleSnapshot.capture(from: context)
        await runDigest(snapshot: snapshot, apiKey: apiKey, model: model)
    }

    // MARK: - Private: persisted state

    private func loadPersistedState() {
        guard let (content, date) = prefs.loadDigest() else { return }
        if Calendar.current.isDateInToday(date) {
            dailyDigest = content
            lastDigestDate = date
            digestArticleCount = prefs.loadDigestArticleCount()
            recommendArticleCount = prefs.loadRecommendArticleCount()
        } else {
            // 跨日：日报与推荐计数都重置（新一天从零开始触发判断）
            prefs.clearDigest()
            prefs.clearRecommendState()
        }
    }

    // MARK: - Private: AI pipeline

    private func processAI(context: ModelContext, hasNewArticles: Bool) async {
        guard let (apiKey, model) = currentCredentials() else { return }

        // 1. 摘要：扫 pending → 调 SummaryPipeline → 回写 SwiftData + 用量
        // 注意：pending 仅用于构造 Sendable tasks，不跨 await 持有 @Model 引用
        // commitSummaries 在 await 之后用 id 重新 fetch alive Article（避免 detached @Model 写入）
        let pendingTasks: [SummaryPipeline.Task]
        do {
            let pending = try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate { $0.aiSummary == nil })
            )
            pendingTasks = pending.map {
                SummaryPipeline.Task(id: $0.id, title: $0.title, content: $0.content)
            }
        } catch {
            lastError = "数据库查询失败，跳过本次 AI 处理"
            return
        }
        let coverage: Bool
        if pendingTasks.isEmpty {
            coverage = true
        } else {
            isSummarizing = true
            let result = await summaryPipeline.run(tasks: pendingTasks, apiKey: apiKey, model: model)
            isSummarizing = false
            commitSummaries(result: result, model: model, context: context)
            coverage = result.completionRate >= coverageThreshold
            // 大面积失败时显式告警，避免 UI 永远没摘要却不显示 Banner（P10 修复）
            if !coverage && !result.failedIds.isEmpty {
                aiAvailability = .unavailable("摘要调用多数失败 (\(result.failedIds.count)/\(result.total))")
            }
        }

        // 2. 推荐 + 日报：决策在此（单一职责），Engine 只负责执行
        let snapshot = ArticleSnapshot.capture(from: context)
        guard snapshot.summarizedCount >= 3 else { return }

        if RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: hasNewArticles,
            isEmpty: recommendedArticleIDs.isEmpty,
            currentCount: snapshot.summarizedCount,
            lastCount: recommendArticleCount,
            deltaThreshold: summaryDeltaThreshold
        ) {
            await runRecommend(snapshot: snapshot, apiKey: apiKey, model: model)
        } else {
            Log.write("[Recommend] skip — delta=\(snapshot.summarizedCount - recommendArticleCount), hasNew=\(hasNewArticles)")
        }

        if !coverage {
            Log.write("[Digest] skip — coverage below threshold")
        } else if RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: hasNewArticles,
            isPresent: dailyDigest != nil,
            lastDate: lastDigestDate,
            currentCount: snapshot.summarizedCount,
            lastCount: digestArticleCount,
            regenerateInterval: digestRegenerateInterval,
            deltaThreshold: summaryDeltaThreshold
        ) {
            await runDigest(snapshot: snapshot, apiKey: apiKey, model: model)
        } else {
            Log.write("[Digest] skip — delta=\(snapshot.summarizedCount - digestArticleCount), hasNew=\(hasNewArticles)")
        }
    }

    private func runRecommend(
        snapshot: ArticleSnapshot,
        apiKey: String,
        model: String
    ) async {
        do {
            if let outcome = try await recommendEngine.run(
                snapshot: snapshot, apiKey: apiKey, model: model
            ) {
                commit(outcome, model: model)
            }
        } catch {
            aiAvailability = .unavailable(error.localizedDescription)
            usage?.recordFailure(scene: .recommend, model: model)
            Log.write("[Recommend] ERROR: \(error)")
        }
    }

    private func runDigest(
        snapshot: ArticleSnapshot,
        apiKey: String,
        model: String
    ) async {
        do {
            if let outcome = try await digestEngine.run(
                snapshot: snapshot, apiKey: apiKey, model: model
            ) {
                commit(outcome, model: model)
            }
        } catch {
            aiAvailability = .unavailable(error.localizedDescription)
            usage?.recordFailure(scene: .digest, model: model)
            Log.write("[Digest] ERROR: \(error)")
        }
    }

    // MARK: - Private: commit (原子更新 UI 状态 + 持久化)

    private func commit(_ outcome: RecommendEngine.Outcome, model: String) {
        recommendedArticleIDs = outcome.ids
        lastRecommendDate = outcome.generatedAt
        recommendArticleCount = outcome.articleCount
        prefs.saveRecommendArticleCount(outcome.articleCount)
        aiAvailability = .available
        usage?.record(scene: .recommend, model: model, info: outcome.usage)
    }

    private func commit(_ outcome: DigestEngine.Outcome, model: String) {
        dailyDigest = outcome.content
        lastDigestDate = outcome.generatedAt
        digestArticleCount = outcome.articleCount
        prefs.saveDigest(content: outcome.content, date: outcome.generatedAt)
        prefs.saveDigestArticleCount(outcome.articleCount)
        usage?.record(scene: .digest, model: model, info: outcome.usage)
        // 注意：不重置 aiAvailability —— 保留 Recommend 路径可能设的 .unavailable
        // （Recommend 失败 + Digest 成功是允许状态，UI 仍应显示 AI 不可用）
    }

    /// 提交摘要结果到 SwiftData。原子写入：要么全部成功（含 token success），要么全部失败（token success=false）。
    /// - 不持有跨 await 的 [Article] @Model 引用：用 id 重新 fetch alive Article
    /// - safeSaveOrThrow 失败时回滚内存 aiSummary + 设 aiAvailability=.unavailable + token 记 success=false
    /// - 真正失败的 task（AI 调用失败）独立记 recordFailure
    private func commitSummaries(
        result: SummaryPipeline.Result,
        model: String,
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
                // 回滚内存 aiSummary（让 ArticleSnapshot.summarizedCount 不被假象污染）
                // 注意：可能部分 Article 已 set 但未 save，重置为 nil 与持久化状态一致
                if let alive = try? context.safeFetchOrThrow(
                    FetchDescriptor<Article>(predicate: #Predicate { ids.contains($0.id) })
                ) {
                    for article in alive where map[article.id] != nil { article.aiSummary = nil }
                    _ = context.safeSave()  // 尽力刷回 nil；失败也无能为力
                }
                aiAvailability = .unavailable("摘要保存失败")
                Log.write("[Summary] commit failed: \(error)")
                persistSucceeded = false
            }
        }

        // Token 记录：persistSucceeded 控制每条 completed 的 success；failed 始终是 failure
        for item in result.completed {
            usage?.record(
                scene: .summary, model: model,
                input: item.usage.inputTokens, output: item.usage.outputTokens,
                success: persistSucceeded
            )
        }
        for _ in result.failedIds {
            usage?.recordFailure(scene: .summary, model: model)
        }
    }

    // MARK: - Private: RSS fetch helpers

    private struct FeedResult: Sendable {
        let articles: [RawArticle]
        let feedID: UUID
        let feedTitle: String
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
                group.addTask {
                    do {
                        let articles = try await rssRef.fetchRawArticles(feedURL: feedURL)
                        return FeedResult(articles: articles, feedID: feedID, feedTitle: feedTitle, error: nil)
                    } catch {
                        return FeedResult(articles: [], feedID: feedID, feedTitle: feedTitle,
                                          error: "\(feedTitle): \(error.localizedDescription)")
                    }
                }
            }
            for await result in group { rawResults.append(result) }
        }
        let errors = rawResults.compactMap(\.error)
        return (rawResults, errors)
    }

    /// C2: 跨刷新批次内 URL 去重 —— existingURLs 是刷新前快照，seenURLs 防止同批次多 feed 重复
    /// 无 publishedAt 的文章丢弃（P11：RSS pubDate 缺失不伪造为今天）
    private func mergeNewArticles(
        rawResults: [FeedResult],
        existingURLs: Set<String>,
        startOfToday: Date
    ) -> [Article] {
        var newArticles: [Article] = []
        var seenURLs: Set<String> = []
        for result in rawResults {
            for raw in result.articles {
                guard let pubDate = raw.publishedAt,
                      !existingURLs.contains(raw.url),
                      !seenURLs.contains(raw.url),
                      pubDate >= startOfToday else { continue }
                seenURLs.insert(raw.url)
                newArticles.append(Article(
                    title: raw.title, url: raw.url, content: raw.content,
                    publishedAt: pubDate,
                    feedID: result.feedID, feedTitle: result.feedTitle
                ))
            }
        }
        return newArticles
    }

    // MARK: - Private: misc

    private func currentCredentials() -> (apiKey: String, model: String)? {
        let key = prefs.getAPIKey() ?? ""
        guard !key.isEmpty else {
            aiAvailability = .unavailable("未配置 API Key")
            return nil
        }
        return (key, prefs.getModel())
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetCrossedDayStateIfNeeded()
                await self?.refresh()
            }
        }
    }

    /// 跨日全量重置：lastResetCheckDate 不在今天时执行
    /// - 清 SwiftData 里昨天的文章
    /// - 重置 @Published 的 digest / 推荐 UI 状态（关键：避免 UI 显示昨天内容直到下次 refresh 完成）
    /// - 重置 prefs 持久化（与 UI 状态保持一致）
    /// - 刷新未读计数
    ///
    /// 调用点：refresh / forceRegenerate* 入口前置 + timer 触发 + refreshIfNeeded 入口 + NSWorkspace 唤醒。
    /// 多处都调形成多重保险，且只有 lastResetCheckDate 跨日时才生效，幂等可重复调用。
    ///
    /// 用 lastResetCheckDate 而非 lastRefreshDate 做 guard —— 后者被 refresh() 末尾写入
    /// 会抹掉跨日信号，导致裸 refresh() 跨过零点后跨日重置机会永久丢失。
    func resetCrossedDayStateIfNeeded() {
        let last = lastResetCheckDate ?? .distantPast
        guard !Calendar.current.isDateInToday(last),
              let context = modelContext else { return }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        cleanupOldArticles(context: context, before: startOfToday)

        dailyDigest = nil
        recommendedArticleIDs = []
        lastDigestDate = nil
        lastRecommendDate = nil
        digestArticleCount = 0
        recommendArticleCount = 0

        prefs.clearDigest()
        prefs.clearRecommendState()

        postUnreadCount(context: context)
        lastResetCheckDate = Date()
        Log.write("[Refresh] cross-day state reset (lastReset=\(last))")
    }

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
