import Foundation
import FeedKit

// Sendable struct for cross-actor data transfer
struct RawArticle: Sendable {
    let title: String
    let url: String
    let content: String?
    let publishedAt: Date
}

actor RSSService {
    static let shared = RSSService()

    func fetchRawArticles(feedURL: String) async throws -> [RawArticle] {
        guard let url = URL(string: feedURL) else {
            throw URLError(.badURL)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let parser = FeedParser(URL: url)
            parser.parseAsync { result in
                switch result {
                case .success(let parsedFeed):
                    continuation.resume(returning: Self.extract(from: parsedFeed))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func extract(from feed: FeedKit.Feed) -> [RawArticle] {
        switch feed {
        case .rss(let rss):
            return rss.items?.compactMap { item in
                guard let title = item.title, let link = item.link else { return nil }
                return RawArticle(title: title, url: link, content: item.description, publishedAt: item.pubDate ?? Date())
            } ?? []
        case .atom(let atom):
            return atom.entries?.compactMap { entry in
                guard let title = entry.title,
                      let link = entry.links?.first?.attributes?.href else { return nil }
                return RawArticle(title: title, url: link, content: entry.summary?.value, publishedAt: entry.published ?? Date())
            } ?? []
        case .json(let json):
            return json.items?.compactMap { item in
                guard let title = item.title, let link = item.url else { return nil }
                return RawArticle(title: title, url: link, content: item.contentText, publishedAt: item.datePublished ?? Date())
            } ?? []
        }
    }
}
