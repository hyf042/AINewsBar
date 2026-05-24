import SwiftUI
import AppKit  // 仅为 NSColor.tertiaryLabelColor

/// TextColor token 体系。
///
/// primary/secondary 使用 SwiftUI 内置 Color；tertiary 桥接 macOS 原生 NSColor 系统色
/// （SwiftUI 没有 `Color.tertiary` 静态属性，只有 `.tertiary` ShapeStyle，
/// 无法直接装进 `Color` 类型的 token enum）。
enum TextColor {
    /// 顶部 hero、未读文章标题、摘要正文、digest 正文。
    static let primary = Color.primary

    /// 区域标题、已读文章标题、文章/推荐摘要文案。
    static let secondary = Color.secondary

    /// feed 名、相对时间、chevron、辅助状态、"已读 (n)" 分隔行。
    /// 用 NSColor.tertiaryLabelColor 桥接，自动适配明暗模式（macOS 标准做法）。
    static let tertiary = Color(nsColor: .tertiaryLabelColor)

    /// 推荐 index、未读 dot、AI banner 文字 + icon、品牌强调点。
    static let accent = BrandColor.accent
}
