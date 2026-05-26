import SwiftData
import XCTest
@testable import AINewsBar

@MainActor
final class FeedSettingsStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        (container, context) = try TestContainer.make()
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    func testDisablingBuiltInFeedDeletesItsArticlesButKeepsFeed() throws {
        let feed = Feed(title: "Built In", url: "https://example.com/feed.xml", isBuiltIn: true)
        let article = Article(
            title: "Article",
            url: "https://example.com/article",
            publishedAt: Date(),
            feedID: feed.id,
            feedTitle: feed.title,
            accepted: true
        )
        context.insert(feed)
        context.insert(article)
        try context.save()

        feed.isEnabled = false
        try FeedSettingsStore.persistBuiltInEnabledChange(feed: feed, enabled: false, in: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let articles = try context.fetch(FetchDescriptor<Article>())
        XCTAssertEqual(feeds.count, 1)
        XCTAssertFalse(feeds[0].isEnabled)
        XCTAssertTrue(articles.isEmpty)
    }

    func testEnablingBuiltInFeedDoesNotDeleteExistingArticles() throws {
        let feed = Feed(
            title: "Built In",
            url: "https://example.com/feed.xml",
            isBuiltIn: true,
            isEnabled: false
        )
        let article = Article(
            title: "Article",
            url: "https://example.com/article",
            publishedAt: Date(),
            feedID: feed.id,
            feedTitle: feed.title,
            accepted: true
        )
        context.insert(feed)
        context.insert(article)
        try context.save()

        feed.isEnabled = true
        try FeedSettingsStore.persistBuiltInEnabledChange(feed: feed, enabled: true, in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Article>()).count, 1)
    }

    // MARK: - 第九轮 P2：skipFilter 开启清理旧 pending

    /// 开启 skipFilter 时，该 feed 下 accepted==nil 的旧文章应被 flip → accepted=true。
    /// 其他 feed 的文章和 accepted=false 已 reject 的文章都不动。
    func testEnablingSkipFilterFlipsPendingArticlesToAccepted() throws {
        let feed = Feed(title: "Pure", url: "https://example.com/pure.xml",
                        category: .earnings)
        let otherFeed = Feed(title: "Other", url: "https://example.com/other.xml",
                             category: .earnings)
        let pendingA = Article(title: "Pending A", url: "https://example.com/a",
                               publishedAt: Date(), feedID: feed.id, feedTitle: feed.title,
                               category: .earnings, accepted: nil)
        let pendingB = Article(title: "Pending B", url: "https://example.com/b",
                               publishedAt: Date(), feedID: feed.id, feedTitle: feed.title,
                               category: .earnings, accepted: nil)
        let rejected = Article(title: "Rejected", url: "https://example.com/r",
                               publishedAt: Date(), feedID: feed.id, feedTitle: feed.title,
                               category: .earnings, accepted: false)
        let otherPending = Article(title: "Other Pending", url: "https://example.com/op",
                                   publishedAt: Date(), feedID: otherFeed.id,
                                   feedTitle: otherFeed.title, category: .earnings, accepted: nil)
        for entity in [feed, otherFeed] { context.insert(entity) }
        for entity in [pendingA, pendingB, rejected, otherPending] { context.insert(entity) }
        try context.save()

        let updated = try FeedSettingsStore.persistSkipFilterChange(
            feed: feed, newValue: true, in: context
        )

        XCTAssertEqual(updated, 2, "仅该 feed 下两条 accepted=nil 文章应被更新")
        let articles = try context.fetch(FetchDescriptor<Article>())
        let byID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        XCTAssertEqual(byID[pendingA.id]?.accepted, true)
        XCTAssertEqual(byID[pendingB.id]?.accepted, true)
        XCTAssertEqual(byID[rejected.id]?.accepted, false, "已 reject 不动")
        XCTAssertEqual(byID[otherPending.id]?.accepted, nil, "其他 feed 的 pending 不动")
    }

    /// 关闭 skipFilter 不反向 flip 已 accepted=true 的旧文章（避免过度设计）。
    func testDisablingSkipFilterDoesNotResetAccepted() throws {
        let feed = Feed(title: "Pure", url: "https://example.com/pure.xml",
                        category: .earnings, skipFilter: true)
        let accepted = Article(title: "Already accepted", url: "https://example.com/a",
                               publishedAt: Date(), feedID: feed.id, feedTitle: feed.title,
                               category: .earnings, accepted: true)
        context.insert(feed)
        context.insert(accepted)
        try context.save()

        let updated = try FeedSettingsStore.persistSkipFilterChange(
            feed: feed, newValue: false, in: context
        )

        XCTAssertEqual(updated, 0)
        let articles = try context.fetch(FetchDescriptor<Article>())
        XCTAssertEqual(articles.first?.accepted, true, "已通过的文章保持 accepted=true")
    }

    func testDeletingCustomFeedDeletesItsArticles() throws {
        let feed = Feed(title: "Custom", url: "https://example.com/feed.xml")
        let otherFeed = Feed(title: "Other", url: "https://example.com/other.xml")
        let article = Article(
            title: "Article",
            url: "https://example.com/article",
            publishedAt: Date(),
            feedID: feed.id,
            feedTitle: feed.title,
            accepted: true
        )
        let otherArticle = Article(
            title: "Other",
            url: "https://example.com/other",
            publishedAt: Date(),
            feedID: otherFeed.id,
            feedTitle: otherFeed.title,
            accepted: true
        )
        context.insert(feed)
        context.insert(otherFeed)
        context.insert(article)
        context.insert(otherArticle)
        try context.save()

        try FeedSettingsStore.deleteCustomFeeds([feed], in: context)

        let feeds = try context.fetch(FetchDescriptor<Feed>())
        let articles = try context.fetch(FetchDescriptor<Article>())
        XCTAssertEqual(feeds.map(\.id), [otherFeed.id])
        XCTAssertEqual(articles.map(\.id), [otherArticle.id])
    }
}
