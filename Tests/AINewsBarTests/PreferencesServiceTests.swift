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
