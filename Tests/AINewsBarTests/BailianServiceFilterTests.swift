import XCTest
@testable import AINewsBar

/// v2-multi-category: BailianService 的 Filter prompt 装配 + 响应解析 +
/// per-cat prompt 文案差异化测试。
final class BailianServiceFilterTests: XCTestCase {

    // MARK: - makeFilterPrompt 占位符替换

    func testFilterPromptReplacesPlaceholders() {
        let template = "判断 <title> ：<description>"
        let result = BailianService.makeFilterPrompt(
            template: template, title: "苹果财报", description: "Q3 营收 1000 亿"
        )
        XCTAssertEqual(result, "判断 苹果财报 ：Q3 营收 1000 亿")
    }

    func testFilterPromptTruncatesLongDescription() {
        let template = "<description>"
        let long = String(repeating: "x", count: 500)
        let result = BailianService.makeFilterPrompt(
            template: template, title: "T", description: long
        )
        XCTAssertEqual(result.count, 200, "description 应截至前 200 字")
    }

    // MARK: - parseFilterResponse

    func testParseFilterResponseAccepts是() {
        XCTAssertEqual(BailianService.parseFilterResponse("是"), true)
    }

    func testParseFilterResponseRejects否() {
        XCTAssertEqual(BailianService.parseFilterResponse("否"), false)
    }

    func testParseFilterResponseTolerates是的Prefix() {
        XCTAssertEqual(BailianService.parseFilterResponse("是的，这是苹果财报"), true,
                       "首字符匹配应容错")
        XCTAssertEqual(BailianService.parseFilterResponse("否，因为属于宏观"), false)
    }

    func testParseFilterResponseTrimsWhitespace() {
        XCTAssertEqual(BailianService.parseFilterResponse("  是  "), true)
        XCTAssertEqual(BailianService.parseFilterResponse("\n否\n"), false)
    }

    func testParseFilterResponseReturnsNilOnEmpty() {
        XCTAssertNil(BailianService.parseFilterResponse(""))
        XCTAssertNil(BailianService.parseFilterResponse("   "))
    }

    func testParseFilterResponseReturnsNilOnUnknown() {
        XCTAssertNil(BailianService.parseFilterResponse("可能是"),
                     "首字符非 是/否 应返回 nil 触发 retry")
        XCTAssertNil(BailianService.parseFilterResponse("Yes"))
        XCTAssertNil(BailianService.parseFilterResponse("1"))
    }

    // MARK: - per-cat prompt 文案差异化

    func testSummaryPromptDiffersByCategory() {
        let title = "X"
        let aiPrompt = BailianService.makeSummaryPrompt(title: title, content: "c", category: .ai)
        let earningsPrompt = BailianService.makeSummaryPrompt(title: title, content: "c", category: .earnings)
        let newsPrompt = BailianService.makeSummaryPrompt(title: title, content: "c", category: .news)

        XCTAssertTrue(aiPrompt.contains("AI / 科技"), "AI cat 应含 AI / 科技 关键词")
        XCTAssertTrue(earningsPrompt.contains("财经"), "财报 cat 应含 财经 关键词")
        XCTAssertTrue(newsPrompt.contains("时政事件") || newsPrompt.contains("新闻"),
                      "新闻 cat 应含新闻关键词")

        // 三 cat prompt 互不相同（防回退）
        XCTAssertNotEqual(aiPrompt, earningsPrompt)
        XCTAssertNotEqual(aiPrompt, newsPrompt)
        XCTAssertNotEqual(earningsPrompt, newsPrompt)
    }

    func testRecommendPromptMentionsCorrectAudience() {
        let items: [ArticleSnapshot.Item] = (0..<5).map {
            .init(id: UUID(), title: "T\($0)", summary: "s\($0)")
        }
        let aiPrompt = BailianService.makeRecommendPrompt(items: items, category: .ai)
        let earningsPrompt = BailianService.makeRecommendPrompt(items: items, category: .earnings)

        XCTAssertTrue(aiPrompt.contains("AI 从业者"))
        XCTAssertTrue(earningsPrompt.contains("投资者"))
    }

    func testDigestPromptMentionsCorrectFocus() {
        let items: [ArticleSnapshot.Item] = (0..<3).map {
            .init(id: UUID(), title: "T\($0)", summary: "s\($0)")
        }
        let aiPrompt = BailianService.makeDigestPrompt(items: items, category: .ai)
        let earningsPrompt = BailianService.makeDigestPrompt(items: items, category: .earnings)
        let newsPrompt = BailianService.makeDigestPrompt(items: items, category: .news)

        XCTAssertTrue(aiPrompt.contains("AI 进展"))
        XCTAssertTrue(earningsPrompt.contains("财报") || earningsPrompt.contains("业绩"))
        XCTAssertTrue(newsPrompt.contains("国际国内") || newsPrompt.contains("动态"))
    }

    func testAllPromptsHaveMarkdownConstraint() {
        // 沿用踩坑 #26：所有 prompt 都应含纯文本约束
        let summaryAI = BailianService.makeSummaryPrompt(title: "T", content: "c", category: .ai)
        let summaryE  = BailianService.makeSummaryPrompt(title: "T", content: "c", category: .earnings)
        let digestAI  = BailianService.makeDigestPrompt(items: [.init(id: UUID(), title: "T", summary: "s")], category: .ai)
        let digestE   = BailianService.makeDigestPrompt(items: [.init(id: UUID(), title: "T", summary: "s")], category: .earnings)

        for prompt in [summaryAI, summaryE, digestAI, digestE] {
            XCTAssertTrue(prompt.contains("纯文本"),
                          "所有摘要/日报 prompt 应含'纯文本'约束")
            XCTAssertTrue(prompt.contains("markdown"),
                          "应含 markdown 否定指令")
        }
    }
}
