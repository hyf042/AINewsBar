import Foundation
import SwiftData

enum BuiltInFeeds {
    /// 内置源完整清单。v2-multi-category 扩展为 27 源（11 AI + 8 财报 + 8 新闻）。
    /// URL 已 curl 验证（2026-05-24 / 2026-05-25 财报源增补中文）。
    /// 财报区中文源依赖 RSSHub 公共镜像 rsshub.rssforever.com（官方直连全 404/HTML）；
    /// 备用镜像 rss.injahow.cn 同路径可用，user 可在设置里手动替换 URL。
    static let all: [(category: Category, title: String, url: String)] = [

        // MARK: - AI tab (11)
        (.ai, "OpenAI News",           "https://openai.com/news/rss.xml"),
        (.ai, "Google DeepMind",       "https://deepmind.google/blog/rss.xml"),
        (.ai, "Hugging Face Blog",     "https://huggingface.co/blog/feed.xml"),
        (.ai, "TechCrunch AI",         "https://techcrunch.com/category/artificial-intelligence/feed/"),
        (.ai, "The Verge AI",          "https://www.theverge.com/rss/ai-artificial-intelligence/index.xml"),
        (.ai, "Ars Technica AI",       "https://arstechnica.com/ai/feed"),
        (.ai, "The Decoder",           "https://the-decoder.com/feed/"),
        (.ai, "MIT Technology Review", "https://www.technologyreview.com/topic/artificial-intelligence/feed"),
        (.ai, "VentureBeat AI",        "https://venturebeat.com/category/ai/feed/"),
        (.ai, "TLDR AI",               "https://tldr.tech/api/rss/ai"),
        (.ai, "量子位",                  "https://www.qbitai.com/feed"),

        // MARK: - 财报 tab (8 = 4 en + 4 zh)
        (.earnings, "Seeking Alpha",      "https://seekingalpha.com/feed.xml"),
        (.earnings, "Apple Newsroom",     "https://www.apple.com/newsroom/rss-feed.rss"),
        (.earnings, "CNBC Top News",      "https://www.cnbc.com/id/100727362/device/rss/rss.html"),
        (.earnings, "Yahoo Finance",      "https://finance.yahoo.com/news/rssindex"),
        (.earnings, "财联社 头条",          "https://rsshub.rssforever.com/cls/depth/1000"),
        (.earnings, "华尔街见闻 全球",       "https://rsshub.rssforever.com/wallstreetcn/news/global"),
        (.earnings, "FT 中文财经",          "https://www.ftchinese.com/rss/feed"),
        (.earnings, "雪球热门",             "https://xueqiu.com/hots/topic/rss"),

        // MARK: - 新闻 tab (8 = 4 en + 4 zh)
        (.news, "BBC News",          "https://feeds.bbci.co.uk/news/rss.xml"),
        (.news, "NYT World",         "https://rss.nytimes.com/services/xml/rss/nyt/World.xml"),
        (.news, "Hacker News Top",   "https://hnrss.org/frontpage"),
        (.news, "The Verge",         "https://www.theverge.com/rss/index.xml"),
        (.news, "36 氪",              "https://36kr.com/feed"),
        (.news, "新华网",              "https://www.xinhuanet.com/politics/news_politics.xml"),
        (.news, "人民日报",            "https://www.people.com.cn/rss/politics.xml"),
        (.news, "FT 中文新闻",         "https://www.ftchinese.com/rss/news"),
    ]

    static func makeFeeds() -> [Feed] {
        all.map { entry in
            Feed(title: entry.title, url: entry.url,
                 isBuiltIn: true, category: entry.category)
        }
    }

    /// 同步内置源到数据库：删除已失效的内置源（含其文章），添加缺失的新源。
    /// 注意：旧版本升级后 v2 全清重建，syncInto 会注入全部 27 源。
    @MainActor
    static func syncInto(context: ModelContext) {
        let expectedURLs = Set(all.map(\.url))
        let expectedByURL = Dictionary(uniqueKeysWithValues: all.map { ($0.url, $0) })
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

        // URL 稳定但元数据变化时也要同步；Article 冗余了 category/feedTitle，
        // category 变化时直接删旧文章，避免跨 tab 污染。
        for feed in existing {
            guard let expected = expectedByURL[feed.url] else { continue }
            let categoryChanged = feed.category != expected.category.rawValue
            let titleChanged = feed.title != expected.title
            if categoryChanged {
                let feedID = feed.id
                let articles = context.safeFetch(
                    FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
                )
                articles.forEach { context.delete($0) }
                feed.category = expected.category.rawValue
            } else if titleChanged {
                let feedID = feed.id
                let articles = context.safeFetch(
                    FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
                )
                articles.forEach { $0.feedTitle = expected.title }
            }
            if titleChanged {
                feed.title = expected.title
            }
        }

        // 添加缺失的新源（含 category 信息）
        let existingURLs = Set(existing.map(\.url))
        all.filter { !existingURLs.contains($0.url) }
            .map { entry in
                Feed(title: entry.title, url: entry.url,
                     isBuiltIn: true, category: entry.category)
            }
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
