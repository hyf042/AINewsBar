import XCTest
@testable import AINewsBar

/// v2-multi-category: 验证 3 cat 配置完整性 + filter prompt 启用范围。
final class CategoryConfigTests: XCTestCase {

    func testAllThreeCategoriesHaveConfig() {
        let all = CategoryConfig.all
        XCTAssertEqual(all.count, 3, "应有 3 cat 配置")
        XCTAssertNotNil(all[.ai])
        XCTAssertNotNil(all[.earnings])
        XCTAssertNotNil(all[.news])
    }

    func testFilterPromptOnlyEnabledForEarnings() {
        XCTAssertNil(CategoryConfig.for(.ai).filterPrompt,
                     "AI cat 不应启用 filter")
        XCTAssertNotNil(CategoryConfig.for(.earnings).filterPrompt,
                        "财报 cat 应启用 filter")
        XCTAssertNil(CategoryConfig.for(.news).filterPrompt,
                     "新闻 cat first release 不启用 filter (待 30 天后视实际噪声决定)")
    }

    func testEarningsFilterPromptContainsKeywords() {
        let prompt = CategoryConfig.for(.earnings).filterPrompt ?? ""
        // 验证关键词存在（不验证完整文案，避免脆弱测试）
        XCTAssertTrue(prompt.contains("财报"), "应含 财报")
        XCTAssertTrue(prompt.contains("通过"), "应含通过条件说明")
        XCTAssertTrue(prompt.contains("拒绝"), "应含拒绝条件说明")
        XCTAssertTrue(prompt.contains("是") && prompt.contains("否"),
                      "应明确 是/否 输出格式")
    }

    func testRecommendCountIsFiveForAllCategories() {
        XCTAssertEqual(CategoryConfig.for(.ai).recommendCount, 5)
        XCTAssertEqual(CategoryConfig.for(.earnings).recommendCount, 5)
        XCTAssertEqual(CategoryConfig.for(.news).recommendCount, 5)
    }

    func testCategoryFieldMatchesKey() {
        // 防御性：config 的 category 字段应与 dict key 一致
        for (key, config) in CategoryConfig.all {
            XCTAssertEqual(config.category, key,
                           "CategoryConfig.\(key) 的 category 字段应为 .\(key)")
        }
    }

    // MARK: - Category enum 安全 fallback

    func testCategoryFromRawValueSafeFallback() {
        XCTAssertEqual(AINewsBar.Category.from(rawValue: "ai"), .ai)
        XCTAssertEqual(AINewsBar.Category.from(rawValue: "earnings"), .earnings)
        XCTAssertEqual(AINewsBar.Category.from(rawValue: "news"), .news)

        // 无效值 → fallback .ai
        XCTAssertEqual(AINewsBar.Category.from(rawValue: nil), .ai)
        XCTAssertEqual(AINewsBar.Category.from(rawValue: ""), .ai)
        XCTAssertEqual(AINewsBar.Category.from(rawValue: "unknown"), .ai)
        XCTAssertEqual(AINewsBar.Category.from(rawValue: "AI"), .ai, "大小写敏感的 enum，大写值应 fallback")
    }

    func testCategoryDisplayName() {
        XCTAssertEqual(AINewsBar.Category.ai.displayName, "AI")
        XCTAssertEqual(AINewsBar.Category.earnings.displayName, "财报")
        XCTAssertEqual(AINewsBar.Category.news.displayName, "新闻")
    }

    func testAllCasesOrder() {
        // UI segmented control 依赖 allCases 顺序
        XCTAssertEqual(AINewsBar.Category.allCases, [.ai, .earnings, .news])
    }
}
