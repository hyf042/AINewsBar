import Foundation

/// 资讯分类。每个 Feed/Article 归属一个 Category；UI 顶部 segmented control 切分。
/// 顺序与 UI 显示顺序一致（AI 默认选中）。
enum Category: String, CaseIterable, Codable, Sendable {
    case ai
    case earnings
    case news

    /// 中文显示名（用于 UI segmented control / Settings Picker）
    var displayName: String {
        switch self {
        case .ai:        return "AI"
        case .earnings:  return "财报"
        case .news:      return "新闻"
        }
    }

    /// 从持久化 String 安全恢复（fallback .ai）
    static func from(rawValue: String?) -> Category {
        guard let raw = rawValue, let cat = Category(rawValue: raw) else {
            return .ai
        }
        return cat
    }
}
