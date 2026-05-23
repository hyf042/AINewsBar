# UI 样式打磨设计文档（v3）

**日期**: 2026-05-23
**类型**: 视觉优化（typography / color token 化）
**范围**: 全 app（菜单栏 popover + 设置页）
**前置约束**: 排版（padding/spacing/layout）尽量不变
**版本**: v3（基于 architect agent 第二轮 review 修订）

---

## 0.1 v3 修订要点（vs v2）

| # | v2 问题（第二轮 review 发现） | v3 修复 |
|---|--------|--------|
| 0.1-1 | **P1-3 根本冲突**：ArticleListSection `listHeight: 52` 写死与 Typography relative font 互斥，Dynamic Type 大字号下行内容会撑高被截断 | **ArticleRowView 字号回到 fixed size**：`Font.system(size:13)` 替代 `Typography.titleEmphasized/body`；listHeight=52 保留。**ArticleRow 明确放弃 Dynamic Type 响应**，其他 view 仍 relative。Trade-off 记录到 R6/§7 |
| 0.1-2 | **P1-2 BrandColor.surfaceMuted opacity 0.04 在 List 上经合成层 alpha 被吞，浅色几乎不可见** | opacity 0.04 → **0.06**（多 50% 可见度），仍用 `Color.primary.opacity` 路径（与 accent NSColor dynamicProvider 路径不一致是"背景 vs 品牌"语义区别的合理后果） |
| 0.1-3 | **P1-1 SwiftUI Color 桥接深层问题**：`Color(nsColor: NSColor.dynamicProvider)` 在 popover detached 重开时不一定重新求值 dynamicProvider | **接受为 R9 已知风险**：菜单栏 popover 关开是 full view rebuild 场景，初始采样问题实际不易触发。验收 §6.2 加显式走查项观测 |
| 0.1-4 | macOS `Font.headline` 实测是 13pt **bold**（不是 semibold），与 `titleEmphasized = .body + semibold` **字重不一致** | §2.1 注释修正 headline 描述为"13pt bold"；明确接受 hero 与文章标题字重存在 1 档差异（bold > semibold）作为"hero 强调"语义信号 |
| 0.1-5 | `Typography.caption.weight(.bold)` 在 relative font 上 bold trait 可能回落到 semibold | 新增 `Typography.captionEmphasized = Font.system(.caption2, weight: .bold)`，RecommendItem.index 与 placeholderRows 改用此 token |
| 0.1-6 | DesignTokensTests 极简（`!= nil` 永真）形同虚设 | §4 Phase 1 单测加 dynamic provider 双值测试：通过 NSColor.dynamicProvider 强制构造 .aqua / .darkAqua 两个 appearance，验证返回不同 NSColor |
| 0.1-7 | §4 Phase 4 grep 漏扫 `Color\.secondary` / `Color\.primary` / `Font\.body` / `Font\.callout` 等 | grep pattern 列表补全 |
| 0.1-8 | §7.1 防 creep 边界缺 `ArticleListSection` "已读 (n)" 分隔行 `listRowBackground` 与 Charts 字号 | §7.1 显式增加 2 条边界 |
| 0.1-9 | §6.2 "运行时切换 Appearance" 走查步骤不具体（保持 popover 打开 vs 关闭再开行为差异是 R9 关键观测点） | §6.2 R9 走查步骤拆为 2 个子项（关闭再开 + 保持打开） |
| 0.1-10 | §3.2 "plain style 时文字色用 BrandColor.accent" 语焉不详 | §3.2 显式列出哪些按钮属 `.buttonStyle(.plain)`，跟随 BrandColor；其他按钮（系统主样式）跟随系统强调色 |

**未修复（明确权衡）**：
- P1-1 SwiftUI Color 桥接深层问题：在 SwiftUI + macOS 14 范畴内几乎无解（弃用 Color 改 ShapeStyle inline 是过度工程）。接受 R9 + 验收走查
- P1-2 surfaceMuted 与 accent 路径不一致：故意保留作为"背景 vs 品牌"语义区别

---

## 0. v2 修订要点（vs v1）

| # | v1 问题 | v2 修复 |
|---|--------|--------|
| 0-1 | macOS `Font.headline` 字号事实错误（写为 17pt，实际 macOS 上默认 ~13pt） | 全 token 改用 **relative font**（`Font.headline / .body / .callout / .caption2`），不再使用错误的 fixed size 数字 |
| 0-2 | Token 固定字号 `Font.system(size:)` 完全无视 Dynamic Type，**降级了可访问性** | Token 全部走 relative font system style，自动响应 macOS 系统 Text Size 设置 |
| 0-3 | `TextColor.tertiary = Color.tertiary` 编译不通过（SwiftUI 无此 Color 静态属性） | 改 `Color(nsColor: .tertiaryLabelColor)` 走 macOS 原生 NSColor 桥接 |
| 0-4 | `Color(light:dark:)` 用 `NSColor(SwiftUI.Color)` 桥接对 dynamic color 转换有损 | Brand 色用 `NSColor(name:dynamicProvider:)` + **原生 RGB**（`NSColor(red:green:blue:)` 直接构造），避免 SwiftUI Color 桥接 |
| 0-5 | `BrandColor.accentSoft` 单值 0.08 在深色模式下几乎不可见 | accentSoft 也走 dynamic provider，浅色 0.08 / 深色 0.20 双值 |
| 0-6 | `Typography.title` 同时承担两种 weight（未读 semibold / 已读 regular），ArticleRow 已读处绕过 token 用 inline 字号 | 拆 `titleEmphasized` / `body` 两档；推荐项同理拆 `calloutEmphasized` / `callout` |
| 0-7 | `.caption2 → caption` 字号方向反了（caption2 ≈ 10pt，caption 也 ≈ 10pt，但 fixed 11pt 反而是上调） | 用 relative `Font.caption2`，不强行指定 pt，跟随系统 |
| 0-8 | 漏切：`UsageSettingsView` 22pt rounded 统计大数字 | 加 `Typography.stat = Font.system(.title, design: .rounded, weight: .semibold)` |
| 0-9 | 漏切：`DigestSectionView.placeholderBody` / `RecommendSectionView.placeholderRows` / `ArticleListSection.errorState` `.largeTitle` icon | §3.1 补完所有分支 |
| 0-10 | `ProgressView` 三档 scale（0.55/0.6/0.7）与 §7 不交付声明矛盾 | 明确：**保留为非 token 散点**，仅 inline 收敛到 2 档约定值；§7 加强声明 |
| 0-11 | 风险章节缺 Dynamic Type / List 兼容性 / 系统强调色 / 色空间 / popover 缓存 | §5 补齐 5 类盲点 |
| 0-12 | 验收清单缺 a11y 切换 / 系统强调色变更 / List 兼容性走查 | §6.2/6.3 补齐 |
| 0-13 | Scope creep 风险（AddFeedSheet 表单结构、RecommendItem 已读色条形态、MenuBarView body 范围） | §7 显式追加 3 条防 creep 边界 |

**未修复（被明确权衡）**：
- 9pt micro 不单独建档：原 `.system(size: 9)` 用法（仅 FooterView "最后更新"标签）升级到 `Font.caption2`（≈10pt）。理由：macOS HIG 推荐最小可读字号 10pt，9pt 已低于阈值且不响应 Dynamic Type；视觉变化 ≤1pt 几乎不可察。
- 不引入 Asset Catalog：SPM `.process("Resources")` 配置成本不值，且 NSColor dynamicProvider + 原生 RGB 已能彻底避免 SwiftUI Color 桥接损失。

---

## 1. 背景与目标

### 1.1 现状问题

AINewsBar 经过多轮重构后业务架构已稳定（140 单元测试），但 UI 视觉层存在以下散点问题：

1. **字号杂乱**：9 个不同字号 token 混用（`.system(size: 9/10/11/12/13)` + `.caption2/.caption/.footnote/.headline`），缺乏统一的语义层级
2. **背景偏重**：3 个区域全部使用 `.background(.quaternary)`，浅色模式下灰背景叠加观感"灰扑扑"
3. **强调色不统一**：推荐区 `Color.orange`，未读文章 `Color.accentColor.opacity(0.05)`（系统蓝），两套并存
4. **同语义字段层级混乱**：ArticleRow feedTitle 用 `.secondary`，RecommendItem 同字段用 `.tertiary`

### 1.2 目标调性

**macOS 原生精致化** —— 保留系统视觉语言，通过建立 token 化的 typography 与 color 体系实现全 app 视觉一致 + 灰度柔和 + 品牌锚点统一。

### 1.3 范围边界

| 改 | 不改 |
|---|---|
| 字号体系（建 Typography token，relative font） | padding / spacing 散点 |
| 文字层级（建 TextColor token） | 区域顺序、组件布局 |
| 强调色（建 BrandColor token） | 业务逻辑、Service 层 |
| 背景色（`.quaternary` → `surfaceMuted`） | 单元测试（140 项不动） |
| 未读视觉（文章行加 dot + 去背色） | AI banner 版面/逻辑、CheckStatus 语义色 |
| Icon 字号（顺着 Typography token） | Spacing token、IconSize token、ProgressScale token |
| ProgressView scale 收敛到 2 档（inline 修） | （不建专门 token） |

---

## 2. Token 设计

### 2.1 Typography（7 档，全 relative font）

新建 `Sources/AINewsBar/DesignTokens/Typography.swift`：

```swift
import SwiftUI

/// Typography token 体系。
/// 全部使用 SwiftUI relative font system，跟随 macOS 系统 Text Size 设置。
/// 不使用 `Font.system(size:)` 固定字号，避免降级 Dynamic Type 可访问性。
enum Typography {
    /// HeaderView 顶部 hero（"AI 资讯 [n/N]"）。
    /// macOS 默认 ~13pt **bold**（注意：是 bold 不是 semibold，与 titleEmphasized 字重差 1 档）。
    /// 字重差异是 "hero 强调" 的语义信号，刻意保留。
    static let headline = Font.headline

    /// UsageSettings 统计卡片大数字（"今日 X tokens" 等）。
    /// macOS 默认 ~22pt，rounded 设计强化数字识别。
    static let stat = Font.system(.title, design: .rounded, weight: .semibold)

    /// 推荐项 13pt 标题加重（仅在 RecommendItem 13pt 场景使用——目前未使用，
    /// 保留语义槽位以备 ArticleRow 之外的 13pt semibold 标题需求）。
    /// macOS 默认 ~13pt semibold。
    /// 注：ArticleRowView 因 listHeight=52 写死 + Dynamic Type 互斥（见 v3 修订 0.1-1），
    /// 使用 fixed `Font.system(size:13, weight:.semibold/.regular)` 不走此 token。
    static let titleEmphasized = Font.system(.body, weight: .semibold)

    /// 正文、摘要。
    /// macOS 默认 ~13pt regular。
    static let body = Font.body

    /// 推荐项 12pt 未读标题。
    /// macOS 默认 ~12pt semibold。
    static let calloutEmphasized = Font.system(.callout, weight: .semibold)

    /// 推荐项 12pt 已读标题、digest 正文、次要标题。
    /// macOS 默认 ~12pt regular。
    static let callout = Font.callout

    /// 区域标签、feed 名、相对时间、辅助状态、"已读 (n)" 分隔行、chevron 等。
    /// macOS 默认 ~10pt regular。
    static let caption = Font.caption2

    /// 加重的 caption（RecommendItem.index 数字未读态、placeholderRows index）。
    /// 替代原 `caption.weight(.bold)` 调用——relative font 上 weight modifier
    /// 对 bold trait 可能回落到 semibold，定义专用 token 锁定渲染。
    static let captionEmphasized = Font.system(.caption2, weight: .bold)
}
```

**Icon 复用约定**：SF Symbol 字号复用 Typography token：

| 场景 | 调用 |
|------|------|
| 区域标题 icon（brain / star / list.bullet） | `Image(...).font(Typography.titleEmphasized)` |
| 微型按钮 icon（重新生成 arrow.clockwise / chevron） | `Image(...).font(Typography.caption)` |
| AI banner exclamation icon | `Image(...).font(Typography.caption)` |
| HeaderView 刷新按钮 icon | `Image(...).font(Typography.body)` |

**ProgressView scale 约定**（不建 token，仅 inline 收敛到 2 档）：

| 场景 | scale | 调用点 |
|------|-------|--------|
| Header 大号 inline（refresh 旋转） | `0.7` | `HeaderView` |
| 区域 inline 小号（"生成中…"） | `0.55` | `HeaderView` summarizing / `DigestSectionView` / `RecommendSectionView` |

原 `0.6` 一处（HeaderView refresh）下调为 `0.7` 或保持 `0.6`——保留 inline 散点，明确**不进 token**。

### 2.2 TextColor（4 档）

新建 `Sources/AINewsBar/DesignTokens/TextColor.swift`：

```swift
import SwiftUI
import AppKit  // 仅为 NSColor.tertiaryLabelColor

/// TextColor token 体系。
/// primary/secondary 使用 SwiftUI 内置 Color；tertiary 桥接 macOS 原生 NSColor 系统色
/// （SwiftUI 没有 `Color.tertiary` 静态属性，只有 `.tertiary` ShapeStyle）。
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

**一致性修复**：`ArticleRow.feedTitle` 与 `ArticleRow.publishedAt` 由 `.secondary` 下调为 `TextColor.tertiary`，与 `RecommendItem` 同字段保持一致。

### 2.3 BrandColor

新建 `Sources/AINewsBar/DesignTokens/BrandColor.swift`：

```swift
import SwiftUI
import AppKit

/// 品牌色 token 体系。
/// 使用 NSColor.dynamicProvider 实现明暗双值，原生 RGB 构造避免 SwiftUI Color 桥接损失。
/// 不引入 Asset Catalog（SPM 配置成本不值）。
enum BrandColor {
    /// 全局品牌橙。深色降饱和约 15% 防夜间刺眼。
    /// sRGB 色空间显式声明，跨 Wide Color 显示器保持一致。
    static let accent: Color = {
        let light = NSColor(srgbRed: 1.0, green: 0.50, blue: 0.05, alpha: 1.0)  // 接近 systemOrange
        let dark  = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.32, alpha: 1.0)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }()

    /// 高亮背景（AI banner / 未读高亮背景）。
    /// 浅色 8% / 深色 20%——深色下 8% 几乎不可见，需提升 opacity 保证可辨。
    static let accentSoft: Color = {
        let light = NSColor(srgbRed: 1.0, green: 0.50, blue: 0.05, alpha: 0.08)
        let dark  = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.32, alpha: 0.20)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }()

    /// 区域柔和背景（替换 `.background(.quaternary)`）。
    /// SwiftUI 语义颜色自动适配（light: 黑 6% / dark: 白 6%）。
    /// v3 修订：opacity 0.04 → 0.06，避免 List 合成层 alpha 吞掉后浅色不可见。
    /// 与 accent/accentSoft 的 NSColor dynamicProvider 路径不一致——
    /// 这是 "背景 vs 品牌" 语义区别的合理后果，不是 bug。
    static let surfaceMuted = Color.primary.opacity(0.06)
}
```

---

## 3. 视觉变更点详细清单

### 3.1 MenuBar 区（8 个 view）

#### `HeaderView` (`Sources/AINewsBar/Views/MenuBar/HeaderView.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| "AI 资讯 [n/N]" 标题 | `.headline`（默认色） | `Typography.headline` + `TextColor.primary` |
| "AI 摘要中" 文案 | `.caption2` + `.secondary` | `Typography.caption` + `TextColor.tertiary` |
| 刷新按钮 icon | `.system(size:12)` | `Typography.body`（responsive ≈13pt） |
| ProgressView (refresh) | `scaleEffect(0.7)` | 保留 0.7 |
| ProgressView (summarizing inline) | `scaleEffect(0.6)` | 收敛到 0.55 |

#### `FooterView` (`Sources/AINewsBar/Views/MenuBar/FooterView.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| "最后更新" 标签 | `.system(size:9)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary`（**字号 9pt → caption2 ≈10pt，a11y 改进**） |
| 时间值 | `.caption2` + `.secondary` | `Typography.caption` + `TextColor.secondary` |
| "今日 X tokens" | `.caption2` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| "⚠ N 个源失败" 按钮文字 | `.caption2` + `Color.orange` | `Typography.caption` + `BrandColor.accent` |
| "设置" / "退出" 按钮 | `.caption` + `.secondary` | `Typography.caption` + `TextColor.secondary` |
| "未刷新" 状态 | `.caption2` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |

#### `DigestSectionView` (`Sources/AINewsBar/Views/MenuBar/DigestSectionView.swift`)

**`expandedBody` 分支**：

| 元素 | 原 | 新 |
|------|----|----|
| brain icon | `.footnote` + `.secondary` | `Typography.titleEmphasized` + `TextColor.secondary` |
| "今日 AI 资讯摘要" 标题 | `.footnote.weight(.medium)` + `.secondary` | `Typography.titleEmphasized` + `TextColor.secondary` |
| 时间 | `.system(size:10)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| 重新生成 icon | `.system(size:10)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| chevron | `.system(size:9)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| 正文 | `.system(size:12)` + `.primary` | `Typography.callout` + `TextColor.primary` |
| **背景** | `.background(.quaternary)` | `.background(BrandColor.surfaceMuted)` |
| ProgressView 重生成 | `scaleEffect(0.55)` | 保留 0.55 |

**`placeholderBody` 分支**：

| 元素 | 原 | 新 |
|------|----|----|
| brain icon | `.footnote` + `.tertiary` | `Typography.titleEmphasized` + `TextColor.tertiary` |
| 占位 "今日 AI 资讯摘要" 标题 | `.footnote.weight(.medium)` + `.tertiary` | `Typography.titleEmphasized` + `TextColor.tertiary` |
| "生成中…" | `.caption2` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| 重新生成 icon | `.system(size:10)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| ProgressView | `scaleEffect(0.55)` | 保留 0.55 |
| **背景** | `.background(.quaternary)` | `.background(BrandColor.surfaceMuted)` |

#### `RecommendSectionView` (`Sources/AINewsBar/Views/MenuBar/RecommendSectionView.swift`)

**`header` 分支**：

| 元素 | 原 | 新 |
|------|----|----|
| star icon (loading) | `.footnote` + `Color.secondary` | `Typography.titleEmphasized` + `TextColor.secondary` |
| star icon (loaded) | `.footnote` + `Color.orange` | `Typography.titleEmphasized` + `BrandColor.accent` |
| "AI 今日推荐" 标题 | `.footnote.weight(.medium)` + `.secondary` | `Typography.titleEmphasized` + `TextColor.secondary` |
| 时间 | `.system(size:10)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| 重新生成 icon | `.system(size:10)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| "生成中…" | `.caption2` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| ProgressView | `scaleEffect(0.55)` | 保留 0.55 |

**`placeholderRows` 骨架条**：

| 元素 | 原 | 新 |
|------|----|----|
| placeholder index 数字 | `.system(size:11, weight:.bold)` + `.tertiary` | `Typography.captionEmphasized` + `TextColor.tertiary` |
| 骨架条 RoundedRectangle fill | `Color.secondary.opacity(0.12)` | **保留**（已是语义合理的占位） |
| Divider | `Divider().padding(.leading, 34)` | **保留**（placeholderRows 与 pickRows 不同——placeholder 没有色条，divider 不会切断） |

**整体背景**：`.background(.quaternary)` → `.background(BrandColor.surfaceMuted)`

#### `RecommendItemView` (`Sources/AINewsBar/Views/MenuBar/RecommendItemView.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| 左色条 (未读) | `Rectangle().fill(Color.orange).frame(width:3)` | `Rectangle().fill(BrandColor.accent).frame(width:3)` |
| 左色条 (已读) | `Color.clear.frame(width:3)` | **保留透明占位**（防 §6.3 色条贯穿断裂踩坑 #20 复发） |
| index 数字 (未读) | `.system(size:11, weight:.bold)` + `Color.orange` | `Typography.captionEmphasized` + `BrandColor.accent` |
| index 数字 (已读) | `.system(size:11, weight:.regular)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| feed 名 + 时间 | `.caption2` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| 标题 (未读) | `.system(size:12, weight:.semibold)` + `.primary` | `Typography.calloutEmphasized` + `TextColor.primary` |
| 标题 (已读) | `.system(size:12, weight:.regular)` + `.secondary` | `Typography.callout` + `TextColor.secondary` |
| 摘要 | `.caption2` + `.secondary` | `Typography.caption` + `TextColor.secondary` |

#### `ArticleListSection` (`Sources/AINewsBar/Views/MenuBar/ArticleListSection.swift`)

**`foldedHeader`**：

| 元素 | 原 | 新 |
|------|----|----|
| list.bullet icon | `.footnote` + `.secondary` | `Typography.titleEmphasized` + `TextColor.secondary` |
| "今日文章" 标题 | `.footnote.weight(.medium)` + `.secondary` | `Typography.titleEmphasized` + `TextColor.secondary` |
| subtitle "· N 未读" | `.caption` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| chevron | `.system(size:9)` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| **背景** | `.background(.quaternary)` | `.background(BrandColor.surfaceMuted)` |

**`articleList` "已读 (n)" 分隔行**：

| 元素 | 原 | 新 |
|------|----|----|
| "已读 (n)" 文字 | `.caption` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |
| listRowBackground | `Color(nsColor: .separatorColor).opacity(0.12)` | **保留**（macOS 原生系统色，已自动适配明暗） |

**`loadingState` / `errorState` / `emptyState`**：

| 元素 | 原 | 新 |
|------|----|----|
| ProgressView | （默认大小） | 保留默认 |
| "正在获取资讯…" / "暂无文章" 文字 | `.caption` + `.secondary` | `Typography.caption` + `TextColor.secondary` |
| `wifi.exclamationmark` / `newspaper` icon | `.largeTitle` + `.secondary` | **保留 `.largeTitle`**（错误/空态使用大 icon 是 macOS 标准模式；不进 Typography token，作为明确的"非内容字号" exception） |
| "获取失败" 文字 | （默认色，default font） | `Typography.body` + `TextColor.secondary` |
| 错误详情文字 | `.caption2` + `.tertiary` | `Typography.caption` + `TextColor.tertiary` |

#### `ArticleRowView` (`Sources/AINewsBar/Views/ArticleRowView.swift`)

> **特殊例外**：因 `ArticleListSection.listHeight = 52` 写死与 Typography relative font 互斥（v3 修订 0.1-1），
> 本 view 的**标题字号保留 fixed `Font.system(size:13)`**，**不进 Typography token**。
> 已读/未读 weight 直接 inline 表达。其他字段（feedTitle/时间/摘要）仍走 Typography token（小字段行高变化对 listHeight 影响小）。
> 该 view **明确放弃 Dynamic Type 响应**，作为已知 a11y trade-off 记录到 §5 R6。

| 元素 | 原 | 新 |
|------|----|----|
| feedTitle | `.caption2` + `.secondary` | `Typography.caption` + `TextColor.tertiary` **（一致性修复：secondary → tertiary）** |
| 时间 | `.caption2` + `.secondary` | `Typography.caption` + `TextColor.tertiary` **（一致性修复）** |
| 标题 (未读) | `.system(size:13, weight:.semibold)` + `.primary` | **保留 fixed** `Font.system(size:13, weight:.semibold)` + `TextColor.primary` |
| 标题 (已读) | `.system(size:13, weight:.regular)` + `.secondary` | **保留 fixed** `Font.system(size:13, weight:.regular)` + `TextColor.secondary` |
| 摘要 | `.caption` + `.secondary` | `Typography.caption` + `TextColor.secondary` |
| **去掉行底色** | `background(article.isRead ? .clear : Color.accentColor.opacity(0.05))` | **删除** |
| **新增 leading dot** | （无） | `Circle().fill(article.isRead ? .clear : BrandColor.accent).frame(width:4, height:4).padding(.top, 5)` |
| **HStack 结构** | `VStack { HStack {feed,time}, title, summary }` | `HStack(alignment: .top, spacing: 8) { dot; VStack(原全部内容) }` |

**HStack 改造对齐基线说明**：
- dot 用 `.padding(.top, 5)` 与首行（feedTitle/时间 HStack）顶部对齐
- 5pt 是经验值：Typography.caption 在 macOS 默认 ~10pt，行高 ~13pt，首行 baseline 大约在 9pt 处，dot 直径 4pt 顶部偏 5pt 可使 dot 视觉中心与首行 baseline 对齐
- **不使用 `firstTextBaseline` alignment**——SwiftUI 在 Circle/Text 混合时 baseline alignment 行为不稳定，inline padding 更可控
- 已读项 dot 透明但保留 4pt 占位，避免已读/未读切换时整行 leading 偏移抖动

#### `MenuBarView` (`Sources/AINewsBar/Views/MenuBarView.swift`)

**仅修改 `aiUnavailableBanner` 子函数**（**`body` 与 `openArticle` 不动**，防 scope creep）：

| 元素 | 原 | 新 |
|------|----|----|
| exclamationmark icon | `.system(size:11)` + `Color.orange` | `Typography.caption` + `BrandColor.accent` |
| 文案 "AI 不可用：xxx" | `.caption` + `.secondary` | `Typography.caption` + `TextColor.tertiary` |
| "去设置" 按钮 | `.caption` + `Color.accentColor` | `Typography.caption` + `BrandColor.accent` |
| **banner 背景** | `Color.orange.opacity(0.08)` | `BrandColor.accentSoft`（双值，深色 0.20） |

### 3.2 Settings 区（8 个 view + 1 工具文件）

#### `SettingsView` (`Sources/AINewsBar/Views/SettingsView.swift`)

仅 TabView 容器，**字号/颜色完全跟系统默认**——不动。

#### `UsageSettingsView` (`Sources/AINewsBar/Views/Settings/UsageSettingsView.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| 今日卡片大数字（tokens / 调用 / 失败） | `Font.system(size: 22, weight: .semibold, design: .rounded)` | `Typography.stat` |
| 卡片 label（"今日 Tokens" 等） | `.headline` | `Typography.titleEmphasized` + `TextColor.secondary` |
| 卡片副文案 / 时间说明 | `.caption` / `.caption2` | `Typography.caption` + `TextColor.tertiary` |
| "近 7 天" / "近 30 天" Picker label | `.callout` 或类似 | `Typography.body` + `TextColor.primary` |
| Charts 坐标轴/图例 | （SwiftUI Charts 默认） | **保留 Charts 默认字号**（不动） |

#### `FeedsSettingsView` + `FeedRowView` + `BuiltInFeedRowView` (`Sources/AINewsBar/Views/Settings/FeedsSettingsView.swift` + `FeedRowView.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| feed 名 | （默认 body） | `Typography.body` + `TextColor.primary` |
| URL | `.caption` + `.secondary` | `Typography.caption` + `TextColor.secondary` |
| "检测中..." / "检测全部" 状态行内文案 | `.caption2` 等 | `Typography.caption` + `TextColor.tertiary` |
| "检测" / "检测全部" 按钮 | 系统按钮 + 默认色 | **保留系统按钮样式**；文字颜色用 `BrandColor.accent`（仅 plain style 时） |
| CheckStatus icon 颜色 | 绿/红/灰 系统语义色 | **保留**（不 brand 化，语义色不可替换） |

#### `AddFeedSheet` (`Sources/AINewsBar/Views/Settings/AddFeedSheet.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| 表单 label / placeholder / 错误提示文案 | （混合 default / caption） | `Typography.body` / `Typography.caption` + 对应 TextColor 层级 |
| **表单结构** | TextField / Toggle / VStack 等 | **完全保留**（防 scope creep：不动 layout） |
| "保存" / "取消" 主按钮 | 系统强调色 | **保留系统按钮样式**——系统会跟用户系统强调色而非 BrandColor，已知差异，验收 §6.2 走查 |

#### `APISettingsView` (`Sources/AINewsBar/Views/Settings/APISettingsView.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| API Key label / hint | （混合 default / caption） | `Typography.body` / `Typography.caption` + 对应 TextColor |
| 模型选择 Picker | 系统 Picker 默认 | **不动** |
| "检测可用性" 按钮 | 系统按钮 + 默认色 | 文字色 `BrandColor.accent`（仅 plain style 时） |
| 检测状态行内 CheckStatusIcon | 绿/红/灰 | **保留语义色** |

#### `GeneralSettingsView` (`Sources/AINewsBar/Views/Settings/GeneralSettingsView.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| "开机启动" Toggle label | （默认 body） | `Typography.body` + `TextColor.primary` |
| Toggle 副说明 | `.caption` + `.secondary` | `Typography.caption` + `TextColor.secondary` |

#### `CheckStatus.swift` / `CheckStatusIcon` (`Sources/AINewsBar/Views/Settings/CheckStatus.swift`)

| 元素 | 原 | 新 |
|------|----|----|
| icon 字号 | `.footnote` / `.system(size:N)` | `Typography.caption`（统一到 caption2 ≈10pt） |
| 状态文案 | `.caption2` | `Typography.caption` + `TextColor.tertiary` |
| **绿/红/灰语义色** | 系统色 | **保留**（不 brand 化） |

---

## 4. 实施分阶段

### Phase 1 — Token 文件落地（~1 单元）

1. 新建 `Sources/AINewsBar/DesignTokens/` 目录
2. 写 `Typography.swift` / `TextColor.swift` / `BrandColor.swift` 三个文件
3. **新增单测** `Tests/AINewsBarTests/DesignTokensTests.swift`，覆盖：
   - Typography token 实例化非 crash（不仅是 `!= nil`，因 Font 是非可选）：例如 `let _ = Typography.headline; #expect(true)` 至少证明运行时构造无副作用
   - BrandColor dynamic provider 在两种 appearance 下返回不同 NSColor：
     ```swift
     let aquaColor = nsColorFor(appearance: .aqua, in: BrandColor.accent)
     let darkColor = nsColorFor(appearance: .darkAqua, in: BrandColor.accent)
     #expect(aquaColor.redComponent != darkColor.redComponent ||
             aquaColor.blueComponent != darkColor.blueComponent)
     ```
     辅助函数 `nsColorFor(appearance:in:)` 通过 `NSAppearance(named:)` 切换 currentDrawing 后读取实际 RGB
   - BrandColor.accentSoft 同上验证双值
   - Typography.stat token 存在性（防误删）
4. `swift build && swift test` 通过
5. Commit：`feat(tokens): 引入 Typography/TextColor/BrandColor 三套 token`

### Phase 2 — MenuBar popover 切换（~1.5 单元）

1. 按 §3.1 清单逐 view 替换字号 / 颜色调用
2. ArticleRow 加 dot + 去背色 + HStack 重构（重点 verify dot 对齐）
3. `swift build` + 手动验证（浅/深两模式打开菜单走查）
4. Commit：`refactor(ui): MenuBar popover 全量切换至 token 体系 + 文章行未读视觉升级`

### Phase 3 — Settings 同步（~0.5 单元）

1. 按 §3.2 清单逐 view 替换
2. 4 个 Tab 全部走查（浅/深）
3. Commit：`refactor(ui): Settings 4 Tab 同步至 token 体系`

### Phase 4 — 收尾验证（~0.5 单元）

1. **完整 grep 扫描遗漏**（Font / Color / 系统强调色三类）：
   ```bash
   # Font 散点
   rg "\.system\(size:" Sources/AINewsBar/Views/   # 应仅在 ArticleRowView (fixed 13pt 例外) 出现
   rg "\.caption2\b" Sources/AINewsBar/Views/
   rg "\.caption\b" Sources/AINewsBar/Views/
   rg "\.footnote" Sources/AINewsBar/Views/
   rg "\.headline" Sources/AINewsBar/Views/
   rg "Font\.body\b" Sources/AINewsBar/Views/
   rg "Font\.callout\b" Sources/AINewsBar/Views/

   # Color 散点
   rg "Color\.orange" Sources/AINewsBar/Views/
   rg "Color\.primary\b" Sources/AINewsBar/Views/        # 应在 TextColor.primary 后清空
   rg "Color\.secondary\b" Sources/AINewsBar/Views/      # 应在 TextColor.secondary 后清空
   rg "\.tertiary\b" Sources/AINewsBar/Views/            # foregroundStyle(.tertiary) 应替换为 TextColor.tertiary
   rg "Color\.accentColor" Sources/AINewsBar/Views/
   rg "\.quaternary" Sources/AINewsBar/Views/            # 应清零
   ```
   **预期结果**：
   - `ArticleRowView.swift` 保留 1-2 处 `.system(size:13)`（已知 exception 见 §3.1 注释）
   - `SettingsView.swift` 系统 TabView / Picker / Form 保留原生调用
   - `UsageSettingsView.swift` Charts 部分保留 SwiftUI Charts 默认调用
   - `CheckStatus.swift` 绿/红/灰语义色保留
2. CLAUDE.md 增量更新（新增 DesignTokens 目录说明 + 设计决策 token 化条目）
3. `swift test` 全 140 测试 + 新增 token 单测通过
4. 启动验证 + push

---

## 5. 风险与回滚

### 5.1 风险

| # | 风险 | 等级 | 缓解 |
|---|------|-----|------|
| R1 | Token 字号集中下调让用户主观觉得"字变小" | 低 | v2 用 relative font 跟随系统，未刻意下调；仅 9pt → caption2 (~10pt) 是 a11y 改进 |
| R2 | Brand orange 深色降饱和 15% 与浅色不协调 | 低 | Apple HIG 推荐范围内，如反馈不佳可微调至 10% |
| R3 | `Color.primary.opacity(0.04)` 某些显示器/系统配色偏暗 | 低 | 0.04 是肉眼几乎不可感的极淡值，必要时降至 0.03 |
| R4 | 全 app 改 ~19 文件，引入新隐性回归 | 低 | View 层无业务逻辑，单元测试不受影响；手动走查覆盖关键状态 |
| R5 | ArticleRow HStack 结构改动可能影响 List 行高（`listHeight: 52`） | 中 | dot padding 控制在 ±2pt 内；listHeight 算法需 verify，必要时调整常量 |
| **R6** | **Dynamic Type / macOS System Settings Text Size 切换** | 中 | v3：ArticleRow 字号已 fixed（已知放弃），其他 view（Digest/Recommend/Settings）relative font 仍响应 Dynamic Type。§6.2 验收走查 3 档（small / large / xx-large），ArticleListSection 区域接受不响应作为已知 trade-off |
| **R7** | **`.background(BrandColor.surfaceMuted)` 与 List `listRowBackground` 叠加视觉怪异**——踩坑 #1 已记录 List 在 MenuBarExtra 渲染问题 | 中 | §6.2 必走查 ArticleListSection 展开后浅/深两模式，`listRowBackground` 与外层 surfaceMuted 0.06 透明叠加是否产生视觉杂色（v3 已把 opacity 从 0.04 提到 0.06） |
| **R8** | **系统强调色（用户在 System Settings 改 accent）vs BrandColor 共存**——AddFeedSheet 系统按钮跟系统强调色，与菜单栏 BrandColor 橙并列可能突兀 | 中 | §6.2 加"切换系统强调色为非橙（如红/紫）"走查项 |
| **R9** | **SwiftUI Color 包装 NSColor.dynamicProvider 的初始采样问题**——SwiftUI Color 在创建时仅采样一次 NSColor，popover detached 重开时 dynamicProvider 不一定重新求值（第二轮 review P1-1 揭示） | 中 | **接受为已知风险**：菜单栏 popover 关开是 full view rebuild，初始采样问题实际不易触发。§6.2 加 2 个子项观测（保持打开 vs 关闭再开切 Appearance）。若实测频繁触发再考虑 `@Environment(\.colorScheme)` 主动 invalidate 重构 |
| **R10** | **sRGB vs P3 色空间显示器差异**——Wide Color 显示器（如 MBP / Studio Display）下原生 RGB 偏色 | 低 | §2.3 已显式声明 `srgbRed:green:blue:` 锁定 sRGB 色空间 |

### 5.2 回滚

- Token 文件可独立保留（不影响 build）
- 各 phase 独立 commit，回滚以 phase 为单位 `git revert`
- 如某 view 切换后视觉异常，可在该 view 内 inline 还原 SwiftUI 原生调用，不影响其他 view

---

## 6. 验收清单

### 6.1 编译与测试

- [ ] `swift build` 通过（0 warning / 0 error）
- [ ] `swift test` 通过：原 140 项 + 新增 DesignTokens 基础校验测试
- [ ] CLAUDE.md 更新

### 6.2 视觉走查（浅色 + 深色 × 多场景）

**基础 5 区域走查**：
- [ ] HeaderView：hero 13pt semibold（与文章标题同字号、加重）
- [ ] Banner（AI 不可用态）：背景 accentSoft 深色下可见、文案 + icon 用 BrandColor.accent
- [ ] DigestSectionView：expandedBody + placeholderBody 两分支字号/颜色对齐 token
- [ ] RecommendSectionView：header / pickRows / placeholderRows 三分支对齐 token
- [ ] ArticleListSection：foldedHeader（折叠态） / 展开后 articleList（含 loading/error/empty）三态
- [ ] FooterView："最后更新"标签从 9pt → caption2（视觉差异 ≤1pt）

**未读视觉**：
- [ ] 文章列表展开：未读项有 4pt orange dot，已读项无 dot 但占位保留对齐
- [ ] 推荐项：3pt 左色条贯穿（已读透明保留宽度），index 与色条同色
- [ ] 未读 dot 与推荐色条**同色**（BrandColor.accent）

**Settings 4 Tab**：
- [ ] 订阅源 Tab：feed 名/URL/检测状态行字号对齐
- [ ] API Tab：Key 输入/模型选择/检测按钮字号对齐
- [ ] **用量 Tab**：今日卡片 22pt rounded 大数字保留，Charts 字号不动
- [ ] 通用 Tab：开机启动 Toggle 字号对齐

**Dynamic Type / 可访问性走查（R6 验证）**：
- [ ] System Settings → Appearance → Text Size 切到 Large：DigestSectionView / RecommendItem / Settings 4 Tab 字号变化协调
- [ ] **ArticleListSection 文章行字号不变化**（已知 trade-off）
- [ ] 切到 Default：恢复正常
- [ ] 切到 Largest：版面溢出可控（不要求完美，但不能内容截断）

**Light/Dark 实时切换（R9 验证，2 个子项观测 SwiftUI Color 初始采样）**：
- [ ] **子项 A（关闭再开）**：菜单栏 popover 关闭 → System Settings 切 Appearance（Light/Dark） → 重新点击图标打开 popover → 所有 BrandColor.accent / accentSoft / surfaceMuted 跟随新模式（**预期通过**：full view rebuild）
- [ ] **子项 B（保持打开）**：菜单栏 popover 打开 → 在 popover 内可视范围内切 Appearance（如通过 Shortcuts / Touch Bar / Control Center） → 观察 popover 内 BrandColor 是否跟随。**已知风险**：可能不更新需关开 popover，若触发则在 CLAUDE.md 踩坑加 #32 + 后续单独迭代 `@Environment(\.colorScheme)` 重构

**系统强调色冲突（R8 验证）**：
- [ ] System Settings → Appearance → Highlight color 切到非橙色（如紫色）
- [ ] 菜单栏所有 BrandColor.accent 点保持橙色（独立于系统强调色）
- [ ] AddFeedSheet "保存"按钮跟随系统强调色（紫）——已知差异，记录不修

**List 兼容性（R7 验证）**：
- [ ] ArticleListSection 展开后，`articleList` 的 `listRowBackground` 与外层 `surfaceMuted` 在浅色无视觉杂色
- [ ] 深色同验
- [ ] "已读 (n)" 分隔行 separatorColor 与外层 surfaceMuted 叠加不糊

### 6.3 边界场景

- [ ] 文章数 = 0：empty state 字号/颜色对齐
- [ ] 文章数 = 1：dot + 标题不挤压
- [ ] 标题超长（lineLimit=2）：dot 仍与首行顶部对齐（不滑到中间）
- [ ] AI 摘要尚未生成：占位 placeholder 颜色 TextColor.tertiary
- [ ] 推荐 5 项满载 + 已读混合：色条贯穿无断裂（踩坑 #20 不复现）
- [ ] 跨日时刻：状态切换后所有 token 仍生效（drama 测试，必要时手动改系统时间）

---

## 7. 不交付项明确划界（防 scope creep）

为避免 scope creep，以下项目本轮**不交付**，留作后续独立优化：

1. **Spacing token**（padding/spacing 散点保留）—— 用户原话"排版尽量不变"
2. **IconSize.swift** —— icon 字号复用 Typography
3. **ProgressScale token** —— inline 收敛到 2 档（big 0.7 / small 0.55），不建 token
4. **AI banner 版面/逻辑** —— 仅改 BrandColor 使用，结构不动
5. **CheckStatus 验证图标的语义色** —— 绿/红保留，不能 brand 化
6. **设置页 TabView 样式** —— 跟系统 macOS Settings 默认
7. **SwiftUI Charts 字号** —— 跟系统 Charts 默认
8. **Asset Catalog** —— SPM 配置成本不值，BrandColor 用 NSColor dynamicProvider 已能避免桥接损失
9. **9pt micro 单独建档** —— 升到 caption2 (~10pt)，a11y 改进
10. **errorState/emptyState 的 `.largeTitle` icon** —— 错误大 icon 是 macOS 标准模式，作为非内容字号 exception 保留

### 7.1 显式防 scope creep 边界

- **`AddFeedSheet` 表单结构**完全不动——仅 Text 元素的 Typography/TextColor 替换，Form/Section/TextField/Toggle 布局保留
- **`RecommendItemView` 已读色条**保留为透明占位（`Color.clear` width=3）——**不引入** read indicator（dot/line/等），避免踩坑 #20 复发
- **`MenuBarView.body`** 与 `openArticle` 函数不动——仅修改 `aiUnavailableBanner` 内 Text/Image 元素
- **`HeaderView` 顶部"AI 资讯 [n/N]"括号格式**不动——只替换 font/color modifier
- **`FooterView` 时间格式 `.dateTime.hour().minute().second()`** 不动——只替换 font/color
- **`ArticleListSection.articleList` "已读 (n)" 分隔行 `listRowBackground`**（`Color(nsColor: .separatorColor).opacity(0.12)`）保留——macOS 原生系统色已自动适配明暗，不替换为 BrandColor；R7 走查仅验证视觉叠加无杂色
- **`UsageSettingsView` 内 SwiftUI Charts 字号/颜色/网格线**不动——保留 Charts framework 默认渲染，仅卡片头部/标签替换 Typography token
- **`SettingsView` TabView 容器 / Tab label / Tab icon**不动——保留 macOS 系统 Settings 原生样式
- **`ArticleRowView` HStack 改造**仅添加 leading dot + 移除背景色——不动 VStack 内部 spacing/lineLimit/onTapGesture/onHover 逻辑

### 7.2 §3.2 button style 跟随规则补充

| Button | 类别 | 文字色规则 |
|--------|------|----------|
| `FeedsSettingsView` "检测" / "检测全部" | `.buttonStyle(.plain)` | `BrandColor.accent`（跟品牌） |
| `APISettingsView` "检测可用性" | `.buttonStyle(.plain)` | `BrandColor.accent`（跟品牌） |
| `AddFeedSheet` "保存" / "取消" | 系统主样式（无 `.buttonStyle`） | 跟系统 accentColor（用户系统强调色） |
| `MenuBarView.aiUnavailableBanner` "去设置" | `.buttonStyle(.plain)` | `BrandColor.accent`（跟品牌） |
| `FooterView` "⚠ N 个源失败" / "设置" / "退出" | `.buttonStyle(.plain)` | 各自定义（见 §3.1） |

---

## 8. 关联文档与代码索引

| 项 | 位置 |
|---|------|
| 当前菜单栏架构记录 | `CLAUDE.md` |
| 历史踩坑记录 | `CLAUDE.md` §踩坑记录（#1 List 渲染、#20 RecommendItem 色条断裂） |
| Token 文件目标位置 | `Sources/AINewsBar/DesignTokens/` |
| MenuBar view 文件 | `Sources/AINewsBar/Views/MenuBar/`、`Views/MenuBarView.swift`、`Views/ArticleRowView.swift` |
| Settings view 文件 | `Sources/AINewsBar/Views/Settings/`、`Views/SettingsView.swift` |
| 第一轮 architect review 输出 | 见 git commit `61cd738` 提交后的会话历史 |

---

**作者**: Claude (via `/grill-me` 8 轮访谈 + architect review 2 轮)
**审阅**: 待用户最终确认 (v3 已完成 architect 两轮 review 迭代)
**版本**: v3 (2026-05-23)
