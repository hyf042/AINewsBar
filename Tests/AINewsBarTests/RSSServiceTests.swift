import XCTest
import FeedKit
@testable import AINewsBar

final class RSSServiceTests: XCTestCase {
    func testAtomUpdatedFallbackWhenPublishedMissing() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Example</title>
          <id>https://example.com/</id>
          <updated>2026-05-25T00:00:00Z</updated>
          <entry>
            <title>Updated-only item</title>
            <id>https://example.com/1</id>
            <link href="https://example.com/1"/>
            <updated>2026-05-25T12:34:56Z</updated>
            <summary>Hello</summary>
          </entry>
        </feed>
        """
        let feed = try FeedParser(data: Data(xml.utf8)).parse().get()

        let articles = RSSService.extract(from: feed)

        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles.first?.title, "Updated-only item")
        XCTAssertNotNil(articles.first?.publishedAt)
    }
}
