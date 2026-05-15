import Foundation
import SwiftData

@MainActor
final class RefreshService: ObservableObject {
    static let shared = RefreshService()

    @Published var isRefreshing = false
    @Published var lastRefreshDate: Date?

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 3600 // 1 hour
    private let staleThreshold: TimeInterval = 1800  // 30 minutes

    private var modelContext: ModelContext?

    func configure(with context: ModelContext) {
        self.modelContext = context
        scheduleTimer()
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
        defer { isRefreshing = false }

        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        let existingURLs = Set((try? context.fetch(FetchDescriptor<Article>()))?.map(\.url) ?? [])

        var newArticles: [Article] = []
        for feed in feeds {
            guard let articles = try? await RSSService.shared.fetchArticles(from: feed) else { continue }
            let fresh = articles.filter { !existingURLs.contains($0.url) }
            newArticles.append(contentsOf: fresh)
        }

        for article in newArticles {
            context.insert(article)
        }
        try? context.save()

        lastRefreshDate = Date()
        updateBadge(context: context)
        await generatePendingSummaries(for: newArticles, context: context)
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    private func updateBadge(context: ModelContext) {
        let unread = (try? context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { !$0.isRead }))) ?? 0
        // NSApp badge not available in SPM targets; handle via AppDelegate
        NotificationCenter.default.post(name: .unreadCountChanged, object: unread)
    }

    private func generatePendingSummaries(for articles: [Article], context: ModelContext) async {
        let apiKey = KeychainService.shared.getOpenAIKey() ?? ""
        guard !apiKey.isEmpty else { return }

        for article in articles {
            guard article.aiSummary == nil else { continue }
            guard let summary = try? await OpenAIService.shared.generateSummary(for: article, apiKey: apiKey) else { continue }
            let aiSummary = AISummary(articleURL: article.url, summary: summary)
            article.aiSummary = aiSummary
            context.insert(aiSummary)
        }
        try? context.save()
    }
}

extension Notification.Name {
    static let unreadCountChanged = Notification.Name("unreadCountChanged")
}
