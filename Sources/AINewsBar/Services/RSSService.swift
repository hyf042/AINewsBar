import Foundation
import FeedKit

// Sendable struct for cross-actor data transfer.
// publishedAt 为 Optional —— RSS 源缺失发布时间时不伪造为 "现在"，由调用方决定是否入库 (P11)
struct RawArticle: Sendable {
    let title: String
    let url: String
    let content: String?
    let publishedAt: Date?
}

actor RSSService: RSSFetching {
    static let shared = RSSService()

    private let session: URLSession

    init(timeout: TimeInterval = 10) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    func fetchRawArticles(feedURL: String) async throws -> [RawArticle] {
        guard let url = URL(string: feedURL) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await session.data(from: url)
        let parser = FeedParser(data: data)
        let parsedFeed = try parser.parse().get()
        return Self.extract(from: parsedFeed)
    }

    static func extract(from feed: FeedKit.Feed) -> [RawArticle] {
        switch feed {
        case .rss(let rss):
            return rss.items?.compactMap { item in
                guard let title = item.title, let link = item.link else { return nil }
                return RawArticle(title: title, url: link, content: item.description, publishedAt: item.pubDate)
            } ?? []
        case .atom(let atom):
            return atom.entries?.compactMap { entry in
                guard let title = entry.title,
                      let link = entry.links?.first?.attributes?.href else { return nil }
                return RawArticle(title: title, url: link, content: entry.summary?.value,
                                  publishedAt: entry.published ?? entry.updated)
            } ?? []
        case .json(let json):
            return json.items?.compactMap { item in
                guard let title = item.title, let link = item.url else { return nil }
                return RawArticle(title: title, url: link, content: item.contentText, publishedAt: item.datePublished)
            } ?? []
        }
    }
}
