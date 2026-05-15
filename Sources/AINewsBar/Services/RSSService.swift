import Foundation
import FeedKit

actor RSSService {
    static let shared = RSSService()

    func fetchArticles(from feed: Feed) async throws -> [Article] {
        guard let url = URL(string: feed.url) else {
            throw URLError(.badURL)
        }

        // 提前捕获，避免闭包内被 FeedKit.Feed 覆盖
        let feedID = feed.id
        let feedTitle = feed.title

        return try await withCheckedThrowingContinuation { continuation in
            let parser = FeedParser(URL: url)
            parser.parseAsync { result in
                switch result {
                case .success(let parsedFeed):
                    let articles = self.extractArticles(from: parsedFeed, feedID: feedID, feedTitle: feedTitle)
                    continuation.resume(returning: articles)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func extractArticles(from parsedFeed: FeedKit.Feed, feedID: UUID, feedTitle: String) -> [Article] {
        switch parsedFeed {
        case .rss(let rssFeed):
            return rssFeed.items?.compactMap { item in
                guard let title = item.title, let link = item.link else { return nil }
                return Article(
                    title: title,
                    url: link,
                    content: item.description,
                    publishedAt: item.pubDate ?? Date(),
                    feedID: feedID,
                    feedTitle: feedTitle
                )
            } ?? []

        case .atom(let atomFeed):
            return atomFeed.entries?.compactMap { entry in
                guard let title = entry.title,
                      let link = entry.links?.first?.attributes?.href else { return nil }
                return Article(
                    title: title,
                    url: link,
                    content: entry.summary?.value,
                    publishedAt: entry.published ?? Date(),
                    feedID: feedID,
                    feedTitle: feedTitle
                )
            } ?? []

        case .json(let jsonFeed):
            return jsonFeed.items?.compactMap { item in
                guard let title = item.title, let link = item.url else { return nil }
                return Article(
                    title: title,
                    url: link,
                    content: item.contentText,
                    publishedAt: item.datePublished ?? Date(),
                    feedID: feedID,
                    feedTitle: feedTitle
                )
            } ?? []
        }
    }
}
