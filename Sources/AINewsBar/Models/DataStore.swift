import Foundation
import Combine

@MainActor
final class DataStore: ObservableObject {
    static let shared = DataStore()

    @Published private(set) var feeds: [Feed] = []
    @Published private(set) var articles: [Article] = []

    var unreadCount: Int { articles.filter { !$0.isRead }.count }
    var sortedArticles: [Article] { articles.sorted { $0.publishedAt > $1.publishedAt } }

    private let feedsURL: URL
    private let articlesURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AINewsBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        feedsURL = support.appendingPathComponent("feeds.json")
        articlesURL = support.appendingPathComponent("articles.json")
        load()
        seedBuiltInFeedsIfNeeded()
    }

    // MARK: - Feed operations

    func addFeed(_ feed: Feed) {
        guard !feeds.contains(where: { $0.url == feed.url }) else { return }
        feeds.append(feed)
        saveFeeds()
    }

    func removeFeed(_ feed: Feed) {
        feeds.removeAll { $0.id == feed.id }
        articles.removeAll { $0.feedID == feed.id }
        saveFeeds()
        saveArticles()
    }

    // MARK: - Article operations

    func insertNewArticles(_ newArticles: [Article]) {
        let existingURLs = Set(articles.map(\.url))
        let fresh = newArticles.filter { !existingURLs.contains($0.url) }
        guard !fresh.isEmpty else { return }
        articles.append(contentsOf: fresh)
        saveArticles()
    }

    func markRead(_ article: Article) {
        guard let idx = articles.firstIndex(where: { $0.id == article.id }) else { return }
        articles[idx].isRead = true
        saveArticles()
        NotificationCenter.default.post(name: .unreadCountChanged, object: unreadCount)
    }

    func saveSummary(_ summary: String, for articleURL: String) {
        guard let idx = articles.firstIndex(where: { $0.url == articleURL }) else { return }
        articles[idx].aiSummary = summary
        saveArticles()
    }

    func articleNeedsSummary(_ article: Article) -> Bool {
        article.aiSummary == nil && !(article.content ?? "").isEmpty
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: feedsURL) {
            feeds = (try? decoder.decode([Feed].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: articlesURL) {
            articles = (try? decoder.decode([Article].self, from: data)) ?? []
        }
    }

    private func saveFeeds() {
        try? encoder.encode(feeds).write(to: feedsURL, options: .atomic)
    }

    private func saveArticles() {
        try? encoder.encode(articles).write(to: articlesURL, options: .atomic)
    }

    private func seedBuiltInFeedsIfNeeded() {
        guard feeds.filter(\.isBuiltIn).isEmpty else { return }
        BuiltInFeeds.makeFeeds().forEach { addFeed($0) }
    }
}

extension Notification.Name {
    static let unreadCountChanged = Notification.Name("unreadCountChanged")
}
