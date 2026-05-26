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

    /// 第九轮 P2 review：skipFilter 开启时把该 feed 下 accepted==nil 的旧 pending
    /// 文章 → accepted=true。否则旧 pending 仍隐藏（accepted!=true 不进 @Query），
    /// 且下次 refresh 仍会被 FilterPipeline 抓出来烧 token —— 用户标了"纯净源"
    /// 反而既看不到旧文章也省不了费用，违反语义。
    ///
    /// 关闭路径不反向重筛已 accepted=true 的旧文章（无需过度设计：用户能区分
    /// 哪些是"假阴性"已经看到的文章，重新跑 filter 也只会得到相同结果或浪费 token）。
    ///
    /// 返回更新的文章条数；caller 据此决定是否 postUnreadCount + invalidatePerCatCache。
    @discardableResult
    static func persistSkipFilterChange(feed: Feed, newValue: Bool, in context: ModelContext) throws -> Int {
        var updatedCount = 0
        if newValue {
            let feedID = feed.id
            let pending = try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate {
                    $0.feedID == feedID && $0.accepted == nil
                })
            )
            for article in pending {
                article.accepted = true
            }
            updatedCount = pending.count
        }
        try context.safeSaveOrThrow()
        return updatedCount
    }

    private static func deleteArticles(feedID: UUID, in context: ModelContext) throws {
        let articles = try context.safeFetchOrThrow(
            FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
        )
        articles.forEach { context.delete($0) }
    }
}
