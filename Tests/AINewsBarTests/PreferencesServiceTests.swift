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
        XCTAssertNil(prefs.loadDigest())
    }

    func testSaveAndLoadDigest() throws {
        let date = Date()
        prefs.saveDigest(content: "今日要闻", date: date)
        let loaded = try XCTUnwrap(prefs.loadDigest())
        XCTAssertEqual(loaded.content, "今日要闻")
        XCTAssertEqual(loaded.date.timeIntervalSince1970,
                       date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testClearDigestRemovesAll() {
        prefs.saveDigest(content: "x", date: Date())
        prefs.saveDigestArticleCount(5)
        prefs.saveRecommendArticleCount(7)
        prefs.clearDigest()

        XCTAssertNil(prefs.loadDigest())
        XCTAssertEqual(prefs.loadDigestArticleCount(), 0)
        XCTAssertEqual(prefs.loadRecommendArticleCount(), 0)
    }

    // MARK: - Article counts

    func testArticleCountDefaultZero() {
        XCTAssertEqual(prefs.loadDigestArticleCount(), 0)
        XCTAssertEqual(prefs.loadRecommendArticleCount(), 0)
    }

    func testDigestArticleCount() {
        prefs.saveDigestArticleCount(42)
        XCTAssertEqual(prefs.loadDigestArticleCount(), 42)
    }

    func testRecommendArticleCount() {
        prefs.saveRecommendArticleCount(7)
        XCTAssertEqual(prefs.loadRecommendArticleCount(), 7)
    }

    func testCountsAreIndependent() {
        prefs.saveDigestArticleCount(10)
        prefs.saveRecommendArticleCount(20)
        XCTAssertEqual(prefs.loadDigestArticleCount(), 10)
        XCTAssertEqual(prefs.loadRecommendArticleCount(), 20)
    }
}
