import Foundation
import SwiftData

enum BuiltInFeeds {
    /// 内置源完整清单。v2-multi-category：26 源（11 AI + 8 财报 + 7 新闻）。
    /// URL 已 curl 验证（2026-05-24 / 2026-05-25 财报源增补中文 / 2026-05-29 新闻源聚焦时政社会国际）。
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

        // MARK: - 新闻 tab (7 = 时政/社会/国际，去科技去娱乐)
        // 2026-05-29 重构：聚焦实时/社会/国际新闻。删旧科技源（HN/The Verge/36氪，
        // 科技交给 AI tab）；BBC 综合换成分版块 World（去娱乐/体育噪声）；
        // 补社会民生维度（新华社会版官方直连 + 澎湃市场化视角）。国内 4 / 国际 3 均衡。
        (.news, "NYT World",         "https://rss.nytimes.com/services/xml/rss/nyt/World.xml"),
        (.news, "BBC World",         "https://feeds.bbci.co.uk/news/world/rss.xml"),
        (.news, "FT 中文新闻",         "https://www.ftchinese.com/rss/news"),
        (.news, "新华网 时政",         "https://www.xinhuanet.com/politics/news_politics.xml"),
        (.news, "人民日报 时政",       "https://www.people.com.cn/rss/politics.xml"),
        (.news, "新华网 社会",         "https://www.xinhuanet.com/society/news_society.xml"),
        // 澎湃走 RSSHub 公共镜像（同财报 tab known-risk；备用 rss.injahow.cn 同路径）
        (.news, "澎湃新闻",            "https://rsshub.rssforever.com/thepaper/featured"),
    ]

    static func makeFeeds() -> [Feed] {
        all.map { entry in
            Feed(title: entry.title, url: entry.url,
                 isBuiltIn: true, category: entry.category)
        }
    }

    /// 同步内置源到数据库：删除已失效的内置源（含其文章），添加缺失的新源。
    /// 注意：旧版本升级后 v2 全清重建，syncInto 会注入全部 27 源。
    ///
    /// **第十四轮 P3 review**：URL 比对统一走 `URLNormalizer.normalize`。旧 exact match
    /// 让历史用户自定义源 (e.g. `https://Example.com/feed/`) 与内置源 (`https://example.com/feed`)
    /// 视为不同 → 同一资源两条 feed 共存。与 RefreshService 入库去重 + AddFeedSheet 添加去重
    /// 保持一致归一化规则。
    @MainActor
    @discardableResult
    static func syncInto(context: ModelContext) -> Bool {
        let expectedURLs = Set(all.map { URLNormalizer.normalize($0.url) })
        let expectedByURL = Dictionary(
            uniqueKeysWithValues: all.map { (URLNormalizer.normalize($0.url), $0) }
        )
        let existing: [Feed]
        do {
            existing = try context.safeFetchOrThrow(
                FetchDescriptor<Feed>(predicate: #Predicate { $0.isBuiltIn == true })
            )
        } catch {
            Log.write("[Feeds] sync aborted: built-in feed fetch failed: \(error)")
            return false
        }

        do {
            // 删除已失效的内置源及其文章
            let toRemove = existing.filter { !expectedURLs.contains(URLNormalizer.normalize($0.url)) }
            for feed in toRemove {
                let feedID = feed.id
                let orphans = try context.safeFetchOrThrow(
                    FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
                )
                orphans.forEach { context.delete($0) }
                context.delete(feed)
            }

            // URL 稳定但元数据变化时也要同步；Article 冗余了 category/feedTitle，
            // category 变化时直接删旧文章，避免跨 tab 污染。
            // M2: 先改 feed.category 再删 articles（按 feedID 查不按 category）。
            // 旧实现先删再改，若中间出错 rollback 后 feed.category 仍是旧值，
            // 下次启动反复重试同一删除。新顺序对 rollback 等价（事务原子），
            // 但成功路径下"feed.category 与 articles 状态"始终一致。
            for feed in existing {
                guard let expected = expectedByURL[URLNormalizer.normalize(feed.url)] else { continue }
                let categoryChanged = feed.category != expected.category.rawValue
                let titleChanged = feed.title != expected.title
                let feedID = feed.id
                if categoryChanged {
                    feed.category = expected.category.rawValue
                    let articles = try context.safeFetchOrThrow(
                        FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
                    )
                    articles.forEach { context.delete($0) }
                } else if titleChanged {
                    let articles = try context.safeFetchOrThrow(
                        FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
                    )
                    articles.forEach { $0.feedTitle = expected.title }
                }
                if titleChanged {
                    feed.title = expected.title
                }
            }

            // 添加缺失的新源（含 category 信息）。
            // P3 第七轮 review：插入去重必须扫**所有** feed URL（含 custom），不能只
            // 扫 built-in。否则用户已有的同 URL 自定义源在该 URL 被加入内置源时会被
            // 忽略，导致两条同 URL feed 共存（重复 fetch / 重复显示 / 失败统计噪声）。
            // 删除 / 元数据同步仍只动 built-in（custom 由用户管理）。
            let allFeeds = try context.safeFetchOrThrow(FetchDescriptor<Feed>())
            let anyExistingURLs = Set(allFeeds.map { URLNormalizer.normalize($0.url) })
            all.filter { !anyExistingURLs.contains(URLNormalizer.normalize($0.url)) }
                .map { entry in
                    Feed(title: entry.title, url: entry.url,
                         isBuiltIn: true, category: entry.category)
                }
                .forEach { context.insert($0) }

            try context.safeSaveOrThrow()
            return true
        } catch {
            context.rollback()
            Log.write("[Feeds] sync aborted: \(error)")
            return false
        }
    }

    /// 容灾去重：按 URL 移除重复文章，保留 publishedAt 最新的一条。
    /// 仅在 ModelContainer 重建路径调用；正常启动跳过（refresh 已做双重去重）。
    ///
    /// **第十四轮 P3 review**：用 URLNormalizer.normalize 做去重 key —
    /// "/foo" vs "/foo/" / Example.com vs example.com / #fragment 差异都视为同一篇。
    @MainActor
    static func deduplicateArticles(context: ModelContext) {
        let all = context.safeFetch(
            FetchDescriptor<Article>(sortBy: [SortDescriptor(\.publishedAt, order: .reverse)])
        )
        var seen = Set<String>()
        for article in all {
            let key = URLNormalizer.normalize(article.url)
            if seen.contains(key) {
                context.delete(article)
            } else {
                seen.insert(key)
            }
        }
        context.safeSave()
    }
}
