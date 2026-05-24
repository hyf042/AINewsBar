import Testing
import SwiftUI
import AppKit
@testable import AINewsBar

@Suite("DesignTokens")
struct DesignTokensTests {

    // MARK: - Typography

    @Test("Typography token 实例化无副作用")
    func typographyTokensInstantiable() {
        // Font 是非可选类型，简单引用即证明构造无 crash
        let tokens: [Font] = [
            Typography.headline,
            Typography.stat,
            Typography.titleEmphasized,
            Typography.body,
            Typography.calloutEmphasized,
            Typography.callout,
            Typography.caption,
            Typography.captionEmphasized
        ]
        #expect(tokens.count == 8)
    }

    // MARK: - BrandColor dynamic provider 双值

    /// 在指定 appearance 下求值 NSColor.dynamicProvider，
    /// 返回当时的实际 RGB（用于断言明暗模式返回不同值）。
    private func resolveColor(_ color: Color, in appearanceName: NSAppearance.Name) -> NSColor {
        let appearance = NSAppearance(named: appearanceName)!
        var resolved: NSColor!
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)!
        }
        return resolved
    }

    @Test("BrandColor.accent 明暗双值不同")
    func brandAccentDualValues() {
        let aqua = resolveColor(BrandColor.accent, in: .aqua)
        let dark = resolveColor(BrandColor.accent, in: .darkAqua)
        // 浅色 R=1.0 G=0.50 B=0.05 / 深色 R=1.0 G=0.62 B=0.32
        // 绿色分量应有显著差异
        #expect(abs(aqua.greenComponent - dark.greenComponent) > 0.05)
    }

    @Test("BrandColor.accentSoft 明暗双 opacity")
    func brandAccentSoftDualOpacity() {
        let aqua = resolveColor(BrandColor.accentSoft, in: .aqua)
        let dark = resolveColor(BrandColor.accentSoft, in: .darkAqua)
        // 浅色 alpha=0.08 / 深色 alpha=0.20
        #expect(abs(aqua.alphaComponent - dark.alphaComponent) > 0.05)
    }
}
