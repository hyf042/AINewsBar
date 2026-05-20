import XCTest
@testable import AINewsBar

final class SummaryPipelineTests: XCTestCase {

    private var ai: MockAI!
    private var pipeline: SummaryPipeline!

    override func setUp() {
        super.setUp()
        ai = MockAI()
        pipeline = SummaryPipeline(ai: ai, maxConcurrent: 3)
    }

    override func tearDown() {
        pipeline = nil
        ai = nil
        super.tearDown()
    }

    private func makeTask(_ title: String) -> SummaryPipeline.Task {
        SummaryPipeline.Task(id: UUID(), title: title, content: "c-\(title)")
    }

    func testEmptyTasksReturnsZero() async {
        let r = await pipeline.run(tasks: [], apiKey: "k", model: "m")
        XCTAssertEqual(r.total, 0)
        XCTAssertTrue(r.completed.isEmpty)
        XCTAssertEqual(r.completionRate, 1.0, "空集合视为完整完成")
    }

    func testAllSucceed() async {
        ai.summaryProvider = { title, _ in "summary-\(title)" }
        let tasks = (1...5).map { makeTask("T\($0)") }

        let r = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(r.completed.count, 5)
        XCTAssertEqual(r.total, 5)
        XCTAssertEqual(r.completionRate, 1.0)
        XCTAssertEqual(ai.summaryCallCount, 5)
    }

    func testAllFail() async {
        ai.summaryError = URLError(.timedOut)
        let tasks = (1...3).map { makeTask("T\($0)") }

        let r = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(r.completed.count, 0)
        XCTAssertEqual(r.total, 3)
        XCTAssertEqual(r.completionRate, 0.0)
    }

    func testRespectsConcurrencyCap() async {
        // 7 个任务 + maxConcurrent=3：所有任务应完成，且不超过 7 次调用
        ai.summaryProvider = { title, _ in "s-\(title)" }
        let tasks = (1...7).map { makeTask("T\($0)") }

        let r = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(r.completed.count, 7)
        XCTAssertEqual(ai.summaryCallCount, 7, "每个任务恰好调用一次")
    }
}
