import XCTest
@testable import AINewsBar

final class ArticleTests: XCTestCase {
    func testInitDefaults() {
        let feedID = UUID()
        let date = Date()
        let article = Article(title: "T", url: "https://e.com", content: nil,
                              publishedAt: date, feedID: feedID, feedTitle: "F")
        XCTAssertEqual(article.title, "T")
        XCTAssertEqual(article.url, "https://e.com")
        XCTAssertNil(article.content)
        XCTAssertEqual(article.publishedAt, date)
        XCTAssertEqual(article.feedID, feedID)
        XCTAssertEqual(article.feedTitle, "F")
        XCTAssertFalse(article.isRead, "新建文章应未读")
        XCTAssertNil(article.aiSummary, "新建文章无 AI 摘要")
    }

    func testIDIsUniquePerInstance() {
        let a1 = Article(title: "A", url: "u", publishedAt: Date(), feedID: UUID(), feedTitle: "F")
        let a2 = Article(title: "B", url: "u", publishedAt: Date(), feedID: UUID(), feedTitle: "F")
        XCTAssertNotEqual(a1.id, a2.id, "默认 ID 应不同")
    }

    func testExplicitID() {
        let id = UUID()
        let article = Article(id: id, title: "T", url: "u",
                              publishedAt: Date(), feedID: UUID(), feedTitle: "F")
        XCTAssertEqual(article.id, id)
    }
}

final class FeedTests: XCTestCase {
    func testInitDefaults() {
        let before = Date()
        let feed = Feed(title: "T", url: "https://e.com/feed")
        let after = Date()

        XCTAssertEqual(feed.title, "T")
        XCTAssertEqual(feed.url, "https://e.com/feed")
        XCTAssertNil(feed.iconURL)
        XCTAssertFalse(feed.isBuiltIn, "默认非内置")
        XCTAssertTrue(feed.isEnabled, "默认启用")
        XCTAssertGreaterThanOrEqual(feed.addedAt, before)
        XCTAssertLessThanOrEqual(feed.addedAt, after)
    }

    func testInitWithBuiltIn() {
        let feed = Feed(title: "T", url: "u", isBuiltIn: true, isEnabled: false)
        XCTAssertTrue(feed.isBuiltIn)
        XCTAssertFalse(feed.isEnabled)
    }
}
