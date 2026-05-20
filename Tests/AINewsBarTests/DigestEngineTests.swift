import XCTest
@testable import AINewsBar

final class DigestEngineTests: XCTestCase {

    private var ai: MockAI!
    private var engine: DigestEngine!

    override func setUp() {
        super.setUp()
        ai = MockAI()
        engine = DigestEngine(ai: ai)
    }

    override func tearDown() {
        engine = nil
        ai = nil
        super.tearDown()
    }

    private func snap(summarized: Int) -> ArticleSnapshot {
        let items = (0..<summarized).map { i in
            ArticleSnapshot.Item(id: UUID(), title: "T\(i)", summary: "s\(i)")
        }
        return ArticleSnapshot(all: items)
    }

    // 决策已移至 RefreshService（由 RefreshDecisionTests 覆盖）；
    // Engine 在此只测：执行 + "<3 → nil" 数据完整性保护 + AI 错误透传

    func testRunsWhenEnoughSummarized() async throws {
        let outcome = try await engine.run(snapshot: snap(summarized: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNotNil(outcome)
        XCTAssertEqual(ai.digestCallCount, 1)
    }

    func testReturnsNilBelow3Summarized() async throws {
        let outcome = try await engine.run(snapshot: snap(summarized: 2),
                                            apiKey: "k", model: "m")
        XCTAssertNil(outcome, "<3 篇有摘要的不应生成日报")
        XCTAssertEqual(ai.digestCallCount, 0)
    }

    func testPropagatesAIError() async {
        ai.digestError = URLError(.cannotConnectToHost)
        do {
            _ = try await engine.run(snapshot: snap(summarized: 5),
                                      apiKey: "k", model: "m")
            XCTFail("应抛错")
        } catch {
            // OK
        }
    }

    func testOutcomeContent() async throws {
        ai.digestProvider = { _ in "今日要闻..." }
        let outcome = try await engine.run(snapshot: snap(summarized: 5),
                                            apiKey: "k", model: "m")
        XCTAssertEqual(outcome?.content, "今日要闻...")
        XCTAssertEqual(outcome?.articleCount, 5)
    }
}
