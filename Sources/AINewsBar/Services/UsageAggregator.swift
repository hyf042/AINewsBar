import Foundation

/// UsageRecord 聚合纯函数集合。所有时钟通过参数注入，便于单测。
enum UsageAggregator {
    struct DailyPoint: Identifiable, Hashable {
        var id: String { "\(day.timeIntervalSince1970)-\(scene.rawValue)" }
        let day: Date
        let scene: UsageScene
        let tokens: Int
    }

    struct TodayStats: Equatable {
        let totalTokens: Int
        let calls: Int
        let failures: Int

        static let empty = TodayStats(totalTokens: 0, calls: 0, failures: 0)
    }

    /// 今日统计：成功调用的 token 总和、总调用次数（含失败）、失败次数。
    static func todayStats(
        _ records: [UsageRecord],
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> TodayStats {
        let start = calendar.startOfDay(for: now)
        let today = records.filter { $0.timestamp >= start }
        let totalTokens = today
            .filter(\.success)
            .reduce(0) { $0 + $1.totalTokens }
        let failures = today.filter { !$0.success }.count
        return TodayStats(totalTokens: totalTokens, calls: today.count, failures: failures)
    }

    /// 按 (day, scene) 聚合的 token 用量。
    /// 仅含成功调用；day 为当地时区的 startOfDay；含值为 0 的桶被过滤。
    static func dailyByScene(
        _ records: [UsageRecord],
        days: Int,
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> [DailyPoint] {
        guard days > 0 else { return [] }
        let endOfToday = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: endOfToday) else {
            return []
        }

        var bucket: [Date: [UsageScene: Int]] = [:]
        for r in records where r.success && r.timestamp >= start {
            let day = calendar.startOfDay(for: r.timestamp)
            guard let scene = r.sceneEnum else { continue }
            bucket[day, default: [:]][scene, default: 0] += r.totalTokens
        }

        var result: [DailyPoint] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: endOfToday)
            else { continue }
            for scene in UsageScene.allCases {
                let v = bucket[day]?[scene] ?? 0
                if v > 0 {
                    result.append(DailyPoint(day: day, scene: scene, tokens: v))
                }
            }
        }
        return result
    }
}
