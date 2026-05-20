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

    // MARK: - .auto trigger

    func testAutoSkipsWhenDecisionNo() async throws {
        let trigger: RecommendEngine.Trigger = .auto(
            hasNewArticles: false, isEmpty: false,
            currentCount: 5, lastCount: 5, deltaThreshold: 3
        )
        let outcome = try await engine.run(trigger: trigger, snapshot: snap(count: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNil(outcome, "无新文章 + 增量未达阈值 → 不应调 AI")
        XCTAssertEqual(ai.recommendCallCount, 0)
    }

    func testAutoRunsWhenHasNewArticles() async throws {
        let trigger: RecommendEngine.Trigger = .auto(
            hasNewArticles: true, isEmpty: false,
            currentCount: 5, lastCount: 5, deltaThreshold: 3
        )
        let outcome = try await engine.run(trigger: trigger, snapshot: snap(count: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNotNil(outcome)
        XCTAssertEqual(ai.recommendCallCount, 1)
    }

    func testAutoRunsWhenDeltaExceeded() async throws {
        let trigger: RecommendEngine.Trigger = .auto(
            hasNewArticles: false, isEmpty: false,
            currentCount: 10, lastCount: 5, deltaThreshold: 3
        )
        let outcome = try await engine.run(trigger: trigger, snapshot: snap(count: 10),
                                            apiKey: "k", model: "m")
        XCTAssertNotNil(outcome)
    }

    // MARK: - .forced trigger

    func testForcedSkipsDecisionGate() async throws {
        // 即使 hasNewArticles=false, delta=0，forced 应直接执行
        let outcome = try await engine.run(trigger: .forced, snapshot: snap(count: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNotNil(outcome)
        XCTAssertEqual(ai.recommendCallCount, 1)
    }

    func testForcedReturnsNilBelow3Articles() async throws {
        let outcome = try await engine.run(trigger: .forced, snapshot: snap(count: 2),
                                            apiKey: "k", model: "m")
        XCTAssertNil(outcome, "<3 篇文章不应调 AI")
        XCTAssertEqual(ai.recommendCallCount, 0)
    }

    func testForcedPropagatesAIError() async {
        ai.recommendError = URLError(.timedOut)
        do {
            _ = try await engine.run(trigger: .forced, snapshot: snap(count: 5),
                                      apiKey: "k", model: "m")
            XCTFail("应抛出错误")
        } catch {
            // OK
        }
    }

    func testOutcomeCarriesSummarizedCount() async throws {
        let s = snap(count: 5, summarized: 3)
        let outcome = try await engine.run(trigger: .forced, snapshot: s,
                                            apiKey: "k", model: "m")
        XCTAssertEqual(outcome?.articleCount, 3, "articleCount 应为有摘要的数量")
    }
}
