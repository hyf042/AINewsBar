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
- **per-tab 后台刷新** — 1 小时 timer 顺序刷三 cat（峰值 5 路；可靠性优先，避免依赖 provider QPS 不变量）；user 可通用 Tab 关掉某 cat 省 token；手动单 cat 刷新仍保持 cat 内 5 并发

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
| 测试 | XCTest + Swift Testing（共 214 测试：205 XCTest + 9 Swift Testing）|

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
│   ├── ServiceProtocols.swift   # per-cat 显式协议（无 fallback）
│   ├── RefreshDecision.swift    # 触发决策纯函数集
│   ├── RefreshService.swift     # 编排者；states (private set) + per-cat inflight + 顺序 timer + markAvailability + startupError
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

**测试覆盖（214 case = 205 XCTest + 9 Swift Testing）**：
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

### 财报 tab（8，4 en + 4 zh）
Seeking Alpha · Apple Newsroom · CNBC Top News · Yahoo Finance · 财联社 头条 · 华尔街见闻 全球 · FT 中文财经 · 雪球热门

### 新闻 tab（8，4 en + 4 zh）
BBC News · NYT World · Hacker News Top · The Verge · 36 氪 · 新华网 · 人民日报 · FT 中文新闻

> **中文财报 RSS 镜像依赖**：华尔街见闻 / 第一财经 / 东方财富 / 财新 等官方 RSS 全部 404 或返 HTML（v2 时 curl 验证过）。2026-05-25 通过公共 RSSHub 镜像 `rsshub.rssforever.com` 引入 **财联社 头条** + **华尔街见闻 全球** 两个高质量中文财经源（条目数 ≥30、含完整摘要），换出英文里重叠度最高的 Bloomberg Markets + MarketWatch。备用镜像 `rss.injahow.cn` 同路径可用，公共 RSSHub 实例随时可能被反爬升级或下线 — known risk。用户可在设置里手动改 URL（如自部署 RSSHub 实例彻底自主）。

## 工程质量加固（2026-05-25 review）

v2 多分类落地后做了一轮 Linus 风格系统 review，识别并修复 16 项问题（commit `3d57710` + `a11a8f5`）：

| 等级 | 项 | 修复 |
|---|---|---|
| 🔴 C1 | 跨日重置 dead code | 11 行 if/else 简化为 `lastResetCheckDate != nil` |
| 🟠 H1 | `.ai` shortcut 蔓延 | 删 12 个 computed properties，states 改 `private(set)`，公开 `markAvailability(_:for:)` + DEBUG `_testMutate` |
| 🟠 H2 | 内存回滚舞蹈 | `commitSummaries` 改用 SwiftData 自带 `context.rollback()` |
| 🟠 H3 | runRefresh 漏写 fetchError | defer + captured value 保证一定写入 |
| 🟠 H4 | 401/403 一锅炖 | 拆出 `.forbidden` 枚举值，UI 文案区分"key 无效 vs 模型未授权" |
| 🟠 H5 | 三 cat 串行刷新 | 改 `withTaskGroup` 并发，冷启动 1-2 分钟降到 ~30 秒 |
| 🟠 H6 | states setter internal | 改 `private(set)` + DEBUG-only 测试 hook |
| 🟡 M1 | filter 失败状态机散三处 | 收敛到 `Article.recordFilterFailure(maxBeforeReject:)` |
| 🟡 M2 | syncInto 删→改顺序坑 | 先改 `feed.category` 再删 articles |
| 🟡 M3 | currentCredentials 名实不符 | CQS 拆 `currentCredentials()` (query) + `ensureCredentials(cat:)` (command) |
| 🟡 M4 | mutate 递归隐患 | 加注释禁止递归调用 |
| 🟡 M5 | Schema migration `try?` 静默 | 改 do/catch + 区分 `fileNoSuchFile` + Log |
| 🟢 L1 | prompt 函数 `.ai` 默认值 | 删除 default，测试显式传 |
| 🟢 L2 | `Article.accepted = true` 默认 | 改 `nil`，让"通过"成为显式行为 |
| 🟢 L3 | `Category.from` 静默 fallback | 非 nil 解析失败时 Log |

**意外发现的副带 bug**：APISettingsView 的 `testConnection` 成功只 set `.ai` 一个 cat 的 availability，财报/新闻 cat 留 `.unknown`（multi-category 升级遗漏），已修。

净影响：相关文件累计 +233 / -178 = 净 **+55 行**（删 .ai shortcut 瘦身 vs 加防御性 do/catch + extension + 注释，方向互补）。

### 持续可靠性强化（commit `b7a917f`）

review 后又补一轮 6 项设置持久化与外部边界硬化：

| 项 | 修复 |
|---|---|
| 刷新主路径 enabled feeds 查询 | 改 strict fetch，查询失败不假装刷新成功 |
| 内置源开关 / 自定义源删除 | 抽出 `FeedSettingsStore`：strict 删 articles + 失败 rollback；UI 弹 alert 恢复 toggle |
| 开机启动 toggle | 注册失败恢复旧状态 + alert，避免 UI 与系统状态分裂 |
| 打开文章 | `NSWorkspace.open` 失败不标已读；已读 save 失败 rollback，未读计数不撒谎 |
| Atom 解析 | 优先 `rel=alternate + text/html` 链接，再 fallback；防止 `rel=self` 被误当文章 URL（踩坑 #38）|

测试 +4 (208 → 212)：FeedSettingsStoreTests + Atom alternate link 测试。

### 第二轮 review 收尾（commit `bb866b0` + `bbb9234`，8 项）

| 等级 | 项 | 修复 |
|---|---|---|
| 🟠 P2 | cleanupOldArticles 失败不 rollback | 改 throw 版 + runRefresh do/catch 失败 rollback + lastError + return |
| 🟠 P2 | 跨日 cleanup 仍 tolerant | 全 cat 版同改 throw；reset 失败不推进 lastResetCheckDate，下次入口重试 |
| 🟠 P2 | FeedRowView toggle guard 时序 | catch 先 arm guard 再 rollback；末尾 Task 兜底 reset 防卡死 |
| 🟠 P2 | configure 立即 scheduleTimer | timer 拆到 launchBackgroundRefreshIfNeeded 内部；sync 失败 timer 不启动 |
| 🟡 P3 | APISettingsView 不设 globalAIError | catch 调 `GlobalAIError.from(error)`，菜单 UI 立即可见 |
| 🟡 P3 | UsageRecording 契约自相矛盾 | helper `record(info:success:)` success=false 时强制 input/output=0，协议文档明确 |
| 🟡 P3 | summary commit 漏走 helper | 改走 `record(info:success:)`，统一契约 |
| 🟡 P3 | AppDelegate 忽略 syncInto 返回 | 失败 set globalAIError + skip launchBackgroundRefreshIfNeeded |

测试 +2 (212 → 214)：`testRecordHelperZerosTokensOnFailure` + `testRecordHelperPreservesTokensOnSuccess`。

### 第四轮 review（4 项 P2/P3）

| 等级 | 项 | 修复 |
|---|---|---|
| 🟠 P2 | auto path 并发 = QPS 不变量 | `refreshAllCatsConcurrently` → `refreshAllCatsSequentially`：timer/wake/launch 三入口顺序 await；峰值 QPS 15 → 5；手动 / force 入口仍 cat 内并发 |
| 🟡 P3 | postUnreadCount 失败广播 0 | 改 strict fetch + do/catch；失败仅 Log 保留上次 badge，不再"假装全读完" |
| 🟡 P3 | startupError 复用 globalAIError | 新增 `@Published var startupError`，AppDelegate 写它；MenuBarView banner 优先级 startup > global > per-cat；启动错误不被 AI 成功路径清除 |
| 🟡 P3 | recommendCount 撒谎 | BailianService.recommendArticles/makeRecommendPrompt/parseRecommendResponse + RecommendEngine 阈值 + RecommendSectionView 全部从 `CategoryConfig.for(cat).recommendCount` 取；协议加 `count: Int` |

### 第五轮 review（4 项 P2/P3）

| 等级 | 项 | 修复 |
|---|---|---|
| 🟠 P2 | onboarding 断点 | 新增 `RefreshService.applyCredentialChange()`：清 globalAIError + 重置 credential 相关 per-cat unavailable + 顺序 await refresh 三 cat。APISettings 测试成功后 fire-and-forget 调用 |
| 🟡 P3 | 禁用/删除源后 badge stale | FeedRowView.handleToggle 与 FeedsSettingsView.deleteCustomFeeds 成功路径调 `postUnreadCount(context:)` 同步 menu bar |
| 🟡 P3 | 自定义 RSS URL 不去重 | AddFeedSheet 加 `normalize` + insert 前 fetch 全量 Feed 比对；重复弹 alert 拒绝（不做订阅合并） |
| 🟡 P3 | ArticleSnapshot 旧 tolerant API | 删 `capture(from:)` + `capture(from:category:)`；只留 `captureOrThrow`（生产已全部迁完） |

测试 +2 (214 → 216)：`testApplyCredentialChangeClearsErrorsAndTriggersAllCats` + `testApplyCredentialChangeResetsAnyUnavailableToUnknown`。

### 第六轮 review（5 项 P2/P3）

| 等级 | 项 | 修复 |
|---|---|---|
| 🟠 P2 | APISettings 错值覆盖好配置 | saveAndCheck 先 testConnection 局部 apiKey/model，成功才持久化；失败 prefs 不动 |
| 🟠 P2 | RSS / 打开文章 scheme | RSSService 与 openArticle 都 guard `http/https`，拒绝 file://、javascript:、shell: |
| 🟡 P3 | AddFeed try? fetch false-empty | strict `try modelContext.fetch`；失败弹"保存失败"；URL/title trim 后再存 |
| 🟡 P3 | applyCredentialChange 误清 | 静态 `missingCredentialReason`，精确比对，**只清** credential 那一条；business reason 保留到下次 refresh 重判 |
| 🟡 P3 | AddFeed 成功不触发 refresh | 保存成功后 fire-and-forget `service.refresh(selectedCategory)`，绕过 staleThreshold |

测试 +3 (216 → 219)：`testFetchRejectsNonHttpScheme` + `testFetchAcceptsHttpAndHttps` + applyCredential 精确化拆 2 个（净 +1）。

### 第七轮 review（4 项 P1-P3，含一个真实数据丢失漏洞）

| 等级 | 项 | 修复 |
|---|---|---|
| 🔴 P1 | FilterPipeline 把网络错误也算入 filterFailCount（永久 reject 财报文章）| `Result` 拆 `classificationFailedIds` / `transientFailedIds` / `firstTransientGlobalError`；仅 `BailianError.malformedResponse` 计入 filterFailCount，HTTP 401/403/429/5xx + 网络 + 未知都算 transient（保持 accepted=nil，下轮重试） |
| 🟠 P2 | Filter 后 badge stale | 持久化成功且有写入时补 `postUnreadCount(context:)`；财报文章 accepted=nil→true 时 badge 立即更新 |
| 🟡 P3 | 检测可用性污染主 UI | `checkConnection()` 完全删 set/clear globalAIError；只更新本页 checkStatus（候选 vs 持久化值状态隔离） |
| 🟡 P3 | BuiltInFeeds 仅扫 built-in 去重 | 插入前 fetch 全表（含 custom）比对 URL；删除/同步仍只动 built-in |

测试 +3 (219 → 222)：`testUnknownErrorMarkedAsTransient` (rename) + `testMalformedResponseMarkedAsClassificationFailed` + `testHTTP401MarkedAsTransientWithGlobalError` + `testHTTP429MarkedAsTransient`（净 +3）。

## 设计文档

- `CLAUDE.md` — 完整工作记录与设计决策表（含 38 条踩坑记录）
- `docs/plans/multi-category-redesign.md` — v2 重构 spec（16 题 grill 决策 + 6 phase 拆分）
- `docs/plans/optimization-plan.md` — v1 阶段 4 项重构记录
