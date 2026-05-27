import XCTest
@testable import AINewsBar

final class PreferencesServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var prefs: PreferencesService!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.ainewsbar.\(UUID().uuidString)"
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

    // MARK: - API Key

    func testGetAPIKeyDefaultNil() {
        XCTAssertNil(prefs.getAPIKey())
    }

    func testSaveAndGetAPIKey() {
        prefs.saveAPIKey("sk-test-123")
        XCTAssertEqual(prefs.getAPIKey(), "sk-test-123")
    }

    func testSaveEmptyAPIKeyClears() {
        prefs.saveAPIKey("sk-x")
        prefs.saveAPIKey("")
        XCTAssertNil(prefs.getAPIKey())
    }

    func testDeleteAPIKey() {
        prefs.saveAPIKey("sk-x")
        prefs.deleteAPIKey()
        XCTAssertNil(prefs.getAPIKey())
    }

    // MARK: - 第十三轮 P2：边界 trim（治 UI 层未拦截的脏值 + 历史 UserDefaults 残留）

    /// 用户从网页复制 key 带尾部空白/换行 → 写入时 trim
    func testSaveAPIKeyTrimsWhitespace() {
        prefs.saveAPIKey("  sk-test-123\n")
        XCTAssertEqual(prefs.getAPIKey(), "sk-test-123")
    }

    /// 历史 UserDefaults 已存了脏值（UI 升级前写入）→ get 也 trim 兜底
    /// 直接走底层 defaults.set 模拟旧版本写入
    func testGetAPIKeyTrimsHistoricalDirtyValue() {
        defaults.set("  sk-old-dirty\n\t", forKey: "com.ainewsbar.claude-api-key")
        XCTAssertEqual(prefs.getAPIKey(), "sk-old-dirty")
    }

    /// 全空白 key 写入应等价于清空
    func testSaveWhitespaceOnlyAPIKeyClears() {
        prefs.saveAPIKey("sk-x")
        prefs.saveAPIKey("   \n\t  ")
        XCTAssertNil(prefs.getAPIKey())
    }

    /// 全空白历史值读取等价 nil
    func testGetWhitespaceOnlyHistoricalAPIKeyReturnsNil() {
        defaults.set("   \n  ", forKey: "com.ainewsbar.claude-api-key")
        XCTAssertNil(prefs.getAPIKey())
    }

    func testSaveModelTrimsWhitespace() {
        prefs.saveModel("  qwen-custom\n")
        XCTAssertEqual(prefs.getModel(), "qwen-custom")
    }

    func testGetModelTrimsHistoricalDirtyValue() {
        defaults.set("  qwen-dirty\n", forKey: "com.ainewsbar.model")
        XCTAssertEqual(prefs.getModel(), "qwen-dirty")
    }

    func testSaveWhitespaceOnlyModelFallsBackToDefault() {
        prefs.saveModel("custom")
        prefs.saveModel("   ")
        XCTAssertEqual(prefs.getModel(), PreferencesService.defaultModel)
    }

    // MARK: - Model

    func testGetModelDefault() {
        XCTAssertEqual(prefs.getModel(), PreferencesService.defaultModel)
    }

    func testSaveAndGetModel() {
        prefs.saveModel("qwen-custom")
        XCTAssertEqual(prefs.getModel(), "qwen-custom")
    }

    func testSaveEmptyModelFallsBackToDefault() {
        prefs.saveModel("qwen-custom")
        prefs.saveModel("")
        XCTAssertEqual(prefs.getModel(), PreferencesService.defaultModel)
    }

    // MARK: - Digest

    func testLoadDigestDefaultNil() {
        XCTAssertNil(prefs.loadDigest(for: .ai))
    }

    func testSaveAndLoadDigest() throws {
        let date = Date()
        prefs.saveDigest(content: "今日要闻", date: date, for: .ai)
        let loaded = try XCTUnwrap(prefs.loadDigest(for: .ai))
        XCTAssertEqual(loaded.content, "今日要闻")
        XCTAssertEqual(loaded.date.timeIntervalSince1970,
                       date.timeIntervalSince1970, accuracy: 0.001)
    }

    // P3: clearDigest 仅清日报相关 key，保留推荐计数
    func testClearDigestRemovesOnlyDigestKeys() {
        prefs.saveDigest(content: "x", date: Date(), for: .ai)
        prefs.saveDigestArticleCount(5, for: .ai)
        prefs.saveRecommendArticleCount(7, for: .ai)
        prefs.clearDigest(for: .ai)

        XCTAssertNil(prefs.loadDigest(for: .ai))
        XCTAssertEqual(prefs.loadDigestArticleCount(for: .ai), 0)
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .ai), 7, "clearDigest 不应触及推荐计数")
    }

    func testClearRecommendStateRemovesOnlyRecommendKeys() {
        prefs.saveDigest(content: "x", date: Date(), for: .ai)
        prefs.saveDigestArticleCount(5, for: .ai)
        prefs.saveRecommendArticleCount(7, for: .ai)
        prefs.clearRecommendState(for: .ai)

        XCTAssertNotNil(prefs.loadDigest(for: .ai), "clearRecommendState 不应触及日报内容")
        XCTAssertEqual(prefs.loadDigestArticleCount(for: .ai), 5)
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .ai), 0)
    }

    // MARK: - Article counts

    func testArticleCountDefaultZero() {
        XCTAssertEqual(prefs.loadDigestArticleCount(for: .ai), 0)
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .ai), 0)
    }

    func testDigestArticleCount() {
        prefs.saveDigestArticleCount(42, for: .ai)
        XCTAssertEqual(prefs.loadDigestArticleCount(for: .ai), 42)
    }

    func testRecommendArticleCount() {
        prefs.saveRecommendArticleCount(7, for: .ai)
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .ai), 7)
    }

    func testCountsAreIndependent() {
        prefs.saveDigestArticleCount(10, for: .ai)
        prefs.saveRecommendArticleCount(20, for: .ai)
        XCTAssertEqual(prefs.loadDigestArticleCount(for: .ai), 10)
        XCTAssertEqual(prefs.loadRecommendArticleCount(for: .ai), 20)
    }
}
