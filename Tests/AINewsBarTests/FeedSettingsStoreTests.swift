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
