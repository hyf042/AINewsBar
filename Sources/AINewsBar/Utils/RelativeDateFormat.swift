import Foundation

/// 文章发布时间相对格式化
///
/// 设计目标：让用户一眼看出"昨天"，避免 SwiftUI 内置 `.relative` 风格无方向感的问题。
///
/// 映射规则（中文）：
/// - 未来 / < 60s    → "刚刚"
/// - < 60 min        → "X 分钟前"
/// - 同一日（≥1h）   → "X 小时前"
/// - 昨日            → "昨天"
/// - 2–6 天前         → "N 天前"
/// - 更早            → "M/d"
///
/// 时钟与日历通过参数注入，便于单测。
func formatArticleRelative(
    _ date: Date,
    now: Date = Date(),
    calendar: Calendar = .current
) -> String {
    let delta = now.timeIntervalSince(date)

    if delta < 60 { return "刚刚" }
    if delta < 3600 {
        return "\(Int(delta / 60)) 分钟前"
    }

    if calendar.isDateInToday(date) {
        return "\(Int(delta / 3600)) 小时前"
    }
    if calendar.isDateInYesterday(date) {
        return "昨天"
    }

    let startOfToday = calendar.startOfDay(for: now)
    let startOfDate = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
    if days <= 6 {
        return "\(days) 天前"
    }

    let fmt = DateFormatter()
    fmt.calendar = calendar
    fmt.locale = Locale(identifier: "zh_CN")
    fmt.dateFormat = "M/d"
    return fmt.string(from: date)
}
