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
}
