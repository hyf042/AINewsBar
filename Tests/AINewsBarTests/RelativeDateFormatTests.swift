import XCTest
@testable import AINewsBar

final class RelativeDateFormatTests: XCTestCase {

    // 固定 now = 2026-05-22 14:00:00 本地时区，便于精确断言"昨天/今天/N 天前"
    private let now: Date = {
        var comp = DateComponents()
        comp.year = 2026; comp.month = 5; comp.day = 22
        comp.hour = 14; comp.minute = 0; comp.second = 0
        return Calendar.current.date(from: comp)!
    }()

    private let calendar = Calendar.current

    func testJustNowWithinOneMinute() {
        let d = now.addingTimeInterval(-30)
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "刚刚")
    }

    func testMinutesAgo() {
        let d = now.addingTimeInterval(-15 * 60)
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "15 分钟前")
    }

    func testHoursAgoSameDay() {
        let d = now.addingTimeInterval(-3 * 3600)
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "3 小时前")
    }

    // 关键场景：跨日边界 —— 哪怕只差 1 分钟也显示"昨天"
    func testYesterdayJustAcrossMidnight() {
        let midnight = calendar.startOfDay(for: now)
        let d = midnight.addingTimeInterval(-60) // 昨日 23:59
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "昨天")
    }

    func testYesterdayMorning() {
        let d = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "昨天")
    }

    func testTwoDaysAgo() {
        let d = calendar.date(byAdding: .day, value: -2, to: now)!
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "2 天前")
    }

    func testSixDaysAgo() {
        let d = calendar.date(byAdding: .day, value: -6, to: now)!
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "6 天前")
    }

    func testOlderShowsMonthDay() {
        let d = calendar.date(byAdding: .day, value: -10, to: now)!
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "5/12")
    }

    // 防御：未来时间（源服务器时钟错误）也显示"刚刚"，不崩
    func testFutureDateShowsJustNow() {
        let d = now.addingTimeInterval(120)
        XCTAssertEqual(formatArticleRelative(d, now: now, calendar: calendar), "刚刚")
    }
}
