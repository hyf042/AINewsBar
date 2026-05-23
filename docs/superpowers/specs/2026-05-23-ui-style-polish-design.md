# UI 样式打磨设计文档

**日期**: 2026-05-23
**类型**: 视觉优化（typography / color token 化）
**范围**: 全 app（菜单栏 popover + 设置页）
**前置约束**: 排版（padding/spacing/layout）尽量不变

---

## 1. 背景与目标

### 1.1 现状问题

AINewsBar 经过多轮重构后，业务架构已稳定，但 UI 视觉层存在以下散点问题：

1. **字号杂乱**：代码中并存 9 个不同字号 —— `9 / 10 / 11 / 12 / 13pt` 加 `.caption2 / .caption / .footnote / .headline`，缺乏统一的字号语义层级。
2. **背景偏重**：`Digest / Recommend / ArticleList 折叠 header` 三个区域全部使用 `.background(.quaternary)`，在浅色模式下三块灰背景叠加让整个面板观感"灰扑扑"。
3. **强调色不统一**：推荐区使用 `Color.orange` 作为 brand，但未读文章行底色却用 `Color.accentColor.opacity(0.05)`（系统默认蓝），同一面板存在两种"强调色"语义。
4. **同语义字段层级混乱**：ArticleRow 的 feedTitle/publishedAt 用 `.secondary`，RecommendItem 的相同字段用 `.tertiary` —— 同样的"辅助信息"角色却用了不同层级。

### 1.2 目标调性

**macOS 原生精致化** —— 保留系统视觉语言（不引入毛玻璃材质等激进改造），通过建立 token 化的 typography 与 color 体系，让全 app 视觉一致、灰度更柔和、品牌锚点更统一。

### 1.3 范围边界

| 改 | 不改 |
|---|---|
| 字号体系（建 Typography token） | padding / spacing 散点 |
| 文字层级（建 TextColor token） | 区域顺序、组件布局 |
| 强调色（建 BrandColor token） | 业务逻辑、Service 层 |
| 背景色（`.quaternary` → `surfaceMuted`） | 单元测试（140 项不动） |
| 未读视觉（文章行加 dot + 去背色） | AI banner 版面/逻辑、CheckStatus 语义色 |
| Icon 字号（顺着 Typography token） | Spacing token、IconSize token、ProgressScale token |

---

## 2. Token 设计

### 2.1 Typography（5 档）

新建 `Sources/AINewsBar/DesignTokens/Typography.swift`：

| Token | 字号 / weight | 用途 |
|-------|-------------|------|
| `Typography.headline` | 17pt semibold | `HeaderView` 顶部"AI 资讯 [n/N]" |
| `Typography.title` | 13pt semibold | 区域标题（Digest/Recommend/ArticleList header）、文章列表项标题 |
| `Typography.body` | 12pt regular | 摘要正文、推荐项标题、推荐项摘要、digest 正文 |
| `Typography.caption` | 11pt regular | feed 名、相对时间、辅助状态文案 |
| `Typography.micro` | 9pt regular | "最后更新"标签等极端辅助文案 |

**实现**：

```swift
import SwiftUI

enum Typography {
    static let headline = Font.system(size: 17, weight: .semibold)
    static let title    = Font.system(size: 13, weight: .semibold)
    static let body     = Font.system(size: 12, weight: .regular)
    static let bodyEmphasized = Font.system(size: 12, weight: .semibold)  // 文章/推荐标题未读态
    static let caption  = Font.system(size: 11, weight: .regular)
    static let micro    = Font.system(size: 9, weight: .regular)
}
```

**Icon 复用约定**：SF Symbol 复用 Typography token 的字号，不新建 IconSize：

```swift
Image(systemName: "brain").font(Typography.title)         // 区域标题 icon
Image(systemName: "arrow.clockwise").font(Typography.micro) // 微型按钮 icon
Image(systemName: "star.fill").font(Typography.title)     // 推荐区 star
```

### 2.2 TextColor（4 档）

新建 `Sources/AINewsBar/DesignTokens/TextColor.swift`：

| Token | 映射 | 用途 |
|-------|------|------|
| `TextColor.primary` | `Color.primary` | 顶部 hero、未读文章标题、摘要正文 |
| `TextColor.secondary` | `Color.secondary` | 区域标题、已读文章标题、推荐摘要文案 |
| `TextColor.tertiary` | `Color.tertiary` | feed 名、相对时间、chevron、辅助状态 |
| `TextColor.accent` | `BrandColor.accent` | 推荐 index、未读 dot、AI banner 文案/icon |

**实现**：

```swift
import SwiftUI

enum TextColor {
    static let primary   = Color.primary
    static let secondary = Color.secondary
    static let tertiary  = Color.tertiary
    static let accent    = BrandColor.accent
}
```

**一致性修复**：`ArticleRow.feedTitle` 与 `ArticleRow.publishedAt` 由 `.secondary` 下调为 `TextColor.tertiary`，与 `RecommendItem` 同字段保持一致。

### 2.3 BrandColor

新建 `Sources/AINewsBar/DesignTokens/BrandColor.swift`：

```swift
import SwiftUI

enum BrandColor {
    /// 全局品牌橙。明暗模式双值，深色降饱和 15% 防刺眼。
    static let accent = Color(
        light: Color.orange,
        dark:  Color(red: 1.0, green: 0.62, blue: 0.32)
    )

    /// 高亮背景（AI banner / 未读高亮背景使用）。
    static let accentSoft = Color.orange.opacity(0.08)

    /// 区域柔和背景。明暗自动反色（light 黑 4% / dark 白 4%）。
    static let surfaceMuted = Color.primary.opacity(0.04)
}

// Color light/dark 双值便捷构造
extension Color {
    init(light: Color, dark: Color) {
        self = Color(NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        }))
    }
}
```

---

## 3. 视觉变更点详细清单

### 3.1 MenuBar 区（8 个 view）

#### `HeaderView`
- "AI 资讯 [n/N]" 标题：`.headline` → `Typography.headline`（17pt 保留）
- "AI 摘要中" 文案：`.caption2` → `Typography.caption` + `TextColor.tertiary`
- 刷新按钮 icon `.system(size:12)` → `Typography.body`
- ProgressView scaleEffect 0.6/0.7 对齐到 2 档（big 0.7 / inline 0.6）

#### `FooterView`
- "最后更新" 标签 `.system(size:9)` → `Typography.micro` + `TextColor.tertiary`
- 时间值 `.caption2` → `Typography.caption` + `TextColor.secondary`
- "今日 X tokens" `.caption2` → `Typography.caption` + `TextColor.tertiary`
- "⚠ N 个源失败" 按钮：foregroundStyle `.orange` → `BrandColor.accent`
- "设置" / "退出" 按钮 `.caption` → `Typography.caption` + `TextColor.secondary`
- "未刷新" 状态 `.caption2` → `Typography.caption` + `TextColor.tertiary`

#### `DigestSectionView`
- "今日 AI 资讯摘要" 标题：`.footnote.weight(.medium)` → `Typography.title` + `TextColor.secondary`
- brain icon `.footnote` → `Typography.title`
- 时间 `.system(size:10)` → `Typography.caption` + `TextColor.tertiary`
- 重新生成 icon `.system(size:10)` → `Typography.micro` + `TextColor.tertiary`
- chevron `.system(size:9)` → `Typography.micro` + `TextColor.tertiary`
- 正文 `.system(size:12)` → `Typography.body` + `TextColor.primary`
- "生成中…" `.caption2` → `Typography.caption` + `TextColor.tertiary`
- 占位"今日 AI 资讯摘要"文字色：`.tertiary` → `TextColor.tertiary`
- **背景**：`.background(.quaternary)` → `.background(BrandColor.surfaceMuted)`

#### `RecommendSectionView`
- "AI 今日推荐" 标题：`.footnote.weight(.medium)` → `Typography.title` + `TextColor.secondary`
- star icon `.footnote` → `Typography.title`
  - loading: `TextColor.tertiary`（保持）
  - loaded: `BrandColor.accent`
- 时间 `.system(size:10)` → `Typography.caption` + `TextColor.tertiary`
- 刷新 icon `.system(size:10)` → `Typography.micro` + `TextColor.tertiary`
- "生成中…" `.caption2` → `Typography.caption` + `TextColor.tertiary`
- placeholder index `.system(size:11, weight:.bold)` → `Typography.caption.weight(.bold)` + `TextColor.tertiary`
- **背景**：`.background(.quaternary)` → `.background(BrandColor.surfaceMuted)`

#### `RecommendItemView`
- 左色条 `Color.orange` → `BrandColor.accent`（语义不变，颜色 token 化）
- index 数字 `.system(size:11, weight: .bold/.regular)` → `Typography.caption.weight(.bold/.regular)`
  - 未读色：`Color.orange` → `BrandColor.accent`
  - 已读色：`.tertiary` → `TextColor.tertiary`
- feed 名/时间 `.caption2` + `.tertiary` → `Typography.caption` + `TextColor.tertiary`
- 标题 `.system(size:12, weight: .semibold/.regular)` → `Typography.bodyEmphasized/body`
  - 未读色：`.primary` → `TextColor.primary`
  - 已读色：`.secondary` → `TextColor.secondary`
- 摘要 `.caption2` + `.secondary` → `Typography.caption` + `TextColor.secondary`

#### `ArticleListSection`
- 折叠 header 整体：`.background(.quaternary)` → `.background(BrandColor.surfaceMuted)`
- list.bullet icon `.footnote` → `Typography.title`
- "今日文章" 标题：`.footnote.weight(.medium)` → `Typography.title` + `TextColor.secondary`
- subtitle "· N 未读" `.caption` → `Typography.caption` + `TextColor.tertiary`
- chevron `.system(size:9)` → `Typography.micro` + `TextColor.tertiary`
- "已读 (n)" 分隔行 `.caption` → `Typography.caption` + `TextColor.tertiary`
- empty/error/loading 状态文案 `.caption / .caption2` → `Typography.caption` + `TextColor.secondary/tertiary`

#### `ArticleRowView`
- feedTitle `.caption2` + `.secondary` → `Typography.caption` + `TextColor.tertiary` **（一致性修复）**
- 时间 `.caption2` + `.secondary` → `Typography.caption` + `TextColor.tertiary` **（一致性修复）**
- 标题 `.system(size:13, weight: .semibold/.regular)` → `Typography.title / Font.system(size:13, weight:.regular)`
  - 未读色：`.primary` → `TextColor.primary`
  - 已读色：`.secondary` → `TextColor.secondary`
- 摘要 `.caption` + `.secondary` → `Typography.caption` + `TextColor.secondary`
- **去掉行底色**：`.background(article.isRead ? Color.clear : Color.accentColor.opacity(0.05))` 删除
- **新增 leading dot**：HStack 起首 `Circle().fill(article.isRead ? .clear : BrandColor.accent).frame(width:4, height:4).padding(.top, 5)`
- HStack 主结构由 `VStack` 改为 `HStack(alignment: .top, spacing: 8) { dot; VStack(原内容) }`

#### `MenuBarView`
- aiUnavailableBanner：
  - exclamationmark icon `.system(size:11)` → `Typography.caption`，foregroundStyle `.orange` → `BrandColor.accent`
  - 文案 `.caption` → `Typography.caption` + `TextColor.tertiary`
  - "去设置" 按钮 `.caption` → `Typography.caption`，foregroundStyle `Color.accentColor` → `BrandColor.accent`
  - 背景 `Color.orange.opacity(0.08)` → `BrandColor.accentSoft`

### 3.2 Settings 区（8 个 view）

#### `SettingsView`
- TabView label 字号跟系统 macOS Settings 默认（不动）

#### `UsageSettingsView`
- 今日卡片标题、数值、单位文案统一对齐 Typography（title/body/caption）
- Charts 字号跟随 SwiftUI Charts 默认

#### `FeedsSettingsView` / `FeedRowView` / `BuiltInFeedRowView`
- feed 名 / URL / "检测中..." 状态文案统一 Typography.body/caption
- "检测" / "检测全部" 按钮：保留系统按钮样式，文案颜色 `Color.accentColor` → `BrandColor.accent`
- CheckStatus icon 颜色：**保留绿/红语义色**（不 brand 化）

#### `AddFeedSheet`
- 表单 label / placeholder / 错误提示文案对齐 Typography
- "保存" 主按钮使用系统强调色（系统会自动跟 BrandColor accent，但保留系统按钮样式）

#### `APISettingsView`
- API Key 输入框 label / hint 文案对齐 Typography
- 模型选择 Picker 跟系统默认
- "检测可用性" 按钮文案颜色对齐 `BrandColor.accent`
- 检测状态行内 CheckStatus icon 语义色保留

#### `GeneralSettingsView`
- 开机启动 Toggle 文案对齐 Typography.body

#### `CheckStatus.swift` / `CheckStatusIcon`
- icon 字号：`.footnote` / `.system(size:N)` → `Typography.caption`（统一）
- 绿/红/灰语义色保留

---

## 4. 实施分阶段

### Phase 1 — Token 文件落地（~1 单元）
1. 新增 `Sources/AINewsBar/DesignTokens/` 目录
2. 写 `Typography.swift` / `TextColor.swift` / `BrandColor.swift` 三个文件
3. `swift build` 确认编译通过
4. 提交单独 commit：`feat(tokens): 引入 Typography/TextColor/BrandColor 三套 token`

### Phase 2 — MenuBar popover 切换（~1 单元）
1. 按 §3.1 清单逐 view 替换字号 / 颜色调用
2. ArticleRow 加 dot + 去背色 + HStack 重构
3. `swift build` + 手动验证（浅/深两模式打开菜单走查）
4. 提交 commit：`refactor(ui): MenuBar popover 全量切换至 token 体系 + 文章行未读视觉升级`

### Phase 3 — Settings 同步（~0.5 单元）
1. 按 §3.2 清单逐 view 替换
2. 4 个 Tab 全部走查（浅/深）
3. 提交 commit：`refactor(ui): Settings 4 Tab 同步至 token 体系`

### Phase 4 — 收尾验证（~0.5 单元）
1. 删除散落的 magic number（grep 检查 `.system(size:` / `.caption2` 等遗漏点）
2. CLAUDE.md 增量更新（新增 DesignTokens 目录说明 + 设计决策 token 化条目）
3. `swift test` 跑全 140 测试确认无回归
4. 启动验证 + push

---

## 5. 风险与回滚

### 5.1 风险

| 风险 | 等级 | 缓解 |
|------|-----|------|
| 字号集中下调让用户主观觉得"字变小了" | 中 | 字号 token 推荐值与原代码主流字号相同（13/12/11pt），仅消除散点；用户主体阅读字号体验不变 |
| Brand orange 深色降饱和后与浅色不协调 | 低 | 深色降饱和 15% 是 Apple HIG 推荐范围内；如反馈不佳可微调至 10% |
| `Color.primary.opacity(0.04)` 在某些显示器/系统配色下偏暗 | 低 | 0.04 是肉眼几乎不可感的极淡值；如不够柔和可下调至 0.03 或对深色单独设置 |
| 全 app 改 ~19 文件，引入新隐性回归 | 低 | View 层无业务逻辑，单元测试不受影响；手动走查覆盖关键状态（未读/已读/loading/error/empty/banner） |
| ArticleRow HStack 结构改动可能影响 List 行高 | 中 | dot padding 控制在与原行高 ±2pt 内；listHeight 算法（`rowHeight: 52`）需 verify |

### 5.2 回滚

- Token 文件可独立保留（不影响 build）
- 各 phase 独立 commit，回滚以 phase 为单位 `git revert`
- 如某 view 切换后视觉异常，可在该 view 内 inline 还原 SwiftUI 原生调用，不影响其他 view

---

## 6. 验收清单

### 6.1 编译与测试
- [ ] `swift build` 通过（0 warning / 0 error）
- [ ] `swift test` 通过（140/140）
- [ ] CLAUDE.md 更新

### 6.2 视觉走查（浅色 + 深色 × 全场景）
- [ ] 菜单栏面板首次打开：5 区域（Header / Banner / Digest / Recommend / ArticleList / Footer）字号/颜色/背景符合 token
- [ ] 文章列表展开：未读项有 4pt orange dot，已读项无 dot 但占位保留对齐
- [ ] 推荐项：3pt 左色条贯穿，index 与色条同色（BrandColor.accent）
- [ ] AI 不可用状态：banner 背景 accentSoft，"去设置"按钮 BrandColor.accent
- [ ] Feed 源失败：Footer "⚠ N 个源失败" 按钮 BrandColor.accent
- [ ] Settings 4 Tab：字号/层级与菜单栏一致
- [ ] FeedsSettings 检测中/通过/失败三态：icon 颜色保留绿/红/灰语义
- [ ] Loading 状态：ProgressView 大小分两档（header big / inline small）
- [ ] 跨日时刻：状态切换后所有 token 仍生效

### 6.3 边界场景
- [ ] 文章数 = 0：empty state 字号/颜色对齐
- [ ] 文章数 = 1：dot + 标题不挤压
- [ ] 标题超长（lineLimit=2）：dot 仍与首行顶部对齐
- [ ] AI 摘要尚未生成：占位 placeholder 颜色 TextColor.tertiary
- [ ] 推荐 5 项满载 + 已读混合：色条贯穿无断裂（踩坑 #20 不复现）

---

## 7. 不交付项明确划界

为避免 scope creep，以下项目本轮**不交付**，留作后续独立优化：

1. **Spacing token**（padding/spacing 散点保留）—— 用户原话"排版尽量不变"
2. **IconSize.swift** —— icon 字号复用 Typography
3. **ProgressScale token** —— 顺手对齐到 2 档值即可
4. **AI banner 版面/逻辑** —— 仅改 BrandColor 使用，结构不动
5. **CheckStatus 验证图标语义色** —— 绿/红保留，不能 brand 化
6. **设置页 TabView 样式** —— 跟系统 macOS Settings 默认
7. **SwiftUI Charts 字号** —— 跟系统 Charts 默认

---

## 8. 关联文档与代码索引

| 项 | 位置 |
|---|------|
| 当前菜单栏架构记录 | `CLAUDE.md` |
| 历史踩坑记录 | `CLAUDE.md` §踩坑记录 |
| Token 文件目标位置 | `Sources/AINewsBar/DesignTokens/` |
| MenuBar view 文件 | `Sources/AINewsBar/Views/MenuBar/`、`Views/MenuBarView.swift`、`Views/ArticleRowView.swift` |
| Settings view 文件 | `Sources/AINewsBar/Views/Settings/`、`Views/SettingsView.swift` |

---

**作者**: Claude (via `/grill-me` 8 轮访谈)
**审阅**: 待 spec-document-reviewer 与用户确认
