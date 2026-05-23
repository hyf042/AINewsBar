# UI 样式打磨 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 AINewsBar 全 app 引入 Typography/TextColor/BrandColor 三套设计 token，统一字体/颜色/品牌色，柔和区域背景，文章行加 dot 未读指示器。

**Architecture:** 新增 `Sources/AINewsBar/DesignTokens/` 目录承载 3 个 token enum；菜单栏 8 个 view + 设置页 8 个 view 全部 token 化；ArticleRow 因 listHeight 写死保留 fixed font size 作为已知 trade-off；ProgressView/Spacing 不进 token。

**Tech Stack:** Swift 5.9 + SwiftUI + SwiftData + macOS 14+ + Swift Testing (`import Testing` / `@Test`)

**Spec 参考:** [`docs/superpowers/specs/2026-05-23-ui-style-polish-design.md`](../specs/2026-05-23-ui-style-polish-design.md) v3

**前置约束（项目根 CLAUDE.md）：**
- **不主动 git commit** —— 所有 `git commit` 步骤标注 ⚠️，等用户明确指令后执行
- 测试用 Swift Testing (`import Testing`)，避免 XCTest
- View 层不写单测（SwiftUI Preview-only），仅 DesignTokens 加单测

---

## Phase 1 — Token 文件落地

### Task 1.1: 创建 Typography.swift

**Files:**
- Create: `Sources/AINewsBar/DesignTokens/Typography.swift`

- [ ] **Step 1.1.1: 创建目录**

```bash
mkdir -p Sources/AINewsBar/DesignTokens
```

- [ ] **Step 1.1.2: 写入 Typography.swift**

```swift
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
```

- [ ] **Step 1.1.3: 验证编译**

Run: `swift build`
Expected: build succeed, 0 warning

---

### Task 1.2: 创建 BrandColor.swift（先于 TextColor，避免依赖未定义）

**Files:**
- Create: `Sources/AINewsBar/DesignTokens/BrandColor.swift`

- [ ] **Step 1.2.1: 写入 BrandColor.swift**

```swift
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
```

- [ ] **Step 1.2.2: 验证编译**

Run: `swift build`
Expected: build succeed, 0 warning（BrandColor 自包含）

---

### Task 1.3: 创建 TextColor.swift（依赖 BrandColor）

**Files:**
- Create: `Sources/AINewsBar/DesignTokens/TextColor.swift`

- [ ] **Step 1.3.1: 写入 TextColor.swift**

```swift
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
```

- [ ] **Step 1.3.2: 验证编译**

Run: `swift build`
Expected: build succeed, 0 warning（TextColor 引用 BrandColor 已定义）

---

### Task 1.4: 写 DesignTokens 单测

**Files:**
- Create: `Tests/AINewsBarTests/DesignTokensTests.swift`

- [ ] **Step 1.4.1: 写入 DesignTokensTests.swift**

```swift
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
```

- [ ] **Step 1.4.2: 跑单测验证**

Run: `swift test --filter DesignTokensTests`
Expected: 3 tests passed

- [ ] **Step 1.4.3: 跑全测试套确认不回归**

Run: `swift test`
Expected: 140 + 3 = 143 tests passed

- [ ] **Step 1.5 (⚠️ 用户授权后): Commit Phase 1**

```bash
git add Sources/AINewsBar/DesignTokens/ Tests/AINewsBarTests/DesignTokensTests.swift
git commit -m "feat(tokens): 引入 Typography/TextColor/BrandColor 三套 token

- Typography 8 档全 relative font 跟随 Dynamic Type（含 captionEmphasized
  锁定 bold trait）
- TextColor 4 档，tertiary 走 NSColor.tertiaryLabelColor 桥接
- BrandColor accent + accentSoft NSColor.dynamicProvider 明暗双值，
  surfaceMuted 用 Color.primary.opacity(0.06)
- DesignTokensTests 3 个单测覆盖 token 实例化与 dynamic provider 双值"
```

---

## Phase 2 — MenuBar popover 切换

### Task 2.1: HeaderView token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/MenuBar/HeaderView.swift`

- [ ] **Step 2.1.1: 改写 HeaderView**

把整个 HeaderView body 替换为：

```swift
var body: some View {
    HStack {
        Text("AI 资讯 [\(unreadCount)/\(totalCount)]")
            .font(Typography.headline)
            .foregroundStyle(TextColor.primary)
        Spacer()
        if refreshService.isSummarizing {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
                Text("AI 摘要中")
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
            }
        } else if refreshService.isRefreshing {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        }
        Button {
            Task { await refreshService.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(Typography.body)
        }
        .buttonStyle(.plain)
        .disabled(refreshService.isRefreshing || refreshService.isSummarizing)
        .help("刷新")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}
```

- [ ] **Step 2.1.2: 验证编译**

Run: `swift build`
Expected: build succeed

- [ ] **Step 2.1.3: 启动 app 走查 HeaderView**

Run:
```bash
pkill -x AINewsBar; sleep 1
swift build && cp .build/debug/AINewsBar build/AINewsBar.app/Contents/MacOS/AINewsBar
codesign --sign - --force build/AINewsBar.app
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

Expected: 菜单栏顶部 "AI 资讯 [n/N]" 显示，字号 ~13pt bold，刷新 icon ~13pt。点击刷新可触发 spinner。

---

### Task 2.2: FooterView token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/MenuBar/FooterView.swift`

- [ ] **Step 2.2.1: 改写 FooterView body**

参照 spec §3.1 FooterView 字段表替换：
- "最后更新" 标签：`.font(Typography.caption).foregroundStyle(TextColor.tertiary)`
- 时间值：`.font(Typography.caption).foregroundStyle(TextColor.secondary)`
- "今日 X tokens"：`.font(Typography.caption).foregroundStyle(TextColor.tertiary)`
- "⚠ N 个源失败" 按钮：`.font(Typography.caption).foregroundStyle(BrandColor.accent)`
- "设置" / "退出" 按钮：`.font(Typography.caption).foregroundStyle(TextColor.secondary)`
- "未刷新" 状态：`.font(Typography.caption).foregroundStyle(TextColor.tertiary)`

完整代码：

```swift
var body: some View {
    HStack {
        if let date = refreshService.lastRefreshDate {
            VStack(alignment: .leading, spacing: 1) {
                Text("最后更新")
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
                HStack(spacing: 6) {
                    Text(date, format: .dateTime.hour().minute().second())
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.secondary)
                    if todayTokenTotal > 0 {
                        Text("· 今日 \(UsageFormatter.formatTokens(todayTokenTotal)) tokens")
                            .font(Typography.caption)
                            .foregroundStyle(TextColor.tertiary)
                    }
                }
            }
        } else {
            Text("未刷新")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
        }
        Spacer()
        if refreshService.lastFetchErrorCount > 0 {
            Button("⚠ \(refreshService.lastFetchErrorCount) 个源失败") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.plain)
            .font(Typography.caption)
            .foregroundStyle(BrandColor.accent)
        }
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        } label: {
            Text("设置")
                .font(Typography.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(TextColor.secondary)

        Button {
            NSApp.terminate(nil)
        } label: {
            Text("退出")
                .font(Typography.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(TextColor.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
}
```

- [ ] **Step 2.2.2: 验证编译并走查**

Run: `swift build`
Expected: build succeed
Visual: footer 字号一致 caption2，"最后更新" 字号比之前 9pt 略大 1pt（10pt，几乎不可察）

---

### Task 2.3: DigestSectionView token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/MenuBar/DigestSectionView.swift`

- [ ] **Step 2.3.1: 改写 expandedBody**

```swift
private func expandedBody(digest: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 4) {
            Image(systemName: "brain")
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.secondary)
            Text("今日 AI 资讯摘要")
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.secondary)
            if let date = refreshService.lastDigestDate {
                Text(date, style: .time)
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
            }
            Spacer()
            if refreshService.isRegeneratingDigest {
                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
            } else {
                Button {
                    Task { await refreshService.forceRegenerateDigest() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TextColor.tertiary)
                .disabled(refreshService.isRegeneratingDigest || refreshService.isSummarizing)
                .help("重新生成摘要")
            }
            Image(systemName: (isExpanded || isHovered) ? "chevron.up" : "chevron.down")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
        }
        Text(digest)
            .font(Typography.callout)
            .foregroundStyle(TextColor.primary)
            .lineLimit((isExpanded || isHovered) ? nil : 5)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut(duration: 0.2), value: isExpanded || isHovered)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(BrandColor.surfaceMuted)
    .contentShape(Rectangle())
    .onTapGesture { isExpanded.toggle() }
    .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.2)) {
            isHovered = hovering
        }
    }
}
```

- [ ] **Step 2.3.2: 改写 placeholderBody**

```swift
private var placeholderBody: some View {
    HStack(spacing: 8) {
        Image(systemName: "brain")
            .font(Typography.titleEmphasized)
            .foregroundStyle(TextColor.tertiary)
        Text("今日 AI 资讯摘要")
            .font(Typography.titleEmphasized)
            .foregroundStyle(TextColor.tertiary)
        Spacer()
        if refreshService.isRegeneratingDigest || refreshService.isSummarizing {
            ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
            Text("生成中…")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
        } else {
            Button {
                Task { await refreshService.forceRegenerateDigest() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TextColor.tertiary)
            .disabled(refreshService.isRegeneratingDigest || refreshService.isSummarizing)
            .help("重新生成摘要")
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(BrandColor.surfaceMuted)
}
```

- [ ] **Step 2.3.3: 验证编译并走查**

Run: `swift build`
Visual: 摘要区背景从 `.quaternary` 变为更柔和的米白（浅色） / 柔和深灰（深色）。

---

### Task 2.4: RecommendSectionView token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/MenuBar/RecommendSectionView.swift`

- [ ] **Step 2.4.1: 改写 header / placeholderRows**

```swift
private func header(loading: Bool) -> some View {
    HStack(spacing: 4) {
        Image(systemName: "star.fill")
            .font(Typography.titleEmphasized)
            .foregroundStyle(loading ? AnyShapeStyle(TextColor.secondary) : AnyShapeStyle(BrandColor.accent))
        Text("AI 今日推荐")
            .font(Typography.titleEmphasized)
            .foregroundStyle(TextColor.secondary)
        if let date = refreshService.lastRecommendDate {
            Text(date, style: .time)
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
        }
        Spacer()
        if refreshService.isRegeneratingRecommend {
            ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
            Text("生成中…").font(Typography.caption).foregroundStyle(TextColor.tertiary)
        } else if loading && refreshService.isSummarizing {
            ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
            Text("生成中…").font(Typography.caption).foregroundStyle(TextColor.tertiary)
        } else {
            Button {
                Task { await refreshService.forceRegenerateRecommend() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TextColor.tertiary)
            .disabled(refreshService.isRegeneratingRecommend || refreshService.isSummarizing)
            .help("重新生成推荐")
        }
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 4)
}

private var placeholderRows: some View {
    ForEach([1, 2, 3, 4, 5], id: \.self) { i in
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(i)")
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(TextColor.tertiary)
                    .frame(width: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 11)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            if i < 5 { Divider().padding(.leading, 34) }
        }
    }
}
```

- [ ] **Step 2.4.2: 改 background**

把 `.background(.quaternary)` 替换为 `.background(BrandColor.surfaceMuted)`

- [ ] **Step 2.4.3: 验证编译**

Run: `swift build`

---

### Task 2.5: RecommendItemView token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/MenuBar/RecommendItemView.swift`

- [ ] **Step 2.5.1: 完整替换 body**

```swift
var body: some View {
    HStack(spacing: 0) {
        Rectangle()
            .fill(article.isRead ? Color.clear : BrandColor.accent)
            .frame(width: 3)

        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(article.isRead ? Typography.caption : Typography.captionEmphasized)
                .foregroundStyle(article.isRead ? AnyShapeStyle(TextColor.tertiary) : AnyShapeStyle(BrandColor.accent))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(article.feedTitle)
                    Spacer()
                    Text(formatArticleRelative(article.publishedAt))
                }
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)

                Text(article.title)
                    .font(article.isRead ? Typography.callout : Typography.calloutEmphasized)
                    .foregroundStyle(article.isRead ? TextColor.secondary : TextColor.primary)
                    .lineLimit(2)

                if let summary = article.aiSummary {
                    Text(summary)
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.secondary)
                        .lineLimit(isHovered ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: onTap)
    .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.15)) {
            isHovered = hovering
        }
    }
}
```

- [ ] **Step 2.5.2: 验证编译**

Run: `swift build`

---

### Task 2.6: ArticleListSection token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/MenuBar/ArticleListSection.swift`

- [ ] **Step 2.6.1: 改写 foldedHeader**

```swift
private var foldedHeader: some View {
    HStack(spacing: 6) {
        Image(systemName: "list.bullet")
            .font(Typography.titleEmphasized)
            .foregroundStyle(TextColor.secondary)
        Text("今日文章")
            .font(Typography.titleEmphasized)
            .foregroundStyle(TextColor.secondary)
        Text("· \(subtitle)")
            .font(Typography.caption)
            .foregroundStyle(TextColor.tertiary)
        Spacer()
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(Typography.caption)
            .foregroundStyle(TextColor.tertiary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(BrandColor.surfaceMuted)
    .contentShape(Rectangle())
    .onTapGesture {
        withAnimation(.easeInOut(duration: 0.25)) {
            isExpanded.toggle()
        }
    }
}
```

- [ ] **Step 2.6.2: 改写 articleList 中 "已读 (n)" 分隔行**

```swift
HStack {
    Text("已读 (\(readArticles.count))")
        .font(Typography.caption)
        .foregroundStyle(TextColor.tertiary)
    Spacer()
}
.padding(.horizontal, 12)
.padding(.vertical, 5)
.listRowInsets(EdgeInsets())
.listRowSeparator(.hidden)
.listRowBackground(Color(nsColor: .separatorColor).opacity(0.12))  // 不动
```

- [ ] **Step 2.6.3: 改写 loadingState / errorState / emptyState**

```swift
private var loadingState: some View {
    VStack(spacing: 8) {
        ProgressView()
        Text("正在获取资讯…")
            .foregroundStyle(TextColor.secondary)
            .font(Typography.caption)
    }
    .frame(maxWidth: .infinity)
    .padding(40)
}

private func errorState(_ message: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: "wifi.exclamationmark")
            .font(.largeTitle)  // 保留 largeTitle exception
            .foregroundStyle(TextColor.secondary)
        Text("获取失败")
            .font(Typography.body)
            .foregroundStyle(TextColor.secondary)
        Text(message)
            .font(Typography.caption)
            .foregroundStyle(TextColor.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }
    .frame(maxWidth: .infinity)
    .padding(40)
}

private var emptyState: some View {
    VStack(spacing: 8) {
        Image(systemName: "newspaper")
            .font(.largeTitle)  // 保留 largeTitle exception
            .foregroundStyle(TextColor.secondary)
        Text("暂无文章，点击刷新获取")
            .foregroundStyle(TextColor.secondary)
            .font(Typography.caption)
    }
    .frame(maxWidth: .infinity)
    .padding(40)
}
```

- [ ] **Step 2.6.4: 验证编译**

Run: `swift build`

---

### Task 2.7a: ArticleRowView 字号/颜色 token 化（不动结构）

**Files:**
- Modify: `Sources/AINewsBar/Views/ArticleRowView.swift`

> ⚠️ 本 step 仅做字号/颜色 token 化，**保留 VStack 主结构与 isRead 行底色**。
> 行底色去除 + dot 加入留到 Task 2.7b/2.7c。

具体改动表（保留 VStack { HStack(feed,time), title, summary }）：

| Element | Before | After |
|---------|--------|-------|
| feedTitle | `.font(.caption2).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.tertiary)` |
| 时间 | `.font(.caption2).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.tertiary)` |
| 标题 字体 | `.font(.system(size: 13, weight: article.isRead ? .regular : .semibold))` | **保留 fixed**（ArticleRow 例外，spec 0.1-1） |
| 标题 色 | `.foregroundStyle(article.isRead ? .secondary : .primary)` | `.foregroundStyle(article.isRead ? TextColor.secondary : TextColor.primary)` |
| 摘要 | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |

- [ ] **Step 2.7a.1: 应用 4 处颜色/字号替换**

- [ ] **Step 2.7a.2: 验证编译 + 走查**

Run: `swift build`
启动 → 文章列表展开：
- [ ] feed/时间字号 caption 10pt + tertiary 灰
- [ ] 标题字号仍 13pt fixed
- [ ] 标题色未读 primary / 已读 secondary

---

### Task 2.7b: ArticleRowView 去掉行底色

**Files:**
- Modify: `Sources/AINewsBar/Views/ArticleRowView.swift`

- [ ] **Step 2.7b.1: 删除 background 修饰符**

在 body 末尾找到这一行：

```swift
.background(article.isRead ? Color.clear : Color.accentColor.opacity(0.05))
```

**删除整行**。其他 modifier（`.contentShape` / `.onTapGesture` / `.onHover`）保留。

- [ ] **Step 2.7b.2: 验证编译 + 走查**

Run: `swift build`
启动 → 文章列表展开：
- [ ] 未读项**无背景色**（与已读项视觉无差异 —— 此时未读高亮丢失）
- [ ] 这是临时状态，下一步 Task 2.7c 加 dot 恢复未读视觉

---

### Task 2.7c: ArticleRowView 加 leading dot + HStack 重构

**Files:**
- Modify: `Sources/AINewsBar/Views/ArticleRowView.swift`

> ⚠️ 这是 Phase 2 最关键 task。完整替换 body 结构。

- [ ] **Step 2.7c.1: 完整替换 body**

```swift
var body: some View {
    HStack(alignment: .top, spacing: 8) {
        // 未读 dot —— 4pt 实心圆点 + brand orange + 顶部对齐首行
        // 已读项透明保留宽度避免抖动
        Circle()
            .fill(article.isRead ? Color.clear : BrandColor.accent)
            .frame(width: 4, height: 4)
            .padding(.top, 5)  // 与首行 baseline 对齐（经验值）

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(article.feedTitle)
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
                Spacer()
                Text(formatArticleRelative(article.publishedAt))
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
            }

            // ⚠️ 标题字号保留 fixed Font.system(size: 13)
            // 原因：ArticleListSection.listHeight=52 写死与 relative font 互斥
            // 详见 spec v3 修订 0.1-1
            Text(article.title)
                .font(.system(size: 13, weight: article.isRead ? .regular : .semibold))
                .foregroundStyle(article.isRead ? TextColor.secondary : TextColor.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let summary = article.aiSummary {
                Text(summary)
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.secondary)
                    .lineLimit(isHovered ? nil : 1)
                    .multilineTextAlignment(.leading)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
        }
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    // 注意：移除原 `.background(article.isRead ? .clear : Color.accentColor.opacity(0.05))`
    .contentShape(Rectangle())
    .onTapGesture(perform: onTap)
    .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.15)) {
            isHovered = hovering
        }
    }
}
```

- [ ] **Step 2.7c.2: 验证编译**

Run: `swift build`

- [ ] **Step 2.7c.3: 启动验证 dot 对齐**

启动 app，打开菜单栏 → 展开"今日文章"：
- [ ] 未读项 leading 4pt orange dot 与标题首行顶部对齐
- [ ] 已读项 leading 透明保留位置（标题不偏移）
- [ ] 行高仍为 ~52pt 范围内不被截断（listHeight 写死，需 verify 文章数 1/3/5+ 都不截断）

**如 dot 偏移**：调 `padding(.top, X)` X = 4-6 之间，verify 切换 isRead 时无抖动。

---

### Task 2.8: MenuBarView.aiUnavailableBanner token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/MenuBarView.swift`

> ⚠️ 仅改 aiUnavailableBanner 私有函数。body 与 openArticle **不动**。

- [ ] **Step 2.8.1: 改写 aiUnavailableBanner**

```swift
private func aiUnavailableBanner(reason: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(BrandColor.accent)
            .font(Typography.caption)
        Text("AI 不可用：\(reason)")
            .font(Typography.caption)
            .foregroundStyle(TextColor.tertiary)
            .lineLimit(1)
        Spacer()
        Button("去设置") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .buttonStyle(.plain)
        .font(Typography.caption)
        .foregroundStyle(BrandColor.accent)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity)
    .background(BrandColor.accentSoft)
}
```

- [ ] **Step 2.8.2: 验证编译**

Run: `swift build`

---

### Task 2.9: Phase 2 整体走查

- [ ] **Step 2.9.1: 全量启动验证**

```bash
pkill -x AINewsBar; sleep 1
swift build && cp .build/debug/AINewsBar build/AINewsBar.app/Contents/MacOS/AINewsBar
codesign --sign - --force build/AINewsBar.app
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

走查 checklist（按 spec §6.2 基础 5 区域）：
- [ ] HeaderView：hero 13pt bold，刷新 icon 13pt
- [ ] DigestSectionView：expandedBody + placeholderBody 字号/颜色/背景对齐
- [ ] RecommendSectionView：header + pickRows + placeholderRows 字号/颜色/背景对齐
- [ ] ArticleListSection foldedHeader（折叠态）+ articleList（含 loading/error/empty）
- [ ] FooterView："最后更新" 标签 10pt（视觉 ≤1pt 差异）
- [ ] ArticleRow：未读 4pt orange dot，已读透明占位，背景已去除
- [ ] RecommendItem：3pt 左色条贯穿，index 与色条同色

- [ ] **Step 2.9.2: 浅深两模式走查**

System Settings → Appearance 切 Light/Dark，菜单栏关开后：
- [ ] 浅色：区域背景柔和米白（6% 黑透明），可见但不重
- [ ] 深色：区域背景柔和深灰（6% 白透明），可见但不重
- [ ] BrandColor.accent 浅色饱和、深色降饱和
- [ ] BrandColor.accentSoft 深色 20% 可见（AI banner 触发态走查）

- [ ] **Step 2.10 (⚠️ 用户授权后): Commit Phase 2**

```bash
git add Sources/AINewsBar/Views/MenuBar/ Sources/AINewsBar/Views/MenuBarView.swift Sources/AINewsBar/Views/ArticleRowView.swift
git commit -m "refactor(ui): MenuBar popover 全量切换至 token 体系

- 8 view（HeaderView/FooterView/DigestSectionView/RecommendSectionView/
  RecommendItemView/ArticleListSection/ArticleRowView/MenuBarView）字号/颜色
  全量 token 化
- 文章行加 4pt orange dot 未读指示 + 去掉行底色（accentColor.opacity(0.05)）
- ArticleRow 标题保留 fixed Font.system(size:13)（与 listHeight 互斥的已知 trade-off）
- 区域背景 .quaternary → BrandColor.surfaceMuted (6% Color.primary)
- AI banner / 失败按钮 / '去设置' 跳转统一 BrandColor.accent"
```

---

## Phase 3 — Settings 同步

### Task 3.1: SettingsView 不动

- [ ] **Step 3.1.1: 确认 SettingsView 仅 TabView 容器，不需改动**

Run: `grep -n 'font\|foregroundStyle\|background' Sources/AINewsBar/Views/SettingsView.swift`
Expected: 无相关调用或仅有 SwiftUI 系统默认调用，**跳过此 view**

---

### Task 3.2: UsageSettingsView token 化（含 22pt stat）

**Files:**
- Modify: `Sources/AINewsBar/Views/Settings/UsageSettingsView.swift`

具体改动表（line:before → after）：

| Line | Element | Before | After |
|------|---------|--------|-------|
| 35 | "今日用量" 标题 | `.font(.headline)` | `.font(Typography.titleEmphasized).foregroundStyle(TextColor.secondary)` |
| 50 | "趋势" 标题 | `.font(.headline)` | `.font(Typography.titleEmphasized).foregroundStyle(TextColor.secondary)` |
| 69-70 | "暂无用量数据" | `.font(.callout).foregroundStyle(.secondary)` | `.font(Typography.body).foregroundStyle(TextColor.secondary)` |
| 109-110 | statCard label | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |
| 112 | statCard value (22pt) | `.font(.system(size: 22, weight: .semibold, design: .rounded))` | `.font(Typography.stat)` |
| 41 | statCard tint | `tint: stats.failures > 0 ? .orange : .secondary` | `tint: stats.failures > 0 ? BrandColor.accent : TextColor.secondary` |

**Charts 区**（line 74-93）：BarMark / chartForegroundStyleScale / AxisMarks 全部**保留不动**。

- [ ] **Step 3.2.1: 应用上表 6 处替换**

按 line 顺序逐处 Edit。每处替换后保存。

- [ ] **Step 3.2.2: 验证编译**

Run: `swift build`
Expected: build succeed, 0 warning

- [ ] **Step 3.2.3: 启动 + 用量 Tab 走查**

启动 app → 打开设置 → 切换到"用量" Tab：
- [ ] "今日用量" / "趋势" 标题字号同 13pt semibold（与菜单栏区域标题一致）
- [ ] 3 个 statCard 大数字仍 ~22pt rounded（视觉无变化）
- [ ] failure > 0 时数字色为 BrandColor.accent（橙）
- [ ] Charts 柱图字号 / 颜色不变化（蓝/绿/橙堆叠保留）

---

### Task 3.3: FeedsSettingsView + FeedRowView 改动

**Files:**
- Modify: `Sources/AINewsBar/Views/Settings/FeedRowView.swift`
- Modify: `Sources/AINewsBar/Views/Settings/FeedsSettingsView.swift`

具体改动表：

**FeedRowView.swift**

| Line | Element | Before | After |
|------|---------|--------|-------|
| 12 | feed.title | `.font(.system(size: 13))` | `.font(Typography.body).foregroundStyle(TextColor.primary)` |
| 14-15 | URL | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |
| 28-29 | "检测" 按钮 | `.font(.caption).foregroundStyle(Color.accentColor)` | `.font(Typography.caption).foregroundStyle(BrandColor.accent)` |
| 45-46 | builtin feed.title | `.font(.system(size: 13)).foregroundStyle(feed.isEnabled ? .primary : .secondary)` | `.font(Typography.body).foregroundStyle(feed.isEnabled ? TextColor.primary : TextColor.secondary)` |
| 48-49 | builtin URL | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |
| 67-68 | builtin "检测" 按钮 | `.font(.caption).foregroundStyle(Color.accentColor)` | `.font(Typography.caption).foregroundStyle(BrandColor.accent)` |

**FeedsSettingsView.swift**

| Line | Element | Before | After |
|------|---------|--------|-------|
| 58-59 | 底部汇总文案 | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |

- [ ] **Step 3.3.1: 应用上表替换**

- [ ] **Step 3.3.2: 验证编译 + 走查**

Run: `swift build`
启动 → 设置 → "订阅源" Tab：
- [ ] feed 名 13pt（无变化）
- [ ] URL caption 字号 + secondary 灰
- [ ] "检测" / "检测全部" 按钮文字色橙（BrandColor）

---

### Task 3.4: AddFeedSheet token 化（仅 Text/Image，不动结构）

**Files:**
- Modify: `Sources/AINewsBar/Views/Settings/AddFeedSheet.swift`

> ⚠️ 表单结构（Form/Section/TextField/Toggle）**不动**！只改 Text/Image 的 font/foregroundStyle。

具体改动表：

| Line | Element | Before | After |
|------|---------|--------|-------|
| 14 | "添加 RSS 订阅源" 标题 | `.font(.headline)` | `.font(Typography.titleEmphasized).foregroundStyle(TextColor.primary)` |
| 54 | "正在检测…" | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |
| 58 | ✓ icon | `.foregroundStyle(.green).font(.caption)` | **不动**（绿语义色保留）+ `.font(Typography.caption)` |
| 59 | "检测通过..." | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |
| 63 | ⚠ icon | `.foregroundStyle(.orange).font(.caption)` | `.foregroundStyle(BrandColor.accent).font(Typography.caption)` |
| 64 | 错误消息 | `.font(.caption).foregroundStyle(.secondary).lineLimit(2)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary).lineLimit(2)` |

**"保存"/"取消" 按钮（如有 `.buttonStyle(...)` 调用）保留系统样式**。

- [ ] **Step 3.4.1: 应用上表 6 处替换**

- [ ] **Step 3.4.2: 验证编译 + 走查**

Run: `swift build`
启动 → 设置 → "订阅源" Tab → 点 "+" 添加：
- [ ] "添加 RSS 订阅源" 标题 13pt semibold
- [ ] 检测中/通过/失败三态行内文案 caption 字号
- [ ] ⚠ icon 颜色从 .orange 改为 BrandColor.accent（视觉一致）

---

### Task 3.5: APISettingsView token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/Settings/APISettingsView.swift`

具体改动表：

| Line | Element | Before | After |
|------|---------|--------|-------|
| 39 | "检测可用性" 按钮文字 | `.foregroundStyle(Color.accentColor)` | `.foregroundStyle(BrandColor.accent)` |
| 42 | API Key hint | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |
| 88 | "检测中…" | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |
| 92 | ✓ icon | `.foregroundStyle(.green).font(.caption)` | **不动**（绿语义色保留）+ `.font(Typography.caption)` |
| 93 | "API Key 和模型均可用" | `.font(.caption).foregroundStyle(.secondary)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary)` |
| 97 | ✗ icon | `.foregroundStyle(.red).font(.caption)` | **不动**（红语义色保留）+ `.font(Typography.caption)` |
| 98 | 错误消息 | `.font(.caption).foregroundStyle(.secondary).lineLimit(2)` | `.font(Typography.caption).foregroundStyle(TextColor.secondary).lineLimit(2)` |

**模型选择 Picker / TextField 不动**。

- [ ] **Step 3.5.1: 应用上表 7 处替换**

- [ ] **Step 3.5.2: 验证编译 + 走查**

Run: `swift build`
启动 → 设置 → "API" Tab：
- [ ] "检测可用性" 按钮文字色橙（BrandColor，不是系统蓝）
- [ ] 检测中/通过/失败三态字号 caption + secondary 灰
- [ ] 绿/红状态 icon 保留

---

### Task 3.6: GeneralSettingsView token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/Settings/GeneralSettingsView.swift`

- [ ] **Step 3.6.1: 读源代码定位 font 调用**

Run: `cat Sources/AINewsBar/Views/Settings/GeneralSettingsView.swift`

GeneralSettingsView 仅 26 行，包含 1 个 Toggle。grep 结果显示该文件无 explicit font/foregroundStyle 调用（系统默认）。

- [ ] **Step 3.6.2: 如有 Text，加 token 化**

如 Toggle label 或描述文本使用了 `.font(...)`，按规则替换：
- Toggle label → `Typography.body` + `TextColor.primary`
- Toggle 副说明 → `Typography.caption` + `TextColor.secondary`

否则**保留系统默认**（macOS Form 默认字号在系统 Settings UI 已合理）。

- [ ] **Step 3.6.3: 验证编译 + 走查**

Run: `swift build`
启动 → 设置 → "通用" Tab：
- [ ] 开机启动 Toggle 显示正常

---

### Task 3.7: CheckStatus / CheckStatusIcon token 化

**Files:**
- Modify: `Sources/AINewsBar/Views/Settings/CheckStatus.swift`

具体改动表：

| Line | Element | Before | After |
|------|---------|--------|-------|
| 25 | ✓ icon | `.font(.system(size: 13))` | `.font(Typography.caption)` |
| 30 | ✗ icon | `.font(.system(size: 13))` | `.font(Typography.caption)` |

**绿/红 foregroundStyle 保留**（语义色，line 24 / 29 不动）。

- [ ] **Step 3.7.1: 应用上表 2 处替换**

- [ ] **Step 3.7.2: 验证编译 + 走查**

Run: `swift build`
启动 → 设置 → 多 Tab 出现的 CheckStatusIcon：
- [ ] 绿✓ / 红✗ icon 字号从 13pt 降至 caption (10pt) 与周边文本对齐
- [ ] 颜色保留绿/红

---

### Task 3.8: Phase 3 整体走查

- [ ] **Step 3.8.1: 启动验证**

启动 app → 打开设置 → 走查 4 Tab：
- [ ] **订阅源 Tab**：feed 名/URL/检测状态字号对齐
- [ ] **API Tab**：Key 输入/检测按钮字号对齐
- [ ] **用量 Tab**：今日卡片 22pt rounded 大数字保留，Charts 默认字号
- [ ] **通用 Tab**：开机启动 Toggle 字号对齐
- [ ] 浅深两模式都走查

- [ ] **Step 3.9 (⚠️ 用户授权后): Commit Phase 3**

```bash
git add Sources/AINewsBar/Views/Settings/
git commit -m "refactor(ui): Settings 4 Tab 同步至 token 体系

- UsageSettingsView 统计卡片 22pt rounded 进 Typography.stat token
- FeedsSettingsView/FeedRowView/AddFeedSheet/APISettingsView/
  GeneralSettingsView 字号 + 文字层级全量 token 化
- CheckStatus 绿/红/灰语义色保留（不进 BrandColor）
- AddFeedSheet 保存按钮跟系统强调色（已知差异）
- Charts 字号保留 SwiftUI 默认"
```

---

## Phase 4 — 收尾验证

### Task 4.1: grep 扫描遗漏散点

**Files:** N/A（仅扫描）

- [ ] **Step 4.1.1: Font 散点扫描**

```bash
rg "\.system\(size:" Sources/AINewsBar/Views/
rg "\.caption2\b" Sources/AINewsBar/Views/
rg "\.caption\b" Sources/AINewsBar/Views/
rg "\.footnote" Sources/AINewsBar/Views/
rg "\.headline" Sources/AINewsBar/Views/
rg "Font\.body\b" Sources/AINewsBar/Views/
rg "Font\.callout\b" Sources/AINewsBar/Views/
```

预期：仅 `ArticleRowView.swift` 保留 1-2 处 `.system(size:13)`（标题 fixed 例外）；Settings 系统组件保留原生调用。

- [ ] **Step 4.1.2: Color 散点扫描**

```bash
rg "Color\.orange" Sources/AINewsBar/Views/
rg "Color\.primary\b" Sources/AINewsBar/Views/
rg "Color\.secondary\b" Sources/AINewsBar/Views/
rg "\.tertiary\b" Sources/AINewsBar/Views/
rg "Color\.accentColor" Sources/AINewsBar/Views/
rg "\.quaternary" Sources/AINewsBar/Views/
```

预期：`.quaternary` 应清零；`Color.orange` 应清零；`Color.primary/.secondary` 应已替换到 `TextColor.primary/.secondary`；`Color.accentColor` 应清零。

- [ ] **Step 4.1.3: 修补遗漏点**

如果上述扫描发现意外残留（除已知例外），按 spec §3.1/§3.2 对应规则补改并 verify。

---

### Task 4.2: Dynamic Type 走查（spec §6.2 R6）

- [ ] **Step 4.2.1: 切 System Settings → Appearance → Text Size**

- [ ] Default：基线
- [ ] Large：DigestSection / RecommendItem / Settings 字号变化协调；ArticleListSection 文章行**字号不变化**（已知 trade-off）
- [ ] Largest：版面溢出可控（不要求完美，但内容不截断）

如发现严重错位，在 spec §5 R6 记录新发现。

---

### Task 4.3: Light/Dark 实时切换走查（spec §6.2 R9 两子项）

- [ ] **Step 4.3.1: 子项 A 关闭再开**

1. 关闭菜单栏 popover
2. System Settings → Appearance 切到 Light/Dark
3. 重新点击菜单栏图标打开 popover
4. **预期通过**：所有 BrandColor.accent / accentSoft / surfaceMuted 跟随新模式

- [ ] **Step 4.3.2: 子项 B 保持打开**

1. 菜单栏 popover **保持打开状态**
2. 在另一个终端窗口执行：
   ```bash
   # 切到 Dark
   defaults write -g AppleInterfaceStyle Dark
   killall -KILL SystemUIServer

   # 等 1 秒
   sleep 1

   # 切回 Light
   defaults delete -g AppleInterfaceStyle
   killall -KILL SystemUIServer
   ```
3. **不点击菜单栏图标**——观察 popover 内 BrandColor 是否跟随切换
4. **预期**：surfaceMuted 等 SwiftUI 原生语义颜色会跟随；BrandColor.accent / accentSoft（NSColor.dynamicProvider 包装的 SwiftUI Color）**可能不跟随**（spec R9 已知风险）

**若 BrandColor 不跟随**：
- 在 `CLAUDE.md` 踩坑加 #32 记录"BrandColor SwiftUI Color 包装 NSColor.dynamicProvider 不响应运行时 Appearance 切换"
- 不在本轮修复，作为后续 ticket 用 `@Environment(\.colorScheme)` 重构

---

### Task 4.4: 系统强调色冲突走查（spec §6.2 R8）

- [ ] **Step 4.4.1: System Settings → Appearance → Highlight color 切到非橙（如紫色）**

- [ ] 菜单栏所有 `BrandColor.accent` 点保持橙色（独立于系统强调色）：推荐区色条/index、未读 dot、AI banner、failure 按钮、"去设置"链接
- [ ] AddFeedSheet "保存"按钮跟随系统强调色（紫）—— **已知差异，记录不修**

---

### Task 4.5: List 兼容性走查（spec §6.2 R7）

- [ ] **Step 4.5.1: 展开"今日文章"区**

- [ ] 浅色：`articleList` 的 `listRowBackground (separatorColor.opacity(0.12))` 与外层 `surfaceMuted` 在浅色无视觉杂色
- [ ] 深色同验
- [ ] "已读 (n)" 分隔行 separatorColor 与外层 surfaceMuted 叠加不糊

---

### Task 4.6: 边界场景走查（spec §6.3）

- [ ] 文章数 = 0：empty state 字号/颜色对齐
- [ ] 文章数 = 1：dot + 标题不挤压
- [ ] 标题超长（lineLimit=2）：dot 仍与首行顶部对齐（不滑到中间）
- [ ] AI 摘要尚未生成：占位 placeholder 颜色 `TextColor.tertiary`
- [ ] 推荐 5 项满载 + 已读混合：色条贯穿无断裂（踩坑 #20 不复现）

---

### Task 4.7: CLAUDE.md 增量更新

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 4.7.1: 加 2026-05-23 增量描述**

在"2026-05-22 晚间增量"之后追加：

```markdown
**2026-05-23 增量**：UI 样式 token 化（spec/plan 在 `docs/superpowers/`）
1. 新增 `Sources/AINewsBar/DesignTokens/` 目录：`Typography.swift`（7 档 relative
   font + captionEmphasized）、`TextColor.swift`（4 档，tertiary 走
   NSColor.tertiaryLabelColor）、`BrandColor.swift`（accent/accentSoft 用
   NSColor.dynamicProvider 明暗双值 + 原生 sRGB）
2. 菜单栏 popover 全量 token 化（8 view）+ 设置页 4 Tab 同步（7 view）
3. 区域背景 `.quaternary` → `BrandColor.surfaceMuted` (6% Color.primary)
4. 文章行加 4pt orange leading dot + 去掉 `accentColor.opacity` 行底色
5. ArticleRow 标题保留 fixed `Font.system(size:13)`（与 `ArticleListSection.
   listHeight=52` 互斥的已知 a11y trade-off）
6. CheckStatus 绿/红语义色保留（不 brand 化）；AddFeedSheet 保存按钮跟系统强调色
   （已知差异）
7. DesignTokensTests 新增 3 个单测（token 实例化 + dynamic provider 双值验证）
```

设计决策表追加：
```markdown
| Typography 体系 | relative font 7 档（headline/stat/titleEmphasized/body/
calloutEmphasized/callout/caption/captionEmphasized） | 跟随系统 Dynamic Type；
ArticleRow 因 listHeight 写死保留 fixed Font.system(size:13) |
| Color token | TextColor 4 档 + BrandColor accent/accentSoft/surfaceMuted |
tertiary 用 NSColor.tertiaryLabelColor 桥接（SwiftUI 无 Color.tertiary 静态）；
BrandColor 用 NSColor.dynamicProvider + 原生 sRGB 避免桥接损失 |
```

---

### Task 4.8: 测试 + 启动最终验证

- [ ] **Step 4.8.1: 全测试套**

Run: `swift test`
Expected: 143/143 passed（原 140 + DesignTokens 新 3）

- [ ] **Step 4.8.2: 启动最终验证**

```bash
pkill -x AINewsBar; sleep 1
swift build && cp .build/debug/AINewsBar build/AINewsBar.app/Contents/MacOS/AINewsBar
codesign --sign - --force build/AINewsBar.app
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

打开菜单栏 + 设置全 Tab，确认无 build warning / 无 visual regression。

- [ ] **Step 4.9 (⚠️ 用户授权后): Commit Phase 4 + push**

```bash
git add CLAUDE.md
git commit -m "docs(claude): 同步 UI 样式 token 化至 CLAUDE.md

- 新增 DesignTokens 目录与 3 套 token 体系记录
- 加 ArticleRow fixed font 例外说明
- 加 BrandColor NSColor.dynamicProvider 决策表
- spec/plan 位置 docs/superpowers/"

# 若用户进一步授权：
git push origin main
```

---

## 总验收清单

最终交付清单（拼装自 §6.1/§6.2/§6.3）：

### 编译 & 测试
- [ ] `swift build` 0 warning / 0 error
- [ ] `swift test` 143/143 passed
- [ ] CLAUDE.md 已更新

### 视觉走查（浅 + 深 × 8 场景）
- [ ] HeaderView / FooterView / DigestSection / RecommendSection / ArticleListSection / ArticleRow / RecommendItem / aiUnavailableBanner

### a11y / 系统行为
- [ ] Dynamic Type 3 档（small / default / large）
- [ ] Light/Dark 切换 2 子项（关闭再开 / 保持打开）
- [ ] 系统强调色切到非橙不影响 BrandColor
- [ ] List 与 surfaceMuted 叠加无视觉杂色

### 边界场景
- [ ] 文章数 0 / 1 / 5+ 都正确渲染
- [ ] 标题 lineLimit=2 时 dot 仍顶部对齐
- [ ] 推荐 5 项满载色条贯穿无断裂

---

## 相关文档

- [设计 spec v3](../specs/2026-05-23-ui-style-polish-design.md)
- 项目根 `CLAUDE.md`（架构决策 + 踩坑记录）

**作者**: Claude (via `superpowers:writing-plans` skill)
**版本**: v1 (2026-05-23)
