import Foundation

/// 主视野互斥状态：当前展开的区域。
/// recommend ↔ article 互斥单字段。digest 不参与（独立默认展开）。
/// 默认 .recommend（推荐区为主视野，符合产品定位）。
///
/// 切 tab / popover 重开自动 reset 到 .recommend：
/// - cat 切换 onChange(selectedTab) 显式 reset
/// - popover 关闭→重开：MenuBarView 的 @State 重建自动 reset
enum ExpandedSection {
    case recommend
    case article
}
