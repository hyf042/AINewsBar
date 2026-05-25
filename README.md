# 资讯助手（原 AINewsBar）

macOS 菜单栏多分类资讯阅读器。3 个 tab（**AI / 财报 / 新闻**），27 个内置精选 RSS 源，通过阿里云百炼（默认 qwen3.6-plus）生成中文摘要 + AI 推荐 + 每日概述；财报 tab 启用 AI Filter 过滤非财报噪声。

> v2 起从单一 AI 资讯（v1 `AINewsBar`）扩展为多分类（CFBundleDisplayName 改为「资讯助手」，binary 仍 `AINewsBar` 保持向后兼容）。

## 功能

### 核心
- **3 tab 多分类** — AI / 财报 / 新闻，顶部 segmented 切换；`⌘1 / ⌘2 / ⌘3` 快捷键；selectedTab 持久化
- **per-tab 独立状态** — 每 tab 各自的摘要 / 推荐 / 文章列表 / 未读 badge / 自动刷新开关
- **菜单栏图标 unread badge** — 三 tab 累加未读数（仅算 filter 通过的）

### RSS 抓取
- **27 个内置精选源**（11 AI + 8 财报 + 8 新闻；中英混合）
- **自定义 RSS** — 添加时选 cat + 自动验证可用性；可单独开关
- **per-tab 后台刷新** — 1 小时 timer 顺序遍历 3 cat 避免 QPS 峰值；user 可通用 Tab 关掉某 cat 省 token

### AI 处理（cat-specific prompt）
- **AI 单篇摘要** — 后台 5 并发为每篇文章生成一句话中文简介（无论原文语言）；prompt 按 cat 差异化（AI 从业者 / 投资者 / 关心时事的读者）
- **今日摘要** — 基于标题+摘要生成 2-3 句概述；每 3 小时有新文章时重新生成；支持手动刷新；跨重启持久化
- **AI 推荐 5 篇** — 基于标题+摘要综合判断挑选；有新文章或列表为空时调用 API；显示最后更新时间
- **智能增量** — 新增摘要 ≥3 篇时自动触发推荐/日报重新生成（Plan A），避免 API 浪费

### AI Filter Stage（v2 新增，财报 cat 启用）
- **入库后标 accepted**（true/false/nil）：仅 accepted=true 进 UI 与 Recommend/Digest pipeline
- **失败 3 次永久 reject** — 避免黑名单文章反复重试烧 token
- **per-feed `skipFilter` toggle** — 标记"纯净源"（如 Apple Newsroom 100% 公司动态）跳过 filter

### UI
- **已读/未读分层** — 已读文章显示在列表底部（"已读 (n)" 分隔行），标题色降低；Header 显示 [未读/总数]
- **文章列表自适应** — 默认折叠；展开后高度 min 120 / max 400px（防止新闻 84 篇等大量文章溢出屏幕）
- **状态提示** — 摘要不足 N 篇时 placeholder 显示"需 ≥N 篇 (当前 M)"；候选不足 5 篇时同理
- **AI 不可用 banner** — global error（API Key 错）顶部 sticky / per-cat 业务错在 tab 内
- **跨日重置** — 跨过零点自动清三 cat 的 @Published 状态、SwiftData 旧文章、prefs

### Token 用量
- **每次 AI 调用入库 UsageRecord**（scene: summary / recommend / digest / **filter**）+ category
- **Footer 显示三 cat 累加** 今日 token
- **Settings 用量 Tab** — 顶部 cat Picker（全部/AI/财报/新闻）+ 今日卡片 + 7/30 天 SwiftUI Charts 堆叠柱图（4 色 scene）

## 技术栈

| 模块 | 技术 |
|------|------|
| UI | Swift + SwiftUI（MenuBarExtra `.window` style）|
| 数据持久化 | SwiftData（schema v2-multi-category）|
| RSS 解析 | FeedKit |
| AI 服务 | 阿里云百炼 DashScope，默认模型 qwen3.6-plus；支持千问/智谱/Kimi/MiniMax 共 9 个预设 + 自定义 |
| 密钥存储 | UserDefaults（个人工具 + ad-hoc 签名 trade-off）|
| 测试 | XCTest + Swift Testing（共 186 测试）|

**最低系统要求：macOS 14 Sonoma**

## 项目结构

```
Sources/AINewsBar/
├── App/
│   ├── AINewsBarApp.swift       # @main，注入 ModelContainer + RefreshService
│   └── AppDelegate.swift        # 启动期入口；Migration 全清；NSWorkspace 唤醒监听
├── Models/
│   ├── Category.swift           # v2: 3 cat enum (.ai / .earnings / .news)
│   ├── CategoryConfig.swift     # v2: per-cat 配置（filterPrompt / recommendCount）
│   ├── Feed.swift               # +category +skipFilter
│   ├── Article.swift            # +category +accepted: Bool? +filterFailCount
│   └── UsageRecord.swift        # +category；UsageScene +.filter
├── Services/
│   ├── BuiltInFeeds.swift       # 27 内置源（11 AI + 8 财报 + 8 新闻）含 cat
│   ├── RSSService.swift         # FeedKit 封装 actor
│   ├── BailianService.swift     # DashScope 调用；4 prompt 工厂 per-cat + classifyArticle
│   ├── PreferencesService.swift # UserDefaults per-cat key 拼接
│   ├── ServiceProtocols.swift   # 协议双轨（per-cat 新签名 + extension fallback .ai）
│   ├── RefreshDecision.swift    # 触发决策纯函数集
│   ├── RefreshService.swift     # 编排者；states dict + per-cat inflight + 顺序 timer
│   ├── SummaryPipeline.swift    # 5 并发摘要 pipeline
│   ├── FilterPipeline.swift     # v2: 5 并发 filter pipeline
│   ├── RecommendEngine.swift    # AI 推荐生成引擎
│   ├── DigestEngine.swift       # 今日日报生成引擎
│   ├── ArticleSnapshot.swift    # Sendable 文章快照（per-cat capture）
│   ├── UsageRecorder.swift      # UsageRecord SwiftData 写入
│   ├── UsageRecording.swift     # 协议
│   └── UsageAggregator.swift    # todayStats / dailyByScene（cat filter 可选）
├── Views/
│   ├── MenuBarView.swift                  # 顶层：CategoryTabBar 切换 + cat-aware 子视图
│   ├── ArticleRowView.swift               # 文章行（onTapGesture）
│   ├── SettingsView.swift                 # 4 Tab 容器
│   ├── MenuBar/
│   │   ├── CategoryTabBar.swift           # v2: 自定义 segmented 替代 macOS Picker.segmented
│   │   ├── HeaderView.swift / FooterView.swift / DigestSectionView.swift /
│   │   ├── RecommendSectionView.swift / RecommendItemView.swift / ArticleListSection.swift
│   └── Settings/
│       ├── FeedsSettingsView.swift        # 顶部 cat Picker + 范围内"检测全部"
│       ├── FeedRowView.swift / AddFeedSheet.swift /
│       ├── APISettingsView.swift / UsageSettingsView.swift / GeneralSettingsView.swift
└── DesignTokens/
    ├── Typography.swift / TextColor.swift / BrandColor.swift
```

## 安装（直接使用预构建包）

1. 下载最新 `AINewsBar-x.y.z.zip`，解压得到 `AINewsBar.app`（Bundle 内部显示名为「资讯助手」）
2. 将 `AINewsBar.app` 拖入 `/Applications`
3. 首次打开时 macOS Gatekeeper 会提示"无法验证开发者"（ad-hoc 签名，非 App Store 分发）

**解决方法（二选一）：**
- **右键打开**：在 Finder 中右键 `AINewsBar.app` → 打开 → 仍要打开
- **命令行解除隔离**：
  ```bash
  xattr -cr /Applications/AINewsBar.app
  open /Applications/AINewsBar.app
  ```

## 从源码构建

**要求：** macOS 14+，Xcode Command Line Tools（`xcode-select --install`）

```bash
git clone <repo-url>
cd AINewsBar
./scripts/build.sh
```

脚本自动完成：停止已运行实例 → release 构建 → 签名 → 打包为 `build/AINewsBar-x.y.z.zip`。

构建后启动：
```bash
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

> **注意：** 不要用 `open build/AINewsBar.app`（某些状态下静默失败）；不要直接运行裸二进制（MenuBarExtra 依赖 bundle 上下文）。

## 运行测试

```bash
swift test
```

**测试覆盖（186 case）**：
- `PreferencesServiceTests` / `PreferencesServiceCategoryTests` — UserDefaults 隔离实例，per-cat key 隔离
- `BailianServiceTests` / `BailianServiceFilterTests` — 推荐序号解析、3 套 prompt 构造、filter 响应解析容错、per-cat prompt 文案差异
- `RefreshDecisionTests` — 推荐/日报触发条件矩阵 + 时间窗口判断
- `RefreshServiceTests` / `RefreshServicePerCategoryTests` — Mock RSS/AI + 内存 ModelContainer，刷新主流程、跨批次去重、AI 错误、强制刷新、per-cat 隔离
- `FilterPipelineTests` — 5 并发 / accepted / rejected / failure / cancellation / usage 透传
- `CategoryConfigTests` — 3 cat 配置完整性、filter prompt 仅财报、Category.from 安全 fallback
- `ModelsTests` / `BuiltInFeedsTests` — 模型默认值、27 内置源 cat 分布
- `RelativeDateFormatTests` / `MarkdownStripperTests` / `DesignTokensTests` 等

## 配置 API Key

启动后点击菜单栏图标 → **设置（`⌘,`）** → **API** Tab → 填入阿里云百炼 API Key → 选择模型 → **保存**（保存时自动检测可用性）。

- Key 存储在 UserDefaults（`com.ainewsbar.claude-api-key`）
- 支持 9 个预设模型（千问 / 智谱 / Kimi / MiniMax）或自定义模型名称
- 如需验证 RSS 源，进入 **订阅源** Tab → 切到对应 cat → 行内"检测"或"检测全部"

## 键盘快捷键

| 快捷键 | 作用 |
|--------|------|
| `⌘1` / `⌘2` / `⌘3` | 切到 AI / 财报 / 新闻 tab |
| `⌘R` | 刷新当前 tab |
| `⌘,` | 打开设置窗口 |
| `⌘Q` | 退出应用 |

## 内置订阅源（27 个）

### AI tab（11）
OpenAI News · Google DeepMind · Hugging Face Blog · TechCrunch AI · The Verge AI · Ars Technica AI · The Decoder · MIT Technology Review · VentureBeat AI · TLDR AI · 量子位

### 财报 tab（8，6 en + 2 zh）
Seeking Alpha · Apple Newsroom · CNBC Top News · Bloomberg Markets · Yahoo Finance · MarketWatch · FT 中文财经 · 雪球热门

### 新闻 tab（8，4 en + 4 zh）
BBC News · NYT World · Hacker News Top · The Verge · 36 氪 · 新华网 · 人民日报 · FT 中文新闻

> **中文财报 RSS 稀缺**为已知 limitation：华尔街见闻 / 第一财经 / 东方财富 / 财新 等官方 RSS 全部 404 或返 HTML（v2 重构时 curl 验证过）；新浪财经返自定义 XML 非标准 RSS。仅 FT 中文 + 雪球 2 个标准 RSS 可用，故财报 tab 妥协为 6 en + 2 zh。用户可自加自定义中文源补足（如自部署 RSSHub 实例）。

## 设计文档

- `CLAUDE.md` — 完整工作记录与设计决策表（含 37 条踩坑记录）
- `docs/plans/multi-category-redesign.md` — v2 重构 spec（16 题 grill 决策 + 6 phase 拆分）
- `docs/plans/optimization-plan.md` — v1 阶段 4 项重构记录
