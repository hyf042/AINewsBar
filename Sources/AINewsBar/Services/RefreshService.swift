import Foundation
import SwiftData

@MainActor
final class RefreshService: ObservableObject {
    static let shared = RefreshService()

    @Published var isRefreshing = false
    @Published var isSummarizing = false
    @Published var lastRefreshDate: Date?
    @Published var lastError: String?
    @Published var dailyDigest: String?
    @Published var recommendedArticleIDs: [UUID] = []

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 3600
    private let staleThreshold: TimeInterval = 1800

    private var modelContext: ModelContext?
    private var configured = false

    func configure(with context: ModelContext) {
        modelContext = context
        guard !configured else { return }
        configured = true
        scheduleTimer()
    }

    // Unstructured task — not cancelled when popover closes
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

        let feeds = (try? context.fetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.isEnabled == true })
        )) ?? []
        let existingURLs = Set((try? context.fetch(FetchDescriptor<Article>()))?.map(\.url) ?? [])

        let startOfToday = Calendar.current.startOfDay(for: Date())
        cleanupOldArticles(context: context, before: startOfToday)

        var newArticles: [Article] = []
        var fetchErrors: [String] = []

        for feed in feeds {
            let feedID = feed.id
            let feedURL = feed.url
            let feedTitle = feed.title

            do {
                let rawArticles = try await RSSService.shared.fetchRawArticles(feedURL: feedURL)
                let fresh = rawArticles
                    .filter { !existingURLs.contains($0.url) && $0.publishedAt >= startOfToday }
                    .map { Article(title: $0.title, url: $0.url, content: $0.content,
                                   publishedAt: $0.publishedAt, feedID: feedID, feedTitle: feedTitle) }
                newArticles.append(contentsOf: fresh)
            } catch {
                fetchErrors.append("\(feedTitle): \(error.localizedDescription)")
            }
        }

        if !newArticles.isEmpty {
            newArticles.forEach { context.insert($0) }
            try? context.save()
        }

        if !fetchErrors.isEmpty && newArticles.isEmpty {
            lastError = fetchErrors.first
        }

        lastRefreshDate = Date()
        postUnreadCount(context: context)
        await generatePendingSummaries(context: context)
    }

    func postUnreadCount(context: ModelContext) {
        let count = (try? context.fetchCount(
            FetchDescriptor<Article>(predicate: #Predicate { $0.isRead == false })
        )) ?? 0
        NotificationCenter.default.post(name: .unreadCountChanged, object: count)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    private func cleanupOldArticles(context: ModelContext, before date: Date) {
        let old = (try? context.fetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.publishedAt < date })
        )) ?? []
        old.forEach { context.delete($0) }
        if !old.isEmpty { try? context.save() }
    }

    private func generatePendingSummaries(context: ModelContext) async {
        let apiKey = KeychainService.shared.getAPIKey() ?? ""
        guard !apiKey.isEmpty else { return }

        let pending = (try? context.fetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.aiSummary == nil })
        )) ?? []
        guard !pending.isEmpty else {
            await generateDailyDigestIfNeeded(context: context, apiKey: apiKey)
            return
        }

        isSummarizing = true
        defer { isSummarizing = false }
        Log.write("[Summary] pending=\(pending.count)")

        for article in pending {
            do {
                let summary = try await BailianService.shared.generateSummary(for: article, apiKey: apiKey)
                article.aiSummary = summary
            } catch {
                Log.write("[Summary] ERROR \(article.title.prefix(30)): \(error)")
            }
        }
        try? context.save()
        await generateDailyDigestIfNeeded(context: context, apiKey: apiKey)
    }

    private func generateDailyDigestIfNeeded(context: ModelContext, apiKey: String) async {
        let all = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        let withSummary = all.compactMap { a -> (title: String, summary: String)? in
            guard let s = a.aiSummary else { return nil }
            return (title: a.title, summary: s)
        }
        guard withSummary.count >= 3 else { return }

        isSummarizing = true
        defer { isSummarizing = false }

        // 每次刷新都重新生成推荐
        let articlesForPick = all.map { (id: $0.id, title: $0.title) }
        if let ids = try? await BailianService.shared.recommendArticles(articlesForPick, apiKey: apiKey) {
            recommendedArticleIDs = ids
            Log.write("[Recommend] picked \(ids.count) articles")
        }

        // 摘要只在为空时生成（当天不变）
        if dailyDigest == nil {
            Log.write("[Digest] generating from \(withSummary.count) articles")
            if let digest = try? await BailianService.shared.generateDigest(articleSummaries: withSummary, apiKey: apiKey) {
                dailyDigest = digest
                Log.write("[Digest] OK")
            }
        }
    }
}

extension Notification.Name {
    static let unreadCountChanged = Notification.Name("unreadCountChanged")
}
