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
    @Published var lastRefreshDate: Date?
    @Published var lastError: String?
    @Published var dailyDigest: String?
    @Published var recommendedArticleIDs: [UUID] = []
    @Published var aiAvailability: AIAvailability = .unknown

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 3600
    private let staleThreshold: TimeInterval = 1800

    private var modelContext: ModelContext?
    private var configured = false
    @Published var lastDigestDate: Date?
    @Published var lastRecommendDate: Date?
    private let digestRegenerateInterval: TimeInterval = 3 * 3600

    func configure(with context: ModelContext) {
        modelContext = context
        loadPersistedDigest()
        guard !configured else { return }
        configured = true
        scheduleTimer()
    }

    private func loadPersistedDigest() {
        guard let (content, date) = KeychainService.shared.loadDigest() else { return }
        if Calendar.current.isDateInToday(date) {
            dailyDigest = content
            lastDigestDate = date
        } else {
            KeychainService.shared.clearDigest()
        }
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
        await generatePendingSummaries(context: context, hasNewArticles: !newArticles.isEmpty)
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

    private func generatePendingSummaries(context: ModelContext, hasNewArticles: Bool) async {
        let apiKey = KeychainService.shared.getAPIKey() ?? ""
        guard !apiKey.isEmpty else {
            aiAvailability = .unavailable("未配置 API Key")
            return
        }

        let pending = (try? context.fetch(
            FetchDescriptor<Article>(predicate: #Predicate { $0.aiSummary == nil })
        )) ?? []
        guard !pending.isEmpty else {
            await generateDailyDigestIfNeeded(context: context, apiKey: apiKey, hasNewArticles: hasNewArticles)
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
        await generateDailyDigestIfNeeded(context: context, apiKey: apiKey, hasNewArticles: hasNewArticles)
    }

    private func generateDailyDigestIfNeeded(context: ModelContext, apiKey: String, hasNewArticles: Bool) async {
        let all = (try? context.fetch(FetchDescriptor<Article>())) ?? []
        let withSummary = all.compactMap { a -> (title: String, summary: String)? in
            guard let s = a.aiSummary else { return nil }
            return (title: a.title, summary: s)
        }
        guard withSummary.count >= 3 else { return }

        isSummarizing = true
        defer { isSummarizing = false }

        // 推荐：有新文章 或 列表为空时生成
        if hasNewArticles || recommendedArticleIDs.isEmpty {
            let articlesForPick = all.map { (id: $0.id, title: $0.title, summary: $0.aiSummary) }
            do {
                let ids = try await BailianService.shared.recommendArticles(articlesForPick, apiKey: apiKey)
                recommendedArticleIDs = ids
                lastRecommendDate = Date()
                aiAvailability = .available
                Log.write("[Recommend] picked \(ids.count) articles")
            } catch {
                aiAvailability = .unavailable(error.localizedDescription)
                Log.write("[Recommend] ERROR: \(error)")
            }
        } else {
            Log.write("[Recommend] skip — no new articles")
        }

        // 日报：从未生成 或 (有新文章 且 距上次生成超过3小时)
        if dailyDigest == nil || (hasNewArticles && shouldRegenerateDigest()) {
            Log.write("[Digest] generating from \(withSummary.count) articles")
            if let digest = try? await BailianService.shared.generateDigest(articleSummaries: withSummary, apiKey: apiKey) {
                let now = Date()
                dailyDigest = digest
                lastDigestDate = now
                KeychainService.shared.saveDigest(content: digest, date: now)
                Log.write("[Digest] OK, saved to disk")
            }
        } else {
            Log.write("[Digest] skip — digest exists, hasNew=\(hasNewArticles), nextRegen in \(Int((lastDigestDate.map { digestRegenerateInterval - Date().timeIntervalSince($0) } ?? 0)))s")
        }
    }

    private func shouldRegenerateDigest() -> Bool {
        guard let last = lastDigestDate else { return true }
        guard Calendar.current.isDateInToday(last) else { return true }
        return Date().timeIntervalSince(last) > digestRegenerateInterval
    }
}

extension Notification.Name {
    static let unreadCountChanged = Notification.Name("unreadCountChanged")
}
