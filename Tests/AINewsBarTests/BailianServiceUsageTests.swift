import XCTest
@testable import AINewsBar

final class BailianServiceUsageTests: XCTestCase {
    func testParseUsageStandardOpenAIFields() {
        let json: [String: Any] = [
            "usage": [
                "prompt_tokens": 120,
                "completion_tokens": 45,
                "total_tokens": 165
            ]
        ]
        let usage = BailianService.parseUsage(from: json)
        XCTAssertEqual(usage.inputTokens, 120)
        XCTAssertEqual(usage.outputTokens, 45)
        XCTAssertEqual(usage.totalTokens, 165)
    }

    func testParseUsageDashScopeNativeFields() {
        let json: [String: Any] = [
            "usage": [
                "input_tokens": 80,
                "output_tokens": 20
            ]
        ]
        let usage = BailianService.parseUsage(from: json)
        XCTAssertEqual(usage.inputTokens, 80)
        XCTAssertEqual(usage.outputTokens, 20)
    }

    func testParseUsageMissingReturnsZero() {
        XCTAssertEqual(BailianService.parseUsage(from: [:]), .zero)
        XCTAssertEqual(BailianService.parseUsage(from: nil), .zero)
    }

    func testParseUsageNegativeClampedToZero() {
        let json: [String: Any] = [
            "usage": ["prompt_tokens": -5, "completion_tokens": -3]
        ]
        let usage = BailianService.parseUsage(from: json)
        XCTAssertEqual(usage.inputTokens, 0)
        XCTAssertEqual(usage.outputTokens, 0)
    }
}
