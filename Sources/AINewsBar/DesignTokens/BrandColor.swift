import SwiftUI
import AppKit

/// 品牌色 token 体系。
///
/// 使用 NSColor.dynamicProvider 实现明暗双值，**原生 sRGB RGB 构造** 避免 SwiftUI Color 桥接损失。
/// 不引入 Asset Catalog（SPM 配置成本不值）。
///
/// 已知风险（spec R9）：SwiftUI Color 包装 NSColor.dynamicProvider 在 popover detached 重开时
/// 初始采样问题可能不重新求值。菜单栏 popover 关开是 full view rebuild 场景，实际不易触发。
enum BrandColor {
    /// 全局品牌橙。深色降饱和约 15% 防夜间刺眼。
    /// sRGB 色空间显式声明，跨 Wide Color 显示器保持一致。
    static let accent: Color = {
        let light = NSColor(srgbRed: 1.0, green: 0.50, blue: 0.05, alpha: 1.0)  // ≈ systemOrange
        let dark  = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.32, alpha: 1.0)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }()

    /// 高亮背景（AI banner / 未读高亮背景）。
    /// 浅色 8% / 深色 20% —— 深色下 8% 几乎不可见，需提升 opacity 保证可辨。
    static let accentSoft: Color = {
        let light = NSColor(srgbRed: 1.0, green: 0.50, blue: 0.05, alpha: 0.08)
        let dark  = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.32, alpha: 0.20)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }()

    /// 区域柔和背景（替换 `.background(.quaternary)`）。
    /// SwiftUI 语义颜色自动适配（light: 黑 6% / dark: 白 6%）。
    /// 与 accent/accentSoft 路径不一致是 "背景 vs 品牌" 语义区别的合理后果。
    static let surfaceMuted = Color.primary.opacity(0.06)
}
