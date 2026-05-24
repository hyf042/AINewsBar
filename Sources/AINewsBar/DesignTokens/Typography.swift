import SwiftUI

/// Typography token 体系。
///
/// **全部使用 SwiftUI relative font system**，跟随 macOS 系统 Text Size 设置（Dynamic Type）。
/// 不使用 `Font.system(size:)` 固定字号，避免降级 a11y。
///
/// 唯一例外：ArticleRowView 标题因 `ArticleListSection.listHeight = 52` 写死，
/// 使用 fixed `Font.system(size: 13)`，不走此 token。详见 spec v3 修订 0.1-1。
enum Typography {
    /// HeaderView 顶部 hero（"AI 资讯 [n/N]"）。
    /// macOS 默认 ~13pt **bold**（注意：是 bold 不是 semibold，与 titleEmphasized 字重差 1 档）。
    /// 字重差异是 "hero 强调" 的语义信号，刻意保留。
    static let headline = Font.headline

    /// UsageSettings 统计卡片大数字。
    /// macOS 默认 ~22pt，rounded 设计强化数字识别。
    static let stat = Font.system(.title, design: .rounded, weight: .semibold)

    /// 推荐项 13pt 标题加重（保留语义槽位，目前未使用 —— ArticleRow 走 fixed font）。
    /// macOS 默认 ~13pt semibold。
    static let titleEmphasized = Font.system(.body, weight: .semibold)

    /// 正文、摘要。macOS 默认 ~13pt regular。
    static let body = Font.body

    /// 推荐项 12pt 未读标题。macOS 默认 ~12pt semibold。
    static let calloutEmphasized = Font.system(.callout, weight: .semibold)

    /// 推荐项 12pt 已读标题、digest 正文、次要标题。macOS 默认 ~12pt regular。
    static let callout = Font.callout

    /// 区域标签、feed 名、相对时间、辅助状态、"已读 (n)" 分隔行、chevron 等。
    /// macOS 默认 ~10pt regular。
    static let caption = Font.caption2

    /// 加重的 caption（RecommendItem.index 数字未读态、placeholderRows index）。
    /// 替代 `caption.weight(.bold)` 调用 —— relative font 上 weight modifier 对 bold trait
    /// 可能回落到 semibold，定义专用 token 锁定渲染。
    static let captionEmphasized = Font.system(.caption2, weight: .bold)
}
