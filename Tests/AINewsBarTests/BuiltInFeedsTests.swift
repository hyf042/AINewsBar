import XCTest
import SwiftData
@testable import AINewsBar

@MainActor
final class BuiltInFeedsTests: XCTestCase {
    func testAllSourcesUseHTTPS() {
        for entry in BuiltInFeeds.all {
            XCTAssertTrue(entry.url.hasPrefix("https://"),
                          "源 \(entry.title) 不是 https: \(entry.url)")
        }
    }

    func testNoEmptyTitlesOrURLs() {
        for entry in BuiltInFeeds.all {
            XCTAssertFalse(entry.title.isEmpty)
            XCTAssertFalse(entry.url.isEmpty)
        }
    }

    func testURLsAreUnique() {
        let urls = BuiltInFeeds.all.map(\.url)
        XCTAssertEqual(Set(urls).count, urls.count, "内置源 URL 不可重复")
    }

    func testURLsAreValidURL() {
        for entry in BuiltInFeeds.all {
            XCTAssertNotNil(URL(string: entry.url), "无效 URL: \(entry.url)")
        }
    }

    func testMakeFeedsAllBuiltIn() {
        let feeds = BuiltInFeeds.makeFeeds()
        XCTAssertEqual(feeds.count, BuiltInFeeds.all.count)
        XCTAssertTrue(feeds.allSatisfy(\.isBuiltIn))
        XCTAssertTrue(feeds.allSatisfy(\.isEnabled))
    }

    // MARK: - Multi-Category (v2)

    func testTotalCountIs26() {
        XCTAssertEqual(BuiltInFeeds.all.count, 26, "v2 内置源总数应为 26 (11 AI + 8 财报 + 7 新闻)")
    }

    func testCategoryDistribution() {
        let byCat = Dictionary(grouping: BuiltInFeeds.all, by: \.category)
        XCTAssertEqual(byCat[.ai]?.count, 11, "AI tab 应有 11 个内置源")
        XCTAssertEqual(byCat[.earnings]?.count, 8, "财报 tab 应有 8 个内置源")
        XCTAssertEqual(byCat[.news]?.count, 7, "新闻 tab 应有 7 个内置源")
    }

    func testMakeFeedsPropagatesCategory() {
        let feeds = BuiltInFeeds.makeFeeds()
        let aiCount = feeds.filter { $0.category == Category.ai.rawValue }.count
        let earningsCount = feeds.filter { $0.category == Category.earnings.rawValue }.count
        let newsCount = feeds.filter { $0.category == Category.news.rawValue }.count
        XCTAssertEqual(aiCount, 11)
        XCTAssertEqual(earningsCount, 8)
        XCTAssertEqual(newsCount, 7)
    }

    // MARK: - 第十四轮 P3：URLNormalizer 应用于 syncInto

    /// 用户已有同 URL 自定义源（仅 host 大小写不同），syncInto 不应再插入内置源 →
    /// 否则同一资源两条 feed 共存（重复 fetch / 重复显示 / 失败统计噪声）。
    ///
    /// **第十五轮 P3 review**：旧测试 path 用 `/news/RSS.xml`（大小写不同于内置的
    /// `/news/rss.xml`），normalizer 视为不同 URL → custom + builtIn 共存两条，
    /// "Set 去重后元素数相等"恒成立 → 测试**挡不住 exact-match 回归**。
    /// 新数据：path 用 `/news/rss.xml`（host 大小写 = 仅有差异点），断言 OpenAI
    /// 相关 feed 总数 == 1。这才能真正捕捉到去重逻辑失效。
    func testSyncSkipsBuiltInWhenCustomFeedExistsWithDifferentCase() throws {
        let (container, ctx) = try TestContainer.make()
        _ = container

        // 模拟用户已有自定义源：仅 host 大小写与内置 OpenAI News 不同
        let custom = Feed(
            title: "我的 OpenAI 订阅",
            url: "https://OPENAI.com/news/rss.xml",
            isBuiltIn: false,
            category: .ai
        )
        ctx.insert(custom)
        try ctx.save()

        let synced = BuiltInFeeds.syncInto(context: ctx)
        XCTAssertTrue(synced)

        let allFeeds = try ctx.fetch(FetchDescriptor<Feed>())
        // 归一化后等价的 OpenAI feed 只应有 1 条（用户自己保留）。
        // 退化为 exact match 时这里会失败（2 条共存）→ 测试有真实回归挡力。
        let openaiFeeds = allFeeds.filter {
            URLNormalizer.normalize($0.url).contains("openai.com/news/rss.xml")
        }
        XCTAssertEqual(openaiFeeds.count, 1,
                       "host 大小写归一化等价时，custom 应阻止内置源重复插入；exact-match 回归会让此处变 2")
        XCTAssertFalse(openaiFeeds.first?.isBuiltIn ?? true,
                       "保留的应是用户自定义源（先入库者）")
    }

    /// 内置源 URL 仅 host 大小写改写过（模拟历史脏 feed 已入库）→ syncInto 不删它，
    /// 不重新插入（保持原状）。
    func testSyncTolersHistoricalCaseDifferenceOnBuiltInURL() throws {
        let (container, ctx) = try TestContainer.make()
        _ = container

        // 模拟旧版本写入的内置源 URL 含大写
        let historical = Feed(
            title: "OpenAI News",
            url: "https://OpenAI.com/news/rss.xml",
            isBuiltIn: true,
            category: .ai
        )
        ctx.insert(historical)
        try ctx.save()

        let synced = BuiltInFeeds.syncInto(context: ctx)
        XCTAssertTrue(synced)

        // 仍只有一条 OpenAI 源（不重复插入）
        let allFeeds = try ctx.fetch(FetchDescriptor<Feed>())
        let openaiSources = allFeeds.filter {
            URLNormalizer.normalize($0.url).contains("openai.com/news")
        }
        XCTAssertEqual(openaiSources.count, 1, "host 大小写等价不应触发重复插入")
    }

    // MARK: - 第十四轮 P3：deduplicateArticles URL 归一化

    /// 容灾去重：URL 仅大小写/尾斜杠不同的文章应视为同一篇，保留 publishedAt 最新的
    func testDeduplicateRemovesURLsDifferingOnlyByCaseOrSlash() throws {
        let (container, ctx) = try TestContainer.make()
        _ = container

        let feed = Feed(title: "F", url: "https://a.com/feed", category: .ai)
        ctx.insert(feed)

        let now = Date()
        let older = now.addingTimeInterval(-3600)
        let articles = [
            // 三个 URL 归一化后等价：host 大小写 + 尾斜杠 + fragment
            Article(title: "T1", url: "https://Example.com/post/", publishedAt: now,
                    feedID: feed.id, feedTitle: feed.title, category: .ai),
            Article(title: "T1 dup", url: "https://example.com/post", publishedAt: older,
                    feedID: feed.id, feedTitle: feed.title, category: .ai),
            Article(title: "T1 dup2", url: "https://example.com/post#anchor", publishedAt: older,
                    feedID: feed.id, feedTitle: feed.title, category: .ai),
            // 不同 path（大小写敏感）—— 保留
            Article(title: "T2", url: "https://example.com/Post", publishedAt: now,
                    feedID: feed.id, feedTitle: feed.title, category: .ai),
        ]
        articles.forEach { ctx.insert($0) }
        try ctx.save()

        BuiltInFeeds.deduplicateArticles(context: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<Article>())
        XCTAssertEqual(remaining.count, 2, "归一化等价的 3 篇应只剩 1 篇，/Post 与 /post 大小写敏感保留")
        let normalizedKeys = Set(remaining.map { URLNormalizer.normalize($0.url) })
        XCTAssertEqual(normalizedKeys.count, 2)
    }
}
