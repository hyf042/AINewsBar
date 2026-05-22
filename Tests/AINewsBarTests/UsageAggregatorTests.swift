import XCTest
import SwiftData
@testable import AINewsBar

@MainActor
final class UsageAggregatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeRecord(
        days offset: Int,
        scene: UsageScene,
        input: Int = 0,
        output: Int = 0,
        success: Bool = true,
        relativeTo now: Date
    ) -> UsageRecord {
        let day = calendar.startOfDay(for: now)
        let ts = calendar.date(byAdding: .day, value: -offset, to: day)!
            .addingTimeInterval(60) // 给当天一个固定偏移避免 startOfDay 边界混淆
        return UsageRecord(
            timestamp: ts,
            scene: scene,
            model: "m",
            inputTokens: input,
            outputTokens: output,
            success: success
        )
    }

    func testTodayStatsEmptyWhenNoRecords() {
        let stats = UsageAggregator.todayStats([])
        XCTAssertEqual(stats, .empty)
    }

    func testTodayStatsCountsCallsTokensAndFailures() {
        let now = Date()
        let records = [
            makeRecord(days: 0, scene: .summary, input: 10, output: 20, relativeTo: now),
            makeRecord(days: 0, scene: .recommend, input: 30, output: 5, relativeTo: now),
            makeRecord(days: 0, scene: .digest, success: false, relativeTo: now), // 失败
            makeRecord(days: 1, scene: .summary, input: 999, output: 999, relativeTo: now), // 昨日
        ]
        let stats = UsageAggregator.todayStats(records, now: now, calendar: calendar)
        XCTAssertEqual(stats.totalTokens, 10 + 20 + 30 + 5) // 失败不计、昨日不计
        XCTAssertEqual(stats.calls, 3)                       // 今日总条数（含失败）
        XCTAssertEqual(stats.failures, 1)
    }

    func testDailyByScenePositiveDays() {
        let now = Date()
        let records = [
            makeRecord(days: 0, scene: .summary, input: 100, output: 50, relativeTo: now),
            makeRecord(days: 0, scene: .summary, input: 10, output: 5, relativeTo: now),
            makeRecord(days: 1, scene: .recommend, input: 8, output: 12, relativeTo: now),
            makeRecord(days: 2, scene: .digest, input: 20, output: 30, relativeTo: now),
            makeRecord(days: 10, scene: .summary, input: 9999, output: 9999, relativeTo: now), // 范围外
        ]
        let points = UsageAggregator.dailyByScene(records, days: 7, now: now, calendar: calendar)

        // 今天 summary 应聚合为单个点 165
        let today = calendar.startOfDay(for: now)
        let todaySummary = points.first {
            $0.day == today && $0.scene == .summary
        }
        XCTAssertEqual(todaySummary?.tokens, 165)

        // 不应包含 10 天前的记录
        let oldest = calendar.date(byAdding: .day, value: -6, to: today)!
        XCTAssertFalse(points.contains { $0.day < oldest })

        // 失败不入聚合
        XCTAssertFalse(points.contains { $0.tokens == 0 })
    }

    func testDailyByScenSkipsFailedRecords() {
        let now = Date()
        let records = [
            makeRecord(days: 0, scene: .summary, input: 100, output: 0, success: false, relativeTo: now)
        ]
        let points = UsageAggregator.dailyByScene(records, days: 7, now: now, calendar: calendar)
        XCTAssertTrue(points.isEmpty)
    }

    func testDailyByScenZeroDaysReturnsEmpty() {
        let points = UsageAggregator.dailyByScene([], days: 0)
        XCTAssertTrue(points.isEmpty)
    }
}
