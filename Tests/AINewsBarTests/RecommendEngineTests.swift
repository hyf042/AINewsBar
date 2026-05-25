import XCTest
@testable import AINewsBar

final class RecommendEngineTests: XCTestCase {

    private var ai: MockAI!
    private var engine: RecommendEngine!

    override func setUp() {
        super.setUp()
        ai = MockAI()
        engine = RecommendEngine(ai: ai)
    }

    override func tearDown() {
        engine = nil
        ai = nil
        super.tearDown()
    }

    private func snap(count: Int, summarized: Int? = nil) -> ArticleSnapshot {
        let n = summarized ?? count
        let items = (0..<count).map { i -> ArticleSnapshot.Item in
            ArticleSnapshot.Item(id: UUID(), title: "T\(i)", summary: i < n ? "s\(i)" : nil)
        }
        return ArticleSnapshot(all: items)
    }

    // 决策已移至 RefreshService（由 RefreshDecisionTests 覆盖）；
    // Engine 在此只测：执行 + "<5 → nil" 数据完整性保护 + AI 错误透传

    func testRunsWhenEnoughArticles() async throws {
        let outcome = try await engine.run(snapshot: snap(count: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNotNil(outcome)
        XCTAssertEqual(ai.recommendCallCount, 1)
    }

    func testReturnsNilBelow5Articles() async throws {
        // 推荐展示数从 3 升 5，候选阈值同步提升
        let outcome = try await engine.run(snapshot: snap(count: 4),
                                            apiKey: "k", model: "m")
        XCTAssertNil(outcome, "<5 篇文章不应调 AI")
        XCTAssertEqual(ai.recommendCallCount, 0)
    }

    func testPropagatesAIError() async {
        ai.recommendError = URLError(.timedOut)
        do {
            _ = try await engine.run(snapshot: snap(count: 5),
                                      apiKey: "k", model: "m")
            XCTFail("应抛出错误")
        } catch {
            // OK
        }
    }

    func testThrowsWhenAIReturnsTooFewValidRecommendations() async {
        ai.recommendProvider = { items in Array(items.prefix(1).map(\.id)) }

        do {
            _ = try await engine.run(snapshot: snap(count: 5),
                                      apiKey: "k", model: "m")
            XCTFail("有效推荐少于 3 个时应视为 malformed response")
        } catch BailianError.malformedResponse {
            // OK
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testOutcomeCarriesSummarizedCount() async throws {
        let s = snap(count: 6, summarized: 4)
        let outcome = try await engine.run(snapshot: s,
                                            apiKey: "k", model: "m")
        XCTAssertEqual(outcome?.articleCount, 4, "articleCount 应为有摘要的数量")
    }
}
