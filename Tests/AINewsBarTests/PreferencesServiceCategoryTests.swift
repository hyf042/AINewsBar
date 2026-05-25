import XCTest
@testable import AINewsBar

/// v2-multi-category: 验证 per-cat key 隔离 + UI 状态记忆 + 安全 fallback。
final class PreferencesServiceCategoryTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var prefs: PreferencesService!

    override func setUp() {
        super.setUp()
        // 每个测试隔离的 UserDefaults suite，避免跨测试污染
        suiteName = "test.ainewsbar.cat.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        prefs = PreferencesService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        prefs = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - per-cat key 隔离

    func testSaveDigestPerCategoryDoesNotAffectOthers() {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)

        prefs.saveDigest(content: "AI 摘要", date: date1, for: .ai)
        prefs.saveDigest(content: "财报摘要", date: date2, for: .earnings)

        let aiResult = prefs.loadDigest(for: .ai)
        XCTAssertEqual(aiResult?.content, "AI 摘要")
        XCTAssertEqual(aiResult?.date, date1)

        let earningsResult = prefs.loadDigest(for: .earnings)
        XCTAssertEqual(earningsResult?.content, "财报摘要")
        XCTAssertEqual(earningsResult?.date, date2)

        // 新闻 cat 未 set → nil
        XCTAssertNil(prefs.loadDigest(for: .news))
    }

    func testClearDigestPerCategoryDoesNotAffectOthers() {
        prefs.saveDigest(content: "AI", date: Date(), for: .ai)
        prefs.saveDigest(content: "财报", date: Date(), for: .earnings)
        prefs.saveDigestArticleCount(11, for: .ai)
        prefs.saveDigestArticleCount(8, for: .earnings)

        // 只清 AI cat
        prefs.clearDigest(for: .ai)

        XCTAssertNil(prefs.loadDigest(for: .ai))
        XCTAssertEqual(prefs.loadDigestArticleCount(for: .ai), 0)

        // 财报 cat 保持
        XCTAssertNotNil(prefs.loadDigest(for: .earnings))
        XCTAssertEqual(prefs.loadDigestArticleCount(for: .earnings), 8)
    }

    func testRecommendArticleCountPerCategoryIsolated() {
        prefs.saveRecommendArticleCount(11, for: .ai)
        prefs.saveRecommendArticleCount(8, for: .earnings)
        prefs.saveRecommendArticleCount(15, for: .news)

        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .ai), 11)
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .earnings), 8)
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .news), 15)

        prefs.clearRecommendState(for: .earnings)

        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .ai), 11, "清财报不应动 AI")
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .earnings), 0)
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .news), 15, "清财报不应动新闻")
    }

    // MARK: - UI 状态记忆 (selectedTab / settingsFeedsTab)

    func testSelectedTabDefaultsToAI() {
        XCTAssertEqual(prefs.loadSelectedTab(), .ai)
        XCTAssertEqual(prefs.loadSettingsFeedsTab(), .ai)
    }

    func testSelectedTabPersists() {
        prefs.saveSelectedTab(.earnings)
        XCTAssertEqual(prefs.loadSelectedTab(), .earnings)

        prefs.saveSettingsFeedsTab(.news)
        XCTAssertEqual(prefs.loadSettingsFeedsTab(), .news)

        // 新创建的 prefs 实例读到的也是持久化值（验证非内存态）
        let prefs2 = PreferencesService(defaults: defaults)
        XCTAssertEqual(prefs2.loadSelectedTab(), .earnings)
        XCTAssertEqual(prefs2.loadSettingsFeedsTab(), .news)
    }

    // 旧无 category 签名已删除：调用方必须显式传入 cat，避免后续新增分类时误写 .ai。
}
