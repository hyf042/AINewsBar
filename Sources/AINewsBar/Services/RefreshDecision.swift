import Foundation

// MARK: - 触发决策：纯函数集，独立于 RefreshService 状态，便于单元测试

enum RefreshDecision {

    /// 摘要完成率：0.0 - 1.0。空集合视为 1.0（无需生成时直接放行后续步骤）
    static func completionRate(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 1.0 }
        return Double(completed) / Double(total)
    }

    /// 推荐是否需要重新生成（Plan A 增量判断）
    /// - hasNewArticles: 本轮是否有新文章入库
    /// - isEmpty: 当前推荐列表是否为空
    /// - currentCount: 当前有摘要的文章数
    /// - lastCount: 上次生成推荐时的有摘要文章数
    /// - deltaThreshold: 摘要增量触发阈值（默认 3）
    static func shouldRegenerateRecommend(
        hasNewArticles: Bool,
        isEmpty: Bool,
        currentCount: Int,
        lastCount: Int,
        deltaThreshold: Int = 3
    ) -> Bool {
        if hasNewArticles { return true }
        if isEmpty { return true }
        return (currentCount - lastCount) >= deltaThreshold
    }

    /// 日报是否需要重新生成
    /// - hasNewArticles: 本轮是否有新文章入库
    /// - isPresent: 当前是否已有日报内容
    /// - lastDate: 当前日报的生成时间
    /// - currentCount: 当前有摘要的文章数
    /// - lastCount: 上次生成日报时的有摘要文章数
    /// - now: 当前时间（注入以便测试）
    /// - regenerateInterval: 同日内日报重生成的最小间隔（默认 3 小时）
    /// - deltaThreshold: 摘要增量触发阈值（默认 3）
    static func shouldRegenerateDigest(
        hasNewArticles: Bool,
        isPresent: Bool,
        lastDate: Date?,
        currentCount: Int,
        lastCount: Int,
        now: Date = Date(),
        regenerateInterval: TimeInterval = 3 * 3600,
        deltaThreshold: Int = 3,
        calendar: Calendar = .current
    ) -> Bool {
        // 首次：无内容 → 直接生成
        if !isPresent { return true }
        // Plan A: 增量足够 → 生成
        if (currentCount - lastCount) >= deltaThreshold { return true }
        // 有新文章 + 时间窗口已过
        if hasNewArticles, withinRegenerationWindow(lastDate: lastDate, now: now,
                                                     interval: regenerateInterval,
                                                     calendar: calendar) {
            return true
        }
        return false
    }

    /// 仅时间窗口判断：跨日 OR 间隔已超
    static func withinRegenerationWindow(
        lastDate: Date?,
        now: Date,
        interval: TimeInterval,
        calendar: Calendar = .current
    ) -> Bool {
        guard let last = lastDate else { return true }
        if !calendar.isDate(last, inSameDayAs: now) { return true }
        return now.timeIntervalSince(last) > interval
    }
}
