import XCTest
import FeedKit
@testable import AINewsBar

final class RSSServiceTests: XCTestCase {
    private final class HTTPStatusURLProtocol: URLProtocol {
        static var statusCode = 500
        static var body = Data("upstream error".utf8)
        static var receivedUserAgent: String?
        static var receivedAccept: String?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.receivedUserAgent = request.value(forHTTPHeaderField: "User-Agent")
            Self.receivedAccept = request.value(forHTTPHeaderField: "Accept")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

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

    func testHTTPStatusErrorThrownBeforeParsing() async {
        HTTPStatusURLProtocol.statusCode = 429
        HTTPStatusURLProtocol.body = Data("too many requests".utf8)
        HTTPStatusURLProtocol.receivedUserAgent = nil
        HTTPStatusURLProtocol.receivedAccept = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStatusURLProtocol.self]
        let service = RSSService(session: URLSession(configuration: config))

        do {
            _ = try await service.fetchRawArticles(feedURL: "https://example.com/feed.xml")
            XCTFail("HTTP 429 应在 FeedKit 解析前变成明确错误")
        } catch RSSFetchError.httpStatus(let code) {
            XCTAssertEqual(code, 429)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFetchSendsBrowserLikeUserAgent() async throws {
        HTTPStatusURLProtocol.statusCode = 200
        HTTPStatusURLProtocol.body = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Example</title>
            <item>
              <title>Item</title>
              <link>https://example.com/1</link>
              <pubDate>Mon, 25 May 2026 08:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """.utf8)
        HTTPStatusURLProtocol.receivedUserAgent = nil
        HTTPStatusURLProtocol.receivedAccept = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStatusURLProtocol.self]
        let service = RSSService(session: URLSession(configuration: config))

        _ = try await service.fetchRawArticles(feedURL: "https://example.com/feed.xml")

        XCTAssertEqual(HTTPStatusURLProtocol.receivedUserAgent, RSSService.userAgent)
        XCTAssertTrue(HTTPStatusURLProtocol.receivedAccept?.contains("application/rss+xml") == true)
    }
}
