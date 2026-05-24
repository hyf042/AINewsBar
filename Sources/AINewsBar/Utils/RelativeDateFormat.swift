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

    // 注意：不能用 `calendar.isDateInToday(date)` / `isDateInYesterday(date)` ——
    // 这两个 API 内部以系统 `Date()` 锚定，会忽略传入的 `now` 参数，
    // 导致跨日 fixture 测试在 fixture-day ≠ real-today 时全线失败。
    // 改用 startOfDay(for: now) 手算 days，让时钟注入语义闭环。
    let startOfNow = calendar.startOfDay(for: now)
    let startOfDate = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0

    if days == 0 {
        return "\(Int(delta / 3600)) 小时前"
    }
    if days == 1 {
        return "昨天"
    }
    if days <= 6 {
        return "\(days) 天前"
    }

    let fmt = DateFormatter()
    fmt.calendar = calendar
    fmt.locale = Locale(identifier: "zh_CN")
    fmt.dateFormat = "M/d"
    return fmt.string(from: date)
}
