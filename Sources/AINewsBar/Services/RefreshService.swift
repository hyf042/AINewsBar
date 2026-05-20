import Foundation
import SwiftData

enum AIAvailability {
    case unknown
    case available
    case unavailable(String)
}

@MainActor
final class RefreshService: ObservableObject {
    static let shared = RefreshService()

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

    // 注入的依赖
    private let rss: any RSSFetching
    private let ai: any AISummarizing
    private let prefs: any PreferencesStoring

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 3600
    private let staleThreshold: TimeInterval = 1800
    private let digestRegenerateInterval: TimeInterval = 3 * 3600
    private let summaryDeltaThreshold = 3
    private let maxConcurrentSummaries = 5
    private let coverageThreshold = 0.8

    private var modelContext: ModelContext?
    private var configured = false
    private var digestArticleCount: Int = 0
    private var recommendArticleCount: Int = 0

    init(
        rss: any RSSFetching = RSSService.shared,
        ai: any AISummarizing = BailianService.shared,
        prefs: any PreferencesStoring = PreferencesService.shared
    ) {
        self.rss = rss
        self.ai = ai
        self.prefs = prefs
    }

    func configure(with context: ModelContext) {
        modelContext = context
        loadPersistedState()
        guard !configured else { return }
        configured = true
        scheduleTimer()
    }

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

    func refresh() async {
        guard !isRefreshing, let context = modelContext else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        let feeds = context.safeFetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.isEnabled == true })
        )
        let existingURLs = Set(context.safeFetch(FetchDescriptor<Article>()).map(\.url))
        let startOfToday = Calendar.current.startOfDay(for: Date())

        cleanupOldArticles(context: context, before: startOfToday)

        // Parallel RSS fetch — all feeds are independent, no concurrency limit needed
        struct FeedResult: Sendable {
            let articles: [RawArticle]
            let feedID: UUID
            let feedTitle: String
            let error: String?
        }

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

        // C2: 跨刷新批次内 URL 去重 —— existingURLs 是刷新前快照，seenURLs 防止同批次内多 feed 重复
        var newArticles: [Article] = []
        var fetchErrors: [String] = []
        var seenURLs: Set<String> = []
        for result in rawResults {
            if let err = result.error { fetchErrors.append(err) }
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

        if !newArticles.isEmpty {
            newArticles.forEach { context.insert($0) }
            context.safeSave()
        }

        lastFetchErrorCount = fetchErrors.count
        if !fetchErrors.isEmpty && newArticles.isEmpty { lastError = fetchErrors.first }

        lastRefreshDate = Date()
        postUnreadCount(context: context)
        await generatePendingSummaries(context: context, hasNewArticles: !newArticles.isEmpty)
    }

    func postUnreadCount(context: ModelContext) {
        let count = context.safeFetchCount(
            FetchDescriptor<Article>(predicate: #Predicate { $0.isRead == false })
        )
        NotificationCenter.default.post(name: .unreadCountChanged, object: count)
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

    private func generatePendingSummaries(context: ModelContext, hasNewArticles: Bool) async {
        let apiKey = prefs.getAPIKey() ?? ""
        guard !apiKey.isEmpty else {
            aiAvailability = .unavailable("未配置 API Key")
            return
        }

        let pending = context.safeFetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.aiSummary == nil })
        )
        guard !pending.isEmpty else {
            await generateDailyDigestIfNeeded(context: context, apiKey: apiKey,
                                              hasNewArticles: hasNewArticles, hasEnoughCoverage: true)
            return
        }

        isSummarizing = true
        defer { isSummarizing = false }
        Log.write("[Summary] pending=\(pending.count), concurrency=\(maxConcurrentSummaries)")

        // Extract Sendable values before crossing actor boundaries
        struct SummaryTask: Sendable {
            let id: UUID
            let title: String
            let content: String?
        }
        let tasks = pending.map { SummaryTask(id: $0.id, title: $0.title, content: $0.content) }
        let aiRef = ai
        let maxConcurrent = maxConcurrentSummaries
        var completed: [(id: UUID, summary: String)] = []

        // Bounded concurrent execution: seed with up to maxConcurrent, add one per completion
        await withTaskGroup(of: (UUID, String?).self) { group in
            var nextIndex = min(maxConcurrent, tasks.count)

            for i in 0..<nextIndex {
                let task = tasks[i]
                group.addTask {
                    guard let s = try? await aiRef.generateSummary(
                        title: task.title, content: task.content, apiKey: apiKey)
                    else {
                        Log.write("[Summary] failed: \(task.title.prefix(30))")
                        return (task.id, nil)
                    }
                    return (task.id, s)
                }
            }

            for await (id, summary) in group {
                if let s = summary { completed.append((id, s)) }
                if nextIndex < tasks.count {
                    let task = tasks[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        guard let s = try? await aiRef.generateSummary(
                            title: task.title, content: task.content, apiKey: apiKey)
                        else {
                            Log.write("[Summary] failed: \(task.title.prefix(30))")
                            return (task.id, nil)
                        }
                        return (task.id, s)
                    }
                }
            }
        }

        // Apply results on @MainActor
        let resultMap = Dictionary(uniqueKeysWithValues: completed)
        for article in pending {
            if let s = resultMap[article.id] { article.aiSummary = s }
        }
        context.safeSave()

        let rate = RefreshDecision.completionRate(completed: completed.count, total: tasks.count)
        Log.write("[Summary] done: \(completed.count)/\(tasks.count) = \(Int(rate * 100))%")

        await generateDailyDigestIfNeeded(context: context, apiKey: apiKey,
                                          hasNewArticles: hasNewArticles,
                                          hasEnoughCoverage: rate >= coverageThreshold)
    }

    private func generateDailyDigestIfNeeded(context: ModelContext, apiKey: String,
                                              hasNewArticles: Bool, hasEnoughCoverage: Bool) async {
        let all = context.safeFetch(FetchDescriptor<Article>())
        let withSummary = all.compactMap { a -> (title: String, summary: String)? in
            guard let s = a.aiSummary else { return nil }
            return (title: a.title, summary: s)
        }
        guard withSummary.count >= 3 else { return }
        guard hasEnoughCoverage else {
            Log.write("[Digest] skip — coverage below \(Int(coverageThreshold * 100))%")
            return
        }

        isSummarizing = true
        defer { isSummarizing = false }

        let currentCount = withSummary.count

        // Recommend
        let recommendDelta = currentCount - recommendArticleCount
        if RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: hasNewArticles,
            isEmpty: recommendedArticleIDs.isEmpty,
            currentCount: currentCount,
            lastCount: recommendArticleCount,
            deltaThreshold: summaryDeltaThreshold
        ) {
            let articlesForPick = all.map { (id: $0.id, title: $0.title, summary: $0.aiSummary) }
            do {
                let ids = try await ai.recommendArticles(articlesForPick, apiKey: apiKey)
                recommendedArticleIDs = ids
                lastRecommendDate = Date()
                recommendArticleCount = currentCount
                prefs.saveRecommendArticleCount(currentCount)
                aiAvailability = .available
                Log.write("[Recommend] picked \(ids.count), delta=\(recommendDelta)")
            } catch {
                aiAvailability = .unavailable(error.localizedDescription)
                Log.write("[Recommend] ERROR: \(error)")
            }
        } else {
            Log.write("[Recommend] skip — delta=\(recommendDelta)")
        }

        // Digest
        let digestDelta = currentCount - digestArticleCount
        if RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: hasNewArticles,
            isPresent: dailyDigest != nil,
            lastDate: lastDigestDate,
            currentCount: currentCount,
            lastCount: digestArticleCount,
            regenerateInterval: digestRegenerateInterval,
            deltaThreshold: summaryDeltaThreshold
        ) {
            Log.write("[Digest] generating from \(currentCount) articles, delta=\(digestDelta)")
            if let digest = try? await ai.generateDigest(
                articleSummaries: withSummary, apiKey: apiKey) {
                let now = Date()
                dailyDigest = digest
                lastDigestDate = now
                digestArticleCount = currentCount
                prefs.saveDigest(content: digest, date: now)
                prefs.saveDigestArticleCount(currentCount)
                Log.write("[Digest] OK, savedCount=\(currentCount)")
            }
        } else {
            Log.write("[Digest] skip — delta=\(digestDelta), hasNew=\(hasNewArticles)")
        }
    }

    func forceRegenerateRecommend() async {
        guard !isRegeneratingRecommend, let context = modelContext else { return }
        let apiKey = prefs.getAPIKey() ?? ""
        guard !apiKey.isEmpty else {
            aiAvailability = .unavailable("未配置 API Key")
            return
        }
        isRegeneratingRecommend = true
        defer { isRegeneratingRecommend = false }

        let all = context.safeFetch(FetchDescriptor<Article>())
        let articlesForPick = all.map { (id: $0.id, title: $0.title, summary: $0.aiSummary) }
        guard articlesForPick.count >= 3 else { return }

        do {
            let ids = try await ai.recommendArticles(articlesForPick, apiKey: apiKey)
            recommendedArticleIDs = ids
            lastRecommendDate = Date()
            recommendArticleCount = all.filter { $0.aiSummary != nil }.count
            prefs.saveRecommendArticleCount(recommendArticleCount)
            aiAvailability = .available
            Log.write("[Recommend] force-regenerated: \(ids.count) picks")
        } catch {
            aiAvailability = .unavailable(error.localizedDescription)
            Log.write("[Recommend] force ERROR: \(error)")
        }
    }

    func forceRegenerateDigest() async {
        guard !isRegeneratingDigest, let context = modelContext else { return }
        let apiKey = prefs.getAPIKey() ?? ""
        guard !apiKey.isEmpty else {
            aiAvailability = .unavailable("未配置 API Key")
            return
        }
        isRegeneratingDigest = true
        defer { isRegeneratingDigest = false }

        let all = context.safeFetch(FetchDescriptor<Article>())
        let withSummary = all.compactMap { a -> (title: String, summary: String)? in
            guard let s = a.aiSummary else { return nil }
            return (title: a.title, summary: s)
        }
        guard withSummary.count >= 3 else { return }

        do {
            let digest = try await ai.generateDigest(articleSummaries: withSummary, apiKey: apiKey)
            let now = Date()
            dailyDigest = digest
            lastDigestDate = now
            digestArticleCount = withSummary.count
            prefs.saveDigest(content: digest, date: now)
            prefs.saveDigestArticleCount(withSummary.count)
            Log.write("[Digest] force-regenerated from \(withSummary.count) articles")
        } catch {
            aiAvailability = .unavailable(error.localizedDescription)
            Log.write("[Digest] force ERROR: \(error)")
        }
    }
}

extension Notification.Name {
    static let unreadCountChanged = Notification.Name("unreadCountChanged")
}
