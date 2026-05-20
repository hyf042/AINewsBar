import XCTest
@testable import AINewsBar

// 仅测纯函数（prompt 构造、序号解析）；HTTP 部分由集成测试覆盖（本仓库不做）
final class BailianServiceTests: XCTestCase {

    // MARK: - parseRecommendResponse（C1: 必须去重 + 越界过滤）

    func testParseStandardEnglishCommas() {
        let result = BailianService.parseRecommendResponse("2,7,15", totalCount: 20)
        XCTAssertEqual(result, [2, 7, 15])
    }

    func testParseChineseCommas() {
        let result = BailianService.parseRecommendResponse("2，7，15", totalCount: 20)
        XCTAssertEqual(result, [2, 7, 15])
    }

    func testParseMixedSeparators() {
        let result = BailianService.parseRecommendResponse("2, 7、 15", totalCount: 20)
        XCTAssertEqual(result, [2, 7, 15])
    }

    func testParseDedup() {
        // C1: 同一序号重复出现应去重
        let result = BailianService.parseRecommendResponse("2,2,3", totalCount: 20)
        XCTAssertEqual(result, [2, 3], "重复序号必须去重")
    }

    func testParseFiltersOutOfRange() {
        let result = BailianService.parseRecommendResponse("0,2,99,5", totalCount: 10)
        XCTAssertEqual(result, [2, 5], "0 和 99 应被过滤")
    }

    func testParseFiltersNegative() {
        let result = BailianService.parseRecommendResponse("-1,3,4", totalCount: 10)
        XCTAssertEqual(result, [3, 4])
    }

    func testParsePicksAtMostThree() {
        let result = BailianService.parseRecommendResponse("1,2,3,4,5", totalCount: 20)
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testParseAfterDedupStillThree() {
        // C1 边界：去重前 5 个，去重后还有 5 个，仍 cap 在 3
        let result = BailianService.parseRecommendResponse("1,2,1,3,4,5", totalCount: 20)
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testParseDedupReducesBelowThree() {
        // C1 关键：模型返回 "2,2,2" 不应返回 [2,2,2]
        let result = BailianService.parseRecommendResponse("2,2,2", totalCount: 20)
        XCTAssertEqual(result, [2], "去重后只有一个")
    }

    func testParseEmptyResponse() {
        XCTAssertEqual(BailianService.parseRecommendResponse("", totalCount: 10), [])
    }

    func testParseNonNumericResponse() {
        XCTAssertEqual(BailianService.parseRecommendResponse("abc, def", totalCount: 10), [])
    }

    func testParsePreservesOrder() {
        // 保序：返回顺序按响应顺序，而非数字大小
        let result = BailianService.parseRecommendResponse("15,3,7", totalCount: 20)
        XCTAssertEqual(result, [15, 3, 7])
    }

    func testParseWithNewlines() {
        let result = BailianService.parseRecommendResponse("2\n7\n15", totalCount: 20)
        XCTAssertEqual(result, [2, 7, 15])
    }

    // MARK: - Prompt 构造

    func testSummaryPromptIncludesTitle() {
        let prompt = BailianService.makeSummaryPrompt(title: "OpenAI 发布新模型", content: "正文内容...")
        XCTAssertTrue(prompt.contains("OpenAI 发布新模型"))
        XCTAssertTrue(prompt.contains("正文内容"))
        XCTAssertTrue(prompt.contains("中文"))
    }

    func testSummaryPromptHandlesNilContent() {
        let prompt = BailianService.makeSummaryPrompt(title: "T", content: nil)
        XCTAssertTrue(prompt.contains("无正文"))
    }

    func testSummaryPromptTruncatesLongContent() {
        let long = String(repeating: "a", count: 3000)
        let prompt = BailianService.makeSummaryPrompt(title: "T", content: long)
        // prompt 包含前 1500 字符但不应包含完整 3000
        XCTAssertFalse(prompt.contains(long))
        XCTAssertTrue(prompt.contains(String(repeating: "a", count: 1500)))
    }

    func testRecommendPromptIncludesNumberedList() {
        let items: [ArticleSnapshot.Item] = [
            .init(id: UUID(), title: "A", summary: "sa"),
            .init(id: UUID(), title: "B", summary: nil),
            .init(id: UUID(), title: "C", summary: "sc")
        ]
        let prompt = BailianService.makeRecommendPrompt(items: items)
        XCTAssertTrue(prompt.contains("1. A"))
        XCTAssertTrue(prompt.contains("2. B"))
        XCTAssertTrue(prompt.contains("3. C"))
        XCTAssertTrue(prompt.contains("挑选3篇"))
    }

    func testRecommendPromptCapsAt50() {
        let items = (0..<100).map { i in
            ArticleSnapshot.Item(id: UUID(), title: "T\(i)", summary: "s\(i)")
        }
        let prompt = BailianService.makeRecommendPrompt(items: items)
        XCTAssertTrue(prompt.contains("50. T49"))
        XCTAssertFalse(prompt.contains("51. T50"), "超过 50 的应被截断")
    }

    func testDigestPromptIncludesEntries() {
        let items: [ArticleSnapshot.Item] = [
            .init(id: UUID(), title: "A", summary: "sa"),
            .init(id: UUID(), title: "B", summary: "sb")
        ]
        let prompt = BailianService.makeDigestPrompt(items: items)
        XCTAssertTrue(prompt.contains("A｜sa"))
        XCTAssertTrue(prompt.contains("B｜sb"))
        XCTAssertTrue(prompt.contains("中文"))
    }

    func testDigestPromptCapsAt20() {
        let items = (0..<30).map { i in
            ArticleSnapshot.Item(id: UUID(), title: "T\(i)", summary: "s\(i)")
        }
        let prompt = BailianService.makeDigestPrompt(items: items)
        XCTAssertTrue(prompt.contains("T19｜s19"))
        XCTAssertFalse(prompt.contains("T20｜s20"))
    }

    func testDigestPromptSkipsNilSummary() {
        // 防御：caller 通常已传 summarized，但 nil 项不应崩
        let items: [ArticleSnapshot.Item] = [
            .init(id: UUID(), title: "A", summary: "sa"),
            .init(id: UUID(), title: "B", summary: nil),
            .init(id: UUID(), title: "C", summary: "sc")
        ]
        let prompt = BailianService.makeDigestPrompt(items: items)
        XCTAssertTrue(prompt.contains("A｜sa"))
        XCTAssertFalse(prompt.contains("- B"), "nil-summary 项应跳过")
        XCTAssertTrue(prompt.contains("C｜sc"))
    }
}
