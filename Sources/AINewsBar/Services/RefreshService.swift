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

    // MARK: - Tuning

    private let refreshInterval: TimeInterval = 3600
    private let staleThreshold: TimeInterval = 1800
    private let digestRegenerateInterval: TimeInterval = 3 * 3600
    private let summaryDeltaThreshold = 3
    private let maxConcurrentSummaries = 5
    private let coverageThreshold = 0.8

    // MARK: - Mutable

    private var timer: Timer?
    private var modelContext: ModelContext?
    private var configured = false
    private var digestArticleCount: Int = 0
    private var recommendArticleCount: Int = 0

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

    func configure(with context: ModelContext) {
        modelContext = context
        loadPersistedState()
        guard !configured else { return }
        configured = true
        scheduleTimer()
    }

    func launchBackgroundRefreshIfNeeded() {
        guard !isRefreshing else { return }
        Task { @MainActor [weak self] in
            await self?.refreshIfNeeded()
        }
    }

    func refreshIfNeeded() async {
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
        guard !isRefreshing, let context = modelContext else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        cleanupOldArticles(context: context, before: startOfToday)

        let feeds = context.safeFetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.isEnabled == true })
        )
        let existingURLs = Set(context.safeFetch(FetchDescriptor<Article>()).map(\.url))

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
    }

    // MARK: - Force regenerate (外部入口)

    func forceRegenerateRecommend() async {
        guard !isRegeneratingRecommend, let context = modelContext else { return }
        guard let (apiKey, model) = currentCredentials() else { return }
        isRegeneratingRecommend = true
        defer { isRegeneratingRecommend = false }

        let snapshot = ArticleSnapshot.capture(from: context)
        await runRecommend(trigger: .forced, snapshot: snapshot, apiKey: apiKey, model: model)
    }

    func forceRegenerateDigest() async {
        guard !isRegeneratingDigest, let context = modelContext else { return }
        guard let (apiKey, model) = currentCredentials() else { return }
        isRegeneratingDigest = true
        defer { isRegeneratingDigest = false }

        let snapshot = ArticleSnapshot.capture(from: context)
        await runDigest(trigger: .forced, snapshot: snapshot, apiKey: apiKey, model: model)
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
            prefs.clearDigest()
        }
    }

    // MARK: - Private: AI pipeline

    private func processAI(context: ModelContext, hasNewArticles: Bool) async {
        guard let (apiKey, model) = currentCredentials() else { return }

        // 1. 摘要：扫 pending → 调 SummaryPipeline → 回写 SwiftData
        let pending = context.safeFetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.aiSummary == nil })
        )
        let coverage: Bool
        if pending.isEmpty {
            coverage = true
        } else {
            let tasks = pending.map {
                SummaryPipeline.Task(id: $0.id, title: $0.title, content: $0.content)
            }
            isSummarizing = true
            let result = await summaryPipeline.run(tasks: tasks, apiKey: apiKey, model: model)
            isSummarizing = false
            commitSummaries(pending: pending, completed: result.completed, context: context)
            coverage = result.completionRate >= coverageThreshold
        }

        // 2. 推荐 + 日报：基于同一份 snapshot 触发
        let snapshot = ArticleSnapshot.capture(from: context)
        guard snapshot.summarizedCount >= 3 else { return }

        await runRecommend(
            trigger: .auto(
                hasNewArticles: hasNewArticles,
                isEmpty: recommendedArticleIDs.isEmpty,
                currentCount: snapshot.summarizedCount,
                lastCount: recommendArticleCount,
                deltaThreshold: summaryDeltaThreshold
            ),
            snapshot: snapshot,
            apiKey: apiKey,
            model: model
        )

        await runDigest(
            trigger: .auto(
                hasNewArticles: hasNewArticles,
                isPresent: dailyDigest != nil,
                lastDate: lastDigestDate,
                currentCount: snapshot.summarizedCount,
                lastCount: digestArticleCount,
                hasEnoughCoverage: coverage,
                regenerateInterval: digestRegenerateInterval,
                deltaThreshold: summaryDeltaThreshold
            ),
            snapshot: snapshot,
            apiKey: apiKey,
            model: model
        )
    }

    private func runRecommend(
        trigger: RecommendEngine.Trigger,
        snapshot: ArticleSnapshot,
        apiKey: String,
        model: String
    ) async {
        do {
            if let outcome = try await recommendEngine.run(
                trigger: trigger, snapshot: snapshot, apiKey: apiKey, model: model
            ) {
                commit(outcome)
            }
        } catch {
            aiAvailability = .unavailable(error.localizedDescription)
            Log.write("[Recommend] ERROR: \(error)")
        }
    }

    private func runDigest(
        trigger: DigestEngine.Trigger,
        snapshot: ArticleSnapshot,
        apiKey: String,
        model: String
    ) async {
        do {
            if let outcome = try await digestEngine.run(
                trigger: trigger, snapshot: snapshot, apiKey: apiKey, model: model
            ) {
                commit(outcome)
            }
        } catch {
            aiAvailability = .unavailable(error.localizedDescription)
            Log.write("[Digest] ERROR: \(error)")
        }
    }

    // MARK: - Private: commit (原子更新 UI 状态 + 持久化)

    private func commit(_ outcome: RecommendEngine.Outcome) {
        recommendedArticleIDs = outcome.ids
        lastRecommendDate = outcome.generatedAt
        recommendArticleCount = outcome.articleCount
        prefs.saveRecommendArticleCount(outcome.articleCount)
        aiAvailability = .available
    }

    private func commit(_ outcome: DigestEngine.Outcome) {
        dailyDigest = outcome.content
        lastDigestDate = outcome.generatedAt
        digestArticleCount = outcome.articleCount
        prefs.saveDigest(content: outcome.content, date: outcome.generatedAt)
        prefs.saveDigestArticleCount(outcome.articleCount)
        // 注意：不重置 aiAvailability —— 保留 Recommend 路径可能设的 .unavailable
        // （Recommend 失败 + Digest 成功是允许状态，UI 仍应显示 AI 不可用）
    }

    private func commitSummaries(pending: [Article], completed: [(id: UUID, summary: String)], context: ModelContext) {
        let map = Dictionary(uniqueKeysWithValues: completed)
        for article in pending {
            if let s = map[article.id] { article.aiSummary = s }
        }
        context.safeSave()
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
    private func mergeNewArticles(
        rawResults: [FeedResult],
        existingURLs: Set<String>,
        startOfToday: Date
    ) -> [Article] {
        var newArticles: [Article] = []
        var seenURLs: Set<String> = []
        for result in rawResults {
            for raw in result.articles {
                guard !existingURLs.contains(raw.url),
                      !seenURLs.contains(raw.url),
                      raw.publishedAt >= startOfToday else { continue }
                seenURLs.insert(raw.url)
                newArticles.append(Article(
                    title: raw.title, url: raw.url, content: raw.content,
                    publishedAt: raw.publishedAt,
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
            Task { await self?.refresh() }
        }
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
