import Foundation
import SwiftData

enum FeedSettingsStore {
    static func persistBuiltInEnabledChange(feed: Feed, enabled: Bool, in context: ModelContext) throws {
        if !enabled {
            try deleteArticles(feedID: feed.id, in: context)
        }
        try context.safeSaveOrThrow()
    }

    static func deleteCustomFeeds(_ feeds: [Feed], in context: ModelContext) throws {
        for feed in feeds {
            try deleteArticles(feedID: feed.id, in: context)
            context.delete(feed)
        }
        try context.safeSaveOrThrow()
    }

    private static func deleteArticles(feedID: UUID, in context: ModelContext) throws {
        let articles = try context.safeFetchOrThrow(
            FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
        )
        articles.forEach { context.delete($0) }
    }
}
