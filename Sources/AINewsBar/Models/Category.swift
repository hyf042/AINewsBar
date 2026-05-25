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
    /// L3: 解析失败（脏数据 / 未来加新 cat 再降级）时 Log，否则脏数据会被静默打到 AI tab
    /// 污染推荐/日报；Console.app 能看见信号便于排查。
    static func from(rawValue: String?) -> Category {
        if let raw = rawValue, let cat = Category(rawValue: raw) {
            return cat
        }
        // nil 是合法路径（首次启动 prefs 未 set），仅对"非 nil 但无法解析"打 log
        if let raw = rawValue {
            Log.write("[Category] unknown rawValue '\(raw)', falling back to .ai")
        }
        return .ai
    }
}
