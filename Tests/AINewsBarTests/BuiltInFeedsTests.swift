import XCTest
@testable import AINewsBar

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

    func testTotalCountIs27() {
        XCTAssertEqual(BuiltInFeeds.all.count, 27, "v2 内置源总数应为 27 (11 AI + 8 财报 + 8 新闻)")
    }

    func testCategoryDistribution() {
        let byCat = Dictionary(grouping: BuiltInFeeds.all, by: \.category)
        XCTAssertEqual(byCat[.ai]?.count, 11, "AI tab 应有 11 个内置源")
        XCTAssertEqual(byCat[.earnings]?.count, 8, "财报 tab 应有 8 个内置源")
        XCTAssertEqual(byCat[.news]?.count, 8, "新闻 tab 应有 8 个内置源")
    }

    func testMakeFeedsPropagatesCategory() {
        let feeds = BuiltInFeeds.makeFeeds()
        let aiCount = feeds.filter { $0.category == Category.ai.rawValue }.count
        let earningsCount = feeds.filter { $0.category == Category.earnings.rawValue }.count
        let newsCount = feeds.filter { $0.category == Category.news.rawValue }.count
        XCTAssertEqual(aiCount, 11)
        XCTAssertEqual(earningsCount, 8)
        XCTAssertEqual(newsCount, 8)
    }
}
