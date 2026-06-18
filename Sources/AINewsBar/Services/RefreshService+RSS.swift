import Foundation
import SwiftData

// MARK: - RSS 抓取 / 去重 / 入库 / 清理 组件
// 从 RefreshService 主文件拆分（C2 review），降低单文件行数，不改任何逻辑。
// 这些方法不直接写 @Published 状态，返回值的副作用由主文件 runRefresh 负责。

extension RefreshService {

    // MARK: - FeedResult

    struct FeedResult: Sendable {
        let articles: [RawArticle]
        let feedID: UUID
        let feedTitle: String
        let feedCategory: AINewsBar.Category
        let feedSkipFilter: Bool
        let error: String?
    }

    // MARK: - RSS fetch

    func fetchAllFeeds(feeds: [Feed]) async -> (results: [FeedResult], errors: [String]) {
        let rssRef = rss
        var rawResults: [FeedResult] = []
        await withTaskGroup(of: FeedResult.self) { group in
            for feed in feeds {
                let feedID = feed.id
                let feedURL = feed.url
                let feedTitle = feed.title
                let feedCat = AINewsBar.Category.from(rawValue: feed.category)
                let skipFilter = feed.skipFilter
                group.addTask {
                    do {
                        let articles = try await rssRef.fetchRawArticles(feedURL: feedURL)
                        return FeedResult(articles: articles, feedID: feedID, feedTitle: feedTitle,
                                          feedCategory: feedCat, feedSkipFilter: skipFilter, error: nil)
                    } catch {
                        return FeedResult(articles: [], feedID: feedID, feedTitle: feedTitle,
                                          feedCategory: feedCat, feedSkipFilter: skipFilter,
                                          error: "\(feedTitle): \(error.localizedDescription)")
                    }
                }
            }
            for await result in group { rawResults.append(result) }
        }
        let errors = rawResults.compactMap(\.error)
        return (rawResults, errors)
    }

    /// 双重去重（existingURLs + seenURLs）；丢 nil pubDate；article.category 从 feed 派生；
    /// 未配 filter 或 feed.skipFilter 时 accepted 直接为 true。
    func mergeNewArticles(
        cat: AINewsBar.Category,
        rawResults: [FeedResult],
        existingURLs: Set<String>,
        startOfToday: Date
    ) -> [Article] {
        let config = CategoryConfig.for(cat)
        let needFilter = (config.filterPrompt != nil)
        var newArticles: [Article] = []
        var seenURLs: Set<String> = []
        for result in rawResults {
            let acceptedAtInsert: Bool? = (!needFilter || result.feedSkipFilter) ? true : nil
            for raw in result.articles {
                // 归一化后比对（仅判定"是否同一篇"）；存储仍用原 raw.url 保留追踪参数。
                let key = URLNormalizer.normalize(raw.url)
                guard let pubDate = raw.publishedAt,
                      !existingURLs.contains(key),
                      !seenURLs.contains(key),
                      pubDate >= startOfToday else { continue }
                seenURLs.insert(key)
                newArticles.append(Article(
                    title: raw.title, url: raw.url, content: raw.content,
                    publishedAt: pubDate,
                    feedID: result.feedID, feedTitle: result.feedTitle,
                    category: result.feedCategory,
                    accepted: acceptedAtInsert
                ))
            }
        }
        return newArticles
    }

    // MARK: - Cleanup

    /// per-cat 清旧文章（runRefresh 内用）。严格版：fetch/save 失败抛出，让 caller rollback + 中止，
    /// 避免留 pending delete 给后续路径。
    func cleanupOldArticles(
        context: ModelContext, category: AINewsBar.Category, before date: Date
    ) throws {
        let catRaw = category.rawValue
        let old = try context.safeFetchOrThrow(
            FetchDescriptor<Article>(predicate: #Predicate {
                $0.category == catRaw && $0.publishedAt < date
            })
        )
        guard !old.isEmpty else { return }
        old.forEach { context.delete($0) }
        try context.safeSaveOrThrow()
    }

    /// 全 cat 清旧文章（跨日重置内用）。严格版（与 per-cat 对齐）：失败抛出让 caller 不推进 lastResetCheckDate。
    func cleanupOldArticles(context: ModelContext, before date: Date) throws {
        let old = try context.safeFetchOrThrow(
            FetchDescriptor<Article>(predicate: #Predicate { $0.publishedAt < date })
        )
        guard !old.isEmpty else { return }
        old.forEach { context.delete($0) }
        try context.safeSaveOrThrow()
    }
}
