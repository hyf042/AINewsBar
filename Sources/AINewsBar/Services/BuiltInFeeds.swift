import Foundation
import SwiftData

enum BuiltInFeeds {
    static let all: [(title: String, url: String)] = [
        // 官方研究博客
        ("OpenAI News",           "https://openai.com/news/rss.xml"),
        ("Google DeepMind",       "https://deepmind.google/blog/rss.xml"),
        ("Hugging Face Blog",     "https://huggingface.co/blog/feed.xml"),
        // 科技媒体 AI 专栏
        ("TechCrunch AI",         "https://techcrunch.com/category/artificial-intelligence/feed/"),
        ("The Verge AI",          "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml"),
        ("Ars Technica AI",       "https://arstechnica.com/ai/feed"),
        ("The Decoder",           "https://the-decoder.com/feed/"),
        ("MIT Technology Review", "https://www.technologyreview.com/topic/artificial-intelligence/feed"),
        ("VentureBeat AI",        "https://venturebeat.com/category/ai/feed/"),
        // 日报 / 速读
        ("TLDR AI",               "https://tldr.tech/api/rss/ai"),
        // 中文
        ("量子位",                  "https://www.qbitai.com/feed"),
    ]

    static func makeFeeds() -> [Feed] {
        all.map { Feed(title: $0.title, url: $0.url, isBuiltIn: true) }
    }

    /// 同步内置源到数据库：删除已失效的内置源（含其文章），添加缺失的新源
    @MainActor
    static func syncInto(context: ModelContext) {
        let expectedURLs = Set(all.map(\.url))
        let existing = context.safeFetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.isBuiltIn == true })
        )

        // 删除已失效的内置源及其文章
        let toRemove = existing.filter { !expectedURLs.contains($0.url) }
        for feed in toRemove {
            let feedID = feed.id
            let orphans = context.safeFetch(
                FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
            )
            orphans.forEach { context.delete($0) }
            context.delete(feed)
        }

        // 添加缺失的新源
        let existingURLs = Set(existing.map(\.url))
        all.filter { !existingURLs.contains($0.url) }
            .map { Feed(title: $0.title, url: $0.url, isBuiltIn: true) }
            .forEach { context.insert($0) }

        context.safeSave()
    }

    /// 容灾去重：按 URL 移除重复文章，保留 publishedAt 最新的一条。
    /// 仅在 ModelContainer 重建路径调用；正常启动跳过（refresh 已做双重去重）。
    @MainActor
    static func deduplicateArticles(context: ModelContext) {
        let all = context.safeFetch(
            FetchDescriptor<Article>(sortBy: [SortDescriptor(\.publishedAt, order: .reverse)])
        )
        var seen = Set<String>()
        for article in all {
            if seen.contains(article.url) {
                context.delete(article)
            } else {
                seen.insert(article.url)
            }
        }
        context.safeSave()
    }
}
