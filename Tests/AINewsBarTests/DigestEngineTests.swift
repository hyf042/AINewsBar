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

    // MARK: - .auto trigger

    func testAutoSkipsWhenCoverageInsufficient() async throws {
        let trigger: DigestEngine.Trigger = .auto(
            hasNewArticles: true, isPresent: false, lastDate: nil,
            currentCount: 5, lastCount: 0,
            hasEnoughCoverage: false,
            regenerateInterval: 3600, deltaThreshold: 3
        )
        let outcome = try await engine.run(trigger: trigger, snapshot: snap(summarized: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNil(outcome, "覆盖率不足应跳过")
        XCTAssertEqual(ai.digestCallCount, 0)
    }

    func testAutoRunsOnFirstTime() async throws {
        let trigger: DigestEngine.Trigger = .auto(
            hasNewArticles: false, isPresent: false, lastDate: nil,
            currentCount: 5, lastCount: 0,
            hasEnoughCoverage: true,
            regenerateInterval: 3600, deltaThreshold: 3
        )
        let outcome = try await engine.run(trigger: trigger, snapshot: snap(summarized: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNotNil(outcome, "首次（isPresent=false）应生成")
    }

    func testAutoSkipsWhenAlreadyPresentWithoutTrigger() async throws {
        let trigger: DigestEngine.Trigger = .auto(
            hasNewArticles: false, isPresent: true, lastDate: Date(),
            currentCount: 5, lastCount: 5,
            hasEnoughCoverage: true,
            regenerateInterval: 3600, deltaThreshold: 3
        )
        let outcome = try await engine.run(trigger: trigger, snapshot: snap(summarized: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNil(outcome, "已存在 + 无新文章 + 无增量 → 不再生成")
    }

    // MARK: - .forced trigger

    func testForcedSkipsAllGates() async throws {
        // 即使 hasEnoughCoverage 不会进 .forced，forced 直接执行
        let outcome = try await engine.run(trigger: .forced, snapshot: snap(summarized: 5),
                                            apiKey: "k", model: "m")
        XCTAssertNotNil(outcome)
        XCTAssertEqual(ai.digestCallCount, 1)
    }

    func testForcedReturnsNilBelow3Summarized() async throws {
        let outcome = try await engine.run(trigger: .forced, snapshot: snap(summarized: 2),
                                            apiKey: "k", model: "m")
        XCTAssertNil(outcome, "<3 篇有摘要的不应生成日报")
    }

    func testForcedPropagatesAIError() async {
        ai.digestError = URLError(.cannotConnectToHost)
        do {
            _ = try await engine.run(trigger: .forced, snapshot: snap(summarized: 5),
                                      apiKey: "k", model: "m")
            XCTFail("应抛错")
        } catch {
            // OK
        }
    }

    func testOutcomeContent() async throws {
        ai.digestProvider = { _ in "今日要闻..." }
        let outcome = try await engine.run(trigger: .forced, snapshot: snap(summarized: 5),
                                            apiKey: "k", model: "m")
        XCTAssertEqual(outcome?.content, "今日要闻...")
        XCTAssertEqual(outcome?.articleCount, 5)
    }
}
