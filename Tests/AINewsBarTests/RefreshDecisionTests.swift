import XCTest
@testable import AINewsBar

final class RefreshDecisionTests: XCTestCase {

    // MARK: - completionRate

    func testCompletionRateEmpty() {
        XCTAssertEqual(RefreshDecision.completionRate(completed: 0, total: 0), 1.0,
                       "空集合视为完成")
    }

    func testCompletionRateAllSuccess() {
        XCTAssertEqual(RefreshDecision.completionRate(completed: 5, total: 5), 1.0)
    }

    func testCompletionRateAllFail() {
        XCTAssertEqual(RefreshDecision.completionRate(completed: 0, total: 5), 0.0)
    }

    func testCompletionRatePartial() {
        XCTAssertEqual(RefreshDecision.completionRate(completed: 3, total: 4), 0.75)
    }

    // MARK: - shouldRegenerateRecommend

    func testRecommendTriggerOnNewArticles() {
        XCTAssertTrue(RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: true, isEmpty: false, currentCount: 10, lastCount: 10))
    }

    func testRecommendTriggerOnEmpty() {
        XCTAssertTrue(RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: false, isEmpty: true, currentCount: 10, lastCount: 10))
    }

    func testRecommendTriggerOnDelta() {
        XCTAssertTrue(RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: false, isEmpty: false, currentCount: 13, lastCount: 10),
            "增量 3 应触发")
    }

    func testRecommendSkipBelowDelta() {
        XCTAssertFalse(RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: false, isEmpty: false, currentCount: 12, lastCount: 10),
            "增量 2 不应触发")
    }

    func testRecommendCustomThreshold() {
        XCTAssertTrue(RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: false, isEmpty: false, currentCount: 15, lastCount: 10,
            deltaThreshold: 5))
        XCTAssertFalse(RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: false, isEmpty: false, currentCount: 14, lastCount: 10,
            deltaThreshold: 5))
    }

    // MARK: - shouldRegenerateDigest

    func testDigestTriggerWhenAbsent() {
        XCTAssertTrue(RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: false, isPresent: false, lastDate: nil,
            currentCount: 5, lastCount: 0))
    }

    func testDigestTriggerOnDelta() {
        XCTAssertTrue(RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: false, isPresent: true,
            lastDate: Date(), currentCount: 13, lastCount: 10),
            "增量 3 应触发")
    }

    func testDigestSkipWhenPresentAndNoNew() {
        XCTAssertFalse(RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: false, isPresent: true,
            lastDate: Date(), currentCount: 10, lastCount: 10))
    }

    func testDigestTriggerOnNewArticlesAfterInterval() {
        let now = Date()
        let fourHoursAgo = now.addingTimeInterval(-4 * 3600)
        XCTAssertTrue(RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: true, isPresent: true,
            lastDate: fourHoursAgo, currentCount: 10, lastCount: 10, now: now))
    }

    func testDigestSkipNewArticlesWithinInterval() {
        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-1 * 3600)
        XCTAssertFalse(RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: true, isPresent: true,
            lastDate: oneHourAgo, currentCount: 10, lastCount: 10, now: now),
            "1小时内不应重生成")
    }

    func testDigestTriggerOnCrossDayWithNewArticles() {
        let cal = Calendar.current
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: true, isPresent: true,
            lastDate: yesterday, currentCount: 10, lastCount: 10, now: now))
    }

    // MARK: - withinRegenerationWindow

    func testWindowNilLastDateTrue() {
        XCTAssertTrue(RefreshDecision.withinRegenerationWindow(
            lastDate: nil, now: Date(), interval: 3600))
    }

    func testWindowSameDayWithinInterval() {
        let now = Date()
        let almostNow = now.addingTimeInterval(-60)
        XCTAssertFalse(RefreshDecision.withinRegenerationWindow(
            lastDate: almostNow, now: now, interval: 3600))
    }

    func testWindowSameDayBeyondInterval() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        XCTAssertTrue(RefreshDecision.withinRegenerationWindow(
            lastDate: twoHoursAgo, now: now, interval: 3600))
    }

    func testWindowDifferentDay() {
        let cal = Calendar.current
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(RefreshDecision.withinRegenerationWindow(
            lastDate: yesterday, now: now, interval: 3600 * 24 * 30),
            "跨日时无论 interval 多大都应触发")
    }
}
