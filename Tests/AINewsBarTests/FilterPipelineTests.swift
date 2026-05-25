import XCTest
@testable import AINewsBar

/// v2-multi-category: FilterPipeline 单元测试。
final class FilterPipelineTests: XCTestCase {

    private var ai: MockAI!
    private var pipeline: FilterPipeline!

    override func setUp() {
        super.setUp()
        ai = MockAI()
        pipeline = FilterPipeline(ai: ai, maxConcurrent: 5, promptTemplate: "判断 <title> / <description>")
    }

    override func tearDown() {
        ai = nil
        pipeline = nil
        super.tearDown()
    }

    // MARK: - 空 tasks / 边界

    func testEmptyTasksReturnsEmptyResult() async {
        let result = await pipeline.run(tasks: [], apiKey: "k", model: "m")
        XCTAssertEqual(result.total, 0)
        XCTAssertTrue(result.acceptedIds.isEmpty)
        XCTAssertTrue(result.rejectedIds.isEmpty)
        XCTAssertTrue(result.classificationFailedIds.isEmpty)
        XCTAssertTrue(result.transientFailedIds.isEmpty)
        XCTAssertEqual(result.cancelledCount, 0)
        XCTAssertEqual(ai.classifyCallCount, 0)
    }

    // MARK: - 全 accepted / 全 rejected / 混合

    func testAllAccepted() async {
        ai.classifyProvider = { _, _ in true }
        let tasks = makeTasks(count: 3)
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.acceptedIds.count, 3)
        XCTAssertEqual(result.rejectedIds.count, 0)
        XCTAssertEqual(ai.classifyCallCount, 3)
    }

    func testAllRejected() async {
        ai.classifyProvider = { _, _ in false }
        let tasks = makeTasks(count: 4)
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.acceptedIds.count, 0)
        XCTAssertEqual(result.rejectedIds.count, 4)
    }

    func testMixedAcceptedAndRejected() async {
        // 根据 title 路由：含 "OK" → accepted；其他 → rejected
        ai.classifyProvider = { title, _ in title.contains("OK") }
        let tasks = [
            FilterPipeline.Task(id: UUID(), title: "OK-1", description: "d", category: .earnings),
            FilterPipeline.Task(id: UUID(), title: "REJECT", description: "d", category: .earnings),
            FilterPipeline.Task(id: UUID(), title: "OK-2", description: "d", category: .earnings)
        ]
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.acceptedIds.count, 2)
        XCTAssertEqual(result.rejectedIds.count, 1)
        XCTAssertEqual(result.total, 3)
    }

    // MARK: - 失败处理（AI 抛错）

    /// 第七轮 P1：未知错误 → transientFailed（不计 filterFailCount）
    func testUnknownErrorMarkedAsTransient() async {
        struct E: Error {}
        ai.classifyError = E()
        let tasks = makeTasks(count: 3)
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.acceptedIds.count, 0)
        XCTAssertEqual(result.rejectedIds.count, 0)
        XCTAssertEqual(result.classificationFailedIds.count, 0,
                       "未知错误不能进 classificationFailed（否则财报会因网络抖动被永久 reject）")
        XCTAssertEqual(result.transientFailedIds.count, 3)
        XCTAssertEqual(result.total, 3)
    }

    /// 第七轮 P1：BailianError.malformedResponse → classificationFailed（计数）
    /// 这是"模型确实无法分类"，应累计 filterFailCount。
    func testMalformedResponseMarkedAsClassificationFailed() async {
        ai.classifyError = BailianError.malformedResponse(reason: "filter 响应无法解析：xyz")
        let tasks = makeTasks(count: 3)
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.classificationFailedIds.count, 3)
        XCTAssertEqual(result.transientFailedIds.count, 0)
        XCTAssertNil(result.firstTransientGlobalError)
    }

    /// 第七轮 P1：HTTP 401 → transient + firstTransientGlobalError=.invalidAPIKey
    /// 让 caller 设 globalAIError 提示用户；同时 article 保持 accepted=nil 下次重试。
    func testHTTP401MarkedAsTransientWithGlobalError() async {
        ai.classifyError = BailianError.httpStatus(code: 401, bodySnippet: "invalid api key")
        let tasks = makeTasks(count: 2)
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.classificationFailedIds.count, 0,
                       "HTTP 401 不能算 classificationFailed —— 不能因为 key 错把财报永久 reject")
        XCTAssertEqual(result.transientFailedIds.count, 2)
        XCTAssertEqual(result.firstTransientGlobalError, .invalidAPIKey)
    }

    /// 第七轮 P1：HTTP 429 quota → transient + .quotaExceeded
    func testHTTP429MarkedAsTransient() async {
        ai.classifyError = BailianError.httpStatus(code: 429, bodySnippet: "rate limit")
        let tasks = makeTasks(count: 2)
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.transientFailedIds.count, 2)
        XCTAssertEqual(result.firstTransientGlobalError, .quotaExceeded)
    }

    // MARK: - 取消（race-free：仅验证不卡死 + 结果完整性，不验证 cancel 命中率）

    func testCancellationDoesNotHang() async {
        ai.classifyProvider = { _, _ in true }
        let tasks = makeTasks(count: 10)

        let task = _Concurrency.Task { [pipeline] in
            await pipeline!.run(tasks: tasks, apiKey: "k", model: "m")
        }
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result.total, 10, "pipeline 应能完成不卡死")
        let processed = result.acceptedIds.count + result.rejectedIds.count
                      + result.classificationFailedIds.count + result.transientFailedIds.count
                      + result.cancelledCount
        // 取消时机不确定：早期取消可能让所有 task 都不被种入（processed=0），
        // 晚期取消可能让部分 task 已跑完。两种都是合法行为，只验证不超量
        XCTAssertLessThanOrEqual(processed, result.total,
                                  "outcome 数量不应超过 total")
    }

    // MARK: - Usage 透传

    func testUsageCollectedForAcceptedAndRejected() async {
        ai.classifyProvider = { title, _ in title.contains("OK") }
        ai.classifyUsage = UsageInfo(inputTokens: 100, outputTokens: 2)
        let tasks = [
            FilterPipeline.Task(id: UUID(), title: "OK", description: "d", category: .earnings),
            FilterPipeline.Task(id: UUID(), title: "NO", description: "d", category: .earnings)
        ]
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.usages.count, 2, "accepted + rejected 都应有 usage")
        XCTAssertTrue(result.usages.allSatisfy { $0.inputTokens == 100 && $0.outputTokens == 2 })
    }

    func testFailedTasksDoNotProduceUsage() async {
        struct E: Error {}
        ai.classifyError = E()
        let tasks = makeTasks(count: 2)
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.usages.count, 0, "failed 不记 usage（HTTP 失败无 token）")
    }

    // MARK: - 5 并发不丢调用（验证锁）

    func testConcurrentCallsAllCounted() async {
        ai.classifyProvider = { _, _ in true }
        let tasks = makeTasks(count: 20)  // 20 任务 / 5 并发
        let result = await pipeline.run(tasks: tasks, apiKey: "k", model: "m")
        XCTAssertEqual(result.acceptedIds.count, 20)
        XCTAssertEqual(ai.classifyCallCount, 20, "5 并发下计数应精确（NSLock 保护）")
    }

    // MARK: - Helpers

    private func makeTasks(count: Int) -> [FilterPipeline.Task] {
        (0..<count).map { i in
            FilterPipeline.Task(
                id: UUID(),
                title: "Title-\(i)",
                description: "Desc-\(i)",
                category: .earnings
            )
        }
    }
}
