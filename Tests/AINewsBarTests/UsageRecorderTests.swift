import XCTest
import SwiftData
@testable import AINewsBar

@MainActor
final class UsageRecorderTests: XCTestCase {
    private var container: ModelContainer!
    private var ctx: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        (container, ctx) = try TestContainer.make()
    }

    override func tearDown() async throws {
        ctx = nil
        container = nil
        try await super.tearDown()
    }

    func testRecordPersistsEntry() throws {
        let recorder = UsageRecorder(context: ctx)
        recorder.record(scene: .summary, category: .ai, model: "qwen-plus",
                        input: 120, output: 30, success: true)

        let all = try ctx.fetch(FetchDescriptor<UsageRecord>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.scene, "summary")
        XCTAssertEqual(all.first?.model, "qwen-plus")
        XCTAssertEqual(all.first?.inputTokens, 120)
        XCTAssertEqual(all.first?.outputTokens, 30)
        XCTAssertEqual(all.first?.success, true)
    }

    func testNegativeInputsClampedToZero() throws {
        let recorder = UsageRecorder(context: ctx)
        recorder.record(scene: .summary, category: .ai, model: "m",
                        input: -10, output: -5, success: false)
        let all = try ctx.fetch(FetchDescriptor<UsageRecord>())
        XCTAssertEqual(all.first?.inputTokens, 0)
        XCTAssertEqual(all.first?.outputTokens, 0)
    }

    // P3-B: helper record(info:success:) 在 success=false 时强制归零
    // 即便 caller 传了非 zero UsageInfo（如保存失败但 DashScope 已返回 usage）
    func testRecordHelperZerosTokensOnFailure() throws {
        let recorder = UsageRecorder(context: ctx)
        let realUsage = UsageInfo(inputTokens: 500, outputTokens: 100)
        recorder.record(scene: .summary, category: .ai, model: "m",
                        info: realUsage, success: false)

        let all = try ctx.fetch(FetchDescriptor<UsageRecord>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.inputTokens, 0,
                       "P3-B 契约：success=false 时 helper 必须强制归零，不能用 caller 传的真实 token")
        XCTAssertEqual(all.first?.outputTokens, 0)
        XCTAssertEqual(all.first?.success, false)
    }

    func testRecordHelperPreservesTokensOnSuccess() throws {
        let recorder = UsageRecorder(context: ctx)
        let usage = UsageInfo(inputTokens: 500, outputTokens: 100)
        recorder.record(scene: .summary, category: .ai, model: "m",
                        info: usage, success: true)

        let all = try ctx.fetch(FetchDescriptor<UsageRecord>())
        XCTAssertEqual(all.first?.inputTokens, 500)
        XCTAssertEqual(all.first?.outputTokens, 100)
        XCTAssertEqual(all.first?.success, true)
    }

    func testCleanupRemovesOlderThanWindow() throws {
        let recorder = UsageRecorder(context: ctx)

        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -45, to: now)!
        let recentDate = Calendar.current.date(byAdding: .day, value: -3, to: now)!

        ctx.insert(UsageRecord(timestamp: oldDate, scene: .summary, model: "m",
                                inputTokens: 1, outputTokens: 1, success: true))
        ctx.insert(UsageRecord(timestamp: recentDate, scene: .summary, model: "m",
                                inputTokens: 2, outputTokens: 2, success: true))
        try ctx.save()

        recorder.cleanupOlderThan(days: 30)

        let remaining = try ctx.fetch(FetchDescriptor<UsageRecord>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.timestamp, recentDate)
    }

    func testCleanupZeroDaysIsNoOp() throws {
        let recorder = UsageRecorder(context: ctx)
        ctx.insert(UsageRecord(scene: .summary, model: "m",
                                inputTokens: 1, outputTokens: 1, success: true))
        try ctx.save()
        recorder.cleanupOlderThan(days: 0)
        let all = try ctx.fetch(FetchDescriptor<UsageRecord>())
        XCTAssertEqual(all.count, 1)
    }

    func testTodayTotalTokensIncludesOnlyTodaySuccess() throws {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now).addingTimeInterval(3600)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        ctx.insert(UsageRecord(timestamp: today, scene: .summary, model: "m",
                                inputTokens: 50, outputTokens: 50, success: true))
        ctx.insert(UsageRecord(timestamp: today, scene: .digest, model: "m",
                                inputTokens: 100, outputTokens: 0, success: false))
        ctx.insert(UsageRecord(timestamp: yesterday, scene: .summary, model: "m",
                                inputTokens: 999, outputTokens: 999, success: true))
        try ctx.save()

        let total = UsageRecorder.todayTotalTokens(in: ctx, now: now)
        XCTAssertEqual(total, 100)
    }
}
