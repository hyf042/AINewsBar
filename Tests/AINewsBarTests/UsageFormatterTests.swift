import XCTest
@testable import AINewsBar

final class UsageFormatterTests: XCTestCase {
    func testZero() {
        XCTAssertEqual(UsageFormatter.formatTokens(0), "0")
    }

    func testNegativeClampedToZero() {
        XCTAssertEqual(UsageFormatter.formatTokens(-5), "0")
    }

    func testUnderThousandRawValue() {
        XCTAssertEqual(UsageFormatter.formatTokens(1), "1")
        XCTAssertEqual(UsageFormatter.formatTokens(999), "999")
    }

    func testKiloRoundedToOneDecimal() {
        XCTAssertEqual(UsageFormatter.formatTokens(1_000), "1K")
        XCTAssertEqual(UsageFormatter.formatTokens(1_234), "1.2K")
        XCTAssertEqual(UsageFormatter.formatTokens(12_400), "12.4K")
        XCTAssertEqual(UsageFormatter.formatTokens(999_999), "1000K")
    }

    func testMega() {
        XCTAssertEqual(UsageFormatter.formatTokens(1_000_000), "1M")
        XCTAssertEqual(UsageFormatter.formatTokens(1_234_567), "1.2M")
    }
}
