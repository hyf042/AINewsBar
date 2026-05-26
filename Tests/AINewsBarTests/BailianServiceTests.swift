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

    /// 第八轮 P3 行为变化：正则 `\d+` 不识别负号，"-1" 中的 "1" 会被提取出来。
    /// 这是可接受的 fallback（模型几乎不会返回负数；即使返回，提取数字部分仍合理）。
    func testParseTreatsNegativeAsPositive() {
        let result = BailianService.parseRecommendResponse("-1,3,4", totalCount: 10)
        XCTAssertEqual(result, [1, 3, 4],
                       "正则提取 `\\d+`：-1 中的 1 被识别（不识别负号，可接受 fallback）")
    }

    func testParsePicksAtMostFive() {
        // 推荐展示数 3 → 5：parser cap 同步抬升
        let result = BailianService.parseRecommendResponse("1,2,3,4,5,6,7", totalCount: 20)
        XCTAssertEqual(result, [1, 2, 3, 4, 5])
    }

    func testParseAfterDedupStillFive() {
        // C1 边界：去重前 7 个含 1 个重复，去重后 6 个，仍 cap 在 5
        let result = BailianService.parseRecommendResponse("1,2,1,3,4,5,6", totalCount: 20)
        XCTAssertEqual(result, [1, 2, 3, 4, 5])
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

    // 第八轮 P3 review：常见模型啰嗦输出格式

    /// "1. 2. 3." 这种带点号的列表格式 — 旧实现按 `,，、 \n\t` split 后整数解析失败
    func testParseDottedNumberList() {
        let result = BailianService.parseRecommendResponse("1. 2. 3. 4. 5.", totalCount: 20)
        XCTAssertEqual(result, [1, 2, 3, 4, 5])
    }

    /// 序号编号在括号内："1) 2) 3)" 或 "(1)(2)(3)"
    func testParseBracketedNumbers() {
        XCTAssertEqual(BailianService.parseRecommendResponse("1) 2) 3) 4) 5)", totalCount: 20),
                       [1, 2, 3, 4, 5])
        XCTAssertEqual(BailianService.parseRecommendResponse("[1][2][3][4][5]", totalCount: 20),
                       [1, 2, 3, 4, 5])
        XCTAssertEqual(BailianService.parseRecommendResponse("(1)(2)(3)(4)(5)", totalCount: 20),
                       [1, 2, 3, 4, 5])
    }

    /// 模型添加前缀文字："推荐：1,3,7" / "Picks: 1, 3, 7"
    func testParsePrefixedResponse() {
        XCTAssertEqual(BailianService.parseRecommendResponse("推荐：2,4,6,8,10", totalCount: 20),
                       [2, 4, 6, 8, 10])
        XCTAssertEqual(BailianService.parseRecommendResponse("Picks: 1, 3, 5", totalCount: 20),
                       [1, 3, 5])
    }

    /// 多位数序号仍能完整提取
    func testParseMultiDigitIndices() {
        let result = BailianService.parseRecommendResponse("12. 7. 23. 4. 18.", totalCount: 30)
        XCTAssertEqual(result, [12, 7, 23, 4, 18])
    }

    // MARK: - 第九轮 P3：末尾冒号优先（避免解释文字数字混入）

    /// 模型在冒号前的解释里含数字（如 "推荐5篇"）：旧实现会把这个 5 抢先吞掉，
    /// 导致 [5,1,2,3,4] 顺序错乱（甚至少一个 id）。新实现按"解释 : 结果"切片，
    /// 优先取最后冒号后段，结果应保持 [1,2,3,4,5]。
    func testParseSkipsDigitsInPrefixBeforeColon() {
        XCTAssertEqual(
            BailianService.parseRecommendResponse("推荐5篇：1,2,3,4,5", totalCount: 20),
            [1, 2, 3, 4, 5]
        )
        XCTAssertEqual(
            BailianService.parseRecommendResponse("Top 5 picks: 7, 3, 8, 1, 4", totalCount: 20),
            [7, 3, 8, 1, 4]
        )
    }

    /// 无冒号格式（全文正则 fallback）：保持旧 "1,2,3,4,5" / "1) 2)" 兼容。
    func testParseFallsBackToWholeStringWhenNoColon() {
        XCTAssertEqual(
            BailianService.parseRecommendResponse("1, 2, 3, 4, 5", totalCount: 20),
            [1, 2, 3, 4, 5]
        )
    }

    /// 冒号在结果后又跟说明（无意义数字）：取最后一个冒号后段为空数字时应 fallback 全文。
    /// 例 "1,2,3:" 末尾冒号后是空，全文 fallback 回到 [1,2,3]。
    func testParseFallsBackWhenTailAfterLastColonHasNoDigits() {
        XCTAssertEqual(
            BailianService.parseRecommendResponse("1, 2, 3:", totalCount: 20),
            [1, 2, 3]
        )
        XCTAssertEqual(
            BailianService.parseRecommendResponse("1, 2, 3：结束", totalCount: 20),
            [1, 2, 3]
        )
    }

    // MARK: - Prompt 构造

    func testSummaryPromptIncludesTitle() {
        let prompt = BailianService.makeSummaryPrompt(title: "OpenAI 发布新模型", content: "正文内容...", category: .ai)
        XCTAssertTrue(prompt.contains("OpenAI 发布新模型"))
        XCTAssertTrue(prompt.contains("正文内容"))
        XCTAssertTrue(prompt.contains("中文"))
    }

    func testSummaryPromptHandlesNilContent() {
        let prompt = BailianService.makeSummaryPrompt(title: "T", content: nil, category: .ai)
        XCTAssertTrue(prompt.contains("无正文"))
    }

    func testSummaryPromptTruncatesLongContent() {
        let long = String(repeating: "a", count: 3000)
        let prompt = BailianService.makeSummaryPrompt(title: "T", content: long, category: .ai)
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
        let prompt = BailianService.makeRecommendPrompt(items: items, count: 5, category: .ai)
        XCTAssertTrue(prompt.contains("1. A"))
        XCTAssertTrue(prompt.contains("2. B"))
        XCTAssertTrue(prompt.contains("3. C"))
        XCTAssertTrue(prompt.contains("挑选 5 篇"))
        XCTAssertTrue(prompt.contains("按推荐度由高到低"), "prompt 应显式要求按推荐度排序")
    }

    func testRecommendPromptCapsAt50() {
        let items = (0..<100).map { i in
            ArticleSnapshot.Item(id: UUID(), title: "T\(i)", summary: "s\(i)")
        }
        let prompt = BailianService.makeRecommendPrompt(items: items, count: 5, category: .ai)
        XCTAssertTrue(prompt.contains("50. T49"))
        XCTAssertFalse(prompt.contains("51. T50"), "超过 50 的应被截断")
    }

    func testDigestPromptIncludesEntries() {
        let items: [ArticleSnapshot.Item] = [
            .init(id: UUID(), title: "A", summary: "sa"),
            .init(id: UUID(), title: "B", summary: "sb")
        ]
        let prompt = BailianService.makeDigestPrompt(items: items, category: .ai)
        XCTAssertTrue(prompt.contains("A｜sa"))
        XCTAssertTrue(prompt.contains("B｜sb"))
        XCTAssertTrue(prompt.contains("中文"))
    }

    func testDigestPromptCapsAt20() {
        let items = (0..<30).map { i in
            ArticleSnapshot.Item(id: UUID(), title: "T\(i)", summary: "s\(i)")
        }
        let prompt = BailianService.makeDigestPrompt(items: items, category: .ai)
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
        let prompt = BailianService.makeDigestPrompt(items: items, category: .ai)
        XCTAssertTrue(prompt.contains("A｜sa"))
        XCTAssertFalse(prompt.contains("- B"), "nil-summary 项应跳过")
        XCTAssertTrue(prompt.contains("C｜sc"))
    }
}
