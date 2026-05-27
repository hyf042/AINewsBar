import XCTest
@testable import AINewsBar

final class URLNormalizerTests: XCTestCase {

    // MARK: - 等价（应归一化为同一 key）

    func testHostIsLowercased() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://Example.COM/foo"),
            URLNormalizer.normalize("https://example.com/foo")
        )
    }

    func testSchemeIsLowercased() {
        XCTAssertEqual(
            URLNormalizer.normalize("HTTPS://example.com/foo"),
            URLNormalizer.normalize("https://example.com/foo")
        )
    }

    func testTrailingSlashRemovedFromPath() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://a.com/foo/"),
            URLNormalizer.normalize("https://a.com/foo")
        )
    }

    func testFragmentStripped() {
        XCTAssertEqual(
            URLNormalizer.normalize("https://a.com/foo#section-1"),
            URLNormalizer.normalize("https://a.com/foo")
        )
    }

    func testWhitespaceTrimmed() {
        XCTAssertEqual(
            URLNormalizer.normalize("  https://a.com/foo\n"),
            URLNormalizer.normalize("https://a.com/foo")
        )
    }

    func testCombinedNormalizations() {
        let a = URLNormalizer.normalize("  HTTPS://Example.COM/foo/#bar\n")
        let b = URLNormalizer.normalize("https://example.com/foo")
        XCTAssertEqual(a, b)
    }

    // MARK: - 不等价（保守：宁可漏归一化重复入库一次，不能误合并）

    /// 不同 scheme 视为不同（http 明文 vs https）
    func testDifferentSchemeIsDistinct() {
        XCTAssertNotEqual(
            URLNormalizer.normalize("http://a.com/foo"),
            URLNormalizer.normalize("https://a.com/foo")
        )
    }

    /// path 大小写敏感（RFC 3986）：/Foo ≠ /foo
    func testPathCaseIsPreserved() {
        XCTAssertNotEqual(
            URLNormalizer.normalize("https://a.com/Foo"),
            URLNormalizer.normalize("https://a.com/foo")
        )
    }

    /// query 必须保留，不删任何参数（utm_*、id=*、format=rss 都不能丢）
    func testQueryIsPreserved() {
        XCTAssertNotEqual(
            URLNormalizer.normalize("https://a.com/foo?id=123"),
            URLNormalizer.normalize("https://a.com/foo")
        )
    }

    /// query 大小写敏感保留
    func testQueryCaseIsPreserved() {
        XCTAssertNotEqual(
            URLNormalizer.normalize("https://a.com/foo?Id=abc"),
            URLNormalizer.normalize("https://a.com/foo?id=abc")
        )
    }

    /// 不同 path 是不同 URL
    func testDifferentPathsAreDistinct() {
        XCTAssertNotEqual(
            URLNormalizer.normalize("https://a.com/foo"),
            URLNormalizer.normalize("https://a.com/bar")
        )
    }

    // MARK: - 边界（root path 不被吃）

    /// root path "/" 不应被剥成空字符串
    func testRootPathSlashIsPreserved() {
        let a = URLNormalizer.normalize("https://a.com/")
        let b = URLNormalizer.normalize("https://a.com")
        // root path 情形：URLComponents 保留 "/"，无 path 时为 ""
        // 两者都是合法表达的"网站首页"，应等价
        XCTAssertEqual(a, b)
    }

    // MARK: - Fallback（非合法 URL 不崩，走 lowercase + trim）

    func testFallbackForNonHTTPScheme() {
        // javascript: 等非 HTTP scheme host=nil，走 fallback
        let result = URLNormalizer.normalize("  JAVASCRIPT:alert(1)  ")
        XCTAssertEqual(result, "javascript:alert(1)")
    }

    func testFallbackForEmptyString() {
        XCTAssertEqual(URLNormalizer.normalize(""), "")
        XCTAssertEqual(URLNormalizer.normalize("   "), "")
    }
}
