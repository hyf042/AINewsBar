# AINewsBar — Claude 工作记录

## 项目背景

macOS 菜单栏多分类资讯阅读器（v2 起：「资讯助手」 - AI / 财报 / 新闻 三 tab；v1 单 AI tab 阶段）。通过 `/grill-me` 技术访谈定义设计决策。v1 重构详见 `docs/plans/optimization-plan.md`；v2 multi-category 重构详见 `docs/plans/multi-category-redesign.md`。

**位置：** `/Users/hyf042/Projects/AINewsBar`
**性质：** 个人工具，Swift Package Manager，macOS 14+，无 Xcode project 文件
**程序名**（v2 起）：「资讯助手」（CFBundleDisplayName）；binary 仍 `AINewsBar`

> **工作流约束（2026-05-24 起）**：本工程**不使用 superpowers 系列 skill**。规划/执行/code review 走通用流程（`/grill-me` 访谈 + 直接编辑实现 + 必要时手动调度 subagent），spec/plan 需要时落 `docs/plans/`。

## 演进时间线

| 日期 | 里程碑 |
|---|---|
| ~2026-05-20 | **v1 全功能完成**（单 AI tab）：Pipeline/Engine 拆分、ModelContext+Safe 双轨错误处理、UsageInfo 三方法返回、DesignTokens（Typography 8 / TextColor 5 / BrandColor 3）、每日 Token 用量统计 |
| 2026-05-25 | **v2 多分类重构**：3 tab（AI/财报/新闻）、Schema v2 + Migration 全清、FilterPipeline、RefreshService dict 化（`states: [Category: CategoryState]`）、26 内置源、CategoryTabBar。8 轮 Linus review（含 P1 财报永久 reject 数据丢失漏洞）|
| 2026-05-25 | **v2.0.1 发布**：8 轮 review 累计修复打包 |
| 2026-05-26 | **v2.0.2 发布**：schemaVersion bump `v2-multi-category-r2` 强制 nuke（P1 根因，踩坑 #40）+ 分发改 DMG |
| 2026-05-29 (十) | 新闻 tab 内容重构：源 8→7，聚焦实时/社会/国际，去科技去娱乐 |
| 2026-05-30 | **v2.0.6 发布**：hover 崩溃根治（踩坑 #41）+ 推荐 ↔ 文章列表互斥折叠 + 摘要 2 行常显 |
| 2026-06-02 | 摘要超 2 行 hover `.help()` tooltip 看全文（系统级独立窗口，不触发 #41） |
| 2026-06-12 | **Linus 系统性 review 5 项**：C1 API Key Base64 编码防 `strings` 扫描 + 旧版明文自动迁移 / C2 RefreshService 拆三文件消 God-object / H1 SummaryPipeline.Task 删 `.ai` default / H2 抽 `PipelineConcurrency` 消除两 Pipeline 复制粘贴 / H3 抽 `FeedRowComponents` 消除两 FeedRow UI 复制粘贴 |

> 逐轮 review 细节、commit hash、各轮测试数变化见 `git log`，不在此重复。架构决策见下表，踩坑见末段。

---

## 设计决策记录

只记长期有效的架构原则（"指导未来改动"），一次性 bug 修复见踩坑记录 + git log。

| 维度 | 决策 | 理由 |
|------|------|------|
| 应用类型 | macOS 菜单栏（MenuBarExtra） | RSS 需后台刷新，WidgetKit 刷新策略不适合 |
| 技术栈 | Swift + SwiftUI + macOS 14+ | 原生体验，MenuBarExtra 成熟，SwiftData 集成顺畅 |
| 数据来源 | 内置精选源 + 用户自定义 RSS | 开箱即用 + 灵活扩展 |
| UI 布局 | 文章列表 → AI 推荐 → 今日摘要；推荐 ↔ 文章列表互斥折叠（`ExpandedSection` 单字段） | 操作项优先；互斥折叠避免 16 寸 MBP 溢出（recommend 展开占 ~440pt）|
| 刷新策略 | 后台每小时 + 打开时按需（超 30 分钟触发）；跨日 `resetCrossedDayStateIfNeeded()` 双调用（timer + refreshIfNeeded） | 兼顾实时性；@Published 跨日从不自动失效（踩坑 #19）|
| 已读状态 | 两个独立 @Query（未读在前 + 已读在后），标题色区分 | List Section header 有系统背景色问题；SwiftData 不支持 Bool 排序 |
| AI 摘要服务 | 阿里云百炼 DashScope，模型可配置（默认 qwen3.6-plus）；支持千问/智谱/Kimi/MiniMax | — |
| 密钥存储 | UserDefaults，**2026-06-12 起 API Key 改 Base64 编码防 `strings` 扫描 + 旧版明文自动迁移**（C1） | ad-hoc 签名避免弹授权窗口；UserDefaults 明文 key 易被 `strings` 提取 |
| 数据持久化 | SwiftData（Feed / Article）+ UserDefaults（日报内容/生成时间/摘要数量） | 日报跨重启保留，次日自动失效 |
| 分发方式 | 仅自用，ad-hoc 签名 + DMG（`hdiutil`）；README 朋友友好安装指南 | zip 解压双击触发 Gatekeeper "已损坏"；无 $99/年 Developer ID 时 DMG + "仍要打开" 性价比最高 |
| RSS 抓取并发 | TaskGroup 全并发 | 各 feed 互相独立，无需限速 |
| AI 摘要并发 | 手动单 cat / force\* 走有界并发（5）；**auto path（timer/wake/launch）顺序 await 三 cat**（QPS 峰值降到 5） | 后台路径优先可靠性，限速调整/key 多端共享时顺序更安全；最坏冷启动 ~1-2 分钟可接受 |
| AI 生成触发 | 80% 完成度阈值 + Plan A delta≥3 补触发；`coverage` gate 同时挡 recommend 与 digest | 避免部分失败生成低质内容；候选源统一 `snapshot.summarized` 防 nil-summary 烧 token |
| 服务架构 | 外观（RefreshService）+ SummaryPipeline + RecommendEngine + DigestEngine + ArticleSnapshot + FilterPipeline；2026-06-12 RefreshService 拆 `+RSS` / `+AI` 三文件 | Engine 纯业务可独立单测；外观集中编排 + 原子 commit；拆分消 God-object |
| 视图组织 | `Views/MenuBar/` + `Views/Settings/` + `Views/DesignTokens/` 子目录；EnvironmentObject 注入 RefreshService；子 view 用 `.id(selectedTab)` 切换重建（踩坑 #36） | 单文件 <200 行；singleton 散布点 12+ → 1 处（AINewsBarApp）|
| 错误处理 | `ModelContext+Safe` 双轨：`safeFetch/safeSave`（容忍）+ `safeFetchOrThrow/safeSaveOrThrow`（关键路径严格抛出） | 替代散落 25+ 处 `try?` 吞错；caller 显式区分"真无数据"vs"fetch 失败"（踩坑 #22）|
| AI DI | `AISummarizing` 方法签名带 `model: String` 显式参数（无 `.ai` default）；BailianService 不读 prefs | 解除 `PreferencesService.shared.getModel()` 单例后门，测试可完全 mock |
| Token 用量 | 明细级 `UsageRecord` @Model；scene = summary/recommend/digest/filter（testConnection 不入库）；失败强制 tokens=0 + success=false；写入经 `AISummarizing` 三方法返回 UsageInfo → RefreshService 集中 record | 失败语义="花了但没生效"；趋势按 token 求和不被失败污染 |
| Startup 启动逻辑 | 全部在 `AppDelegate.applicationDidFinishLaunching`（container / UsageRecorder / configure / feed sync / postUnreadCount / launchBackgroundRefreshIfNeeded / NSWorkspace.didWakeNotification）；`configure()` 只注入依赖，`scheduleTimer` 在 launch 内部（sync 成功才调） | popover view lazy 创建，`.task` 冷启动不触发（踩坑 #13）；sync 失败时 timer 不该仍 hourly 触发空刷新 |
| 跨日 guard 字段 | `lastResetCheckDate: Date?` 与 `lastRefreshDate` 解耦（仅 reset 内部 set） | 单字段同时做 UI 显示 + guard 会被业务路径漂白（踩坑 #21）|
| force/auto 并发互斥 | per-cat `refreshTasks: Task<Void, Never>?` inflight 复用，所有入口 `await existing.value` | 避免双发 AI/双 commit/双扣 token（踩坑 #25）|
| Pipeline 取消语义 | `.cancelled` 状态独立于 `.failure`，不计 failed 不记 UsageRecord；三点 checkpoint | 取消不是 AI 失败；TaskGroup 取消是协作式（踩坑 #26）|
| 启动数据库容灾 | 二次构造失败 in-memory fallback，三次失败 fatalError；schemaVersion 不匹配 nuke + 白名单清业务 prefs；启动 sanity sweep 三 model（fetch 1 条触发 mandatory 校验）| 个人工具优先可用性；静默删除失败必须可观测（踩坑 #40）|
| 测试 Timer 清理 | RefreshService 暴露 `stop()`；测试 tearDown 显式调用 | Swift 5.9 不支持 `@MainActor isolated deinit`（踩坑 #30）|
| AI 输出净化 | `MarkdownStripper.strip` 双点接入（DigestEngine.run + SummaryPipeline.runOne）+ prompt 端追加纯文本约束 | 单 prompt 不可靠（temperature > 0）；单 strip 易结构错乱；两手都要硬 |
| Category 维度落位 | Feed/Article/UsageRecord 加 `category: String` 冗余；3 cat 硬编码 enum；CategoryConfig 持 per-cat filterPrompt + recommendCount | SwiftData @Query 不支持 join，冗余 1 字段换 O(1) 过滤 |
| Filter Stage 落位 | 入库后标 `accepted: Bool?`（nil/true/false，默认 nil）；财报必备其他可选；`BailianError.malformedResponse` 才计 classification fail → recordFilterFailure，其他错误算 transient 下轮重试 | 入库前 filter 会每次重判 reject 反复烧 token；网络抖动/401/429 不能累计永久 reject |
| 协议双轨策略 | 协议加 cat 时**不留旧无 cat fallback**（2026-05-25 全删过渡 fallback） | 过渡期遗留会让 caller 图省事"默认落 .ai"静默漏改 |
| Migration 全清策略 | schemaVersion 不匹配则 nuke 旧 store + 白名单清 `com.ainewsbar.*`（保 API Key + Model + launchAtLogin）；**任何 v2 内部 schema 演进（含字段 init 默认值变更）都必须 bump r3/r4** | 接受历史数据全清；schemaVersion 颗粒度太粗会留 NULL 行（踩坑 #40）|
| CategoryTabBar | 自定义 HStack 3 Button 等宽替代 Picker.segmented；选中态 `unemphasizedSelectedContentBackgroundColor` | macOS Picker.segmented 按内容宽度无法等分撑满（踩坑 #35）|
| AI 错误分级 | `GlobalAIError`：401→invalidAPIKey / 403→forbidden（模型未授权）/ 429→quotaExceeded / 5xx→other / 网络→networkUnreachable | 一锅炖让用户怀疑代码 bug |
| credentials CQS | `currentCredentials()` 纯查询 + `ensureCredentials(cat:)` 显式 command | 旧 `currentCredentials(cat:)` 名似 query 实是 command |
| FeedRow toggle | 自定义 `Binding(get:set:)`：set 里先 mutate → persist，失败 `context.rollback()` 自动回弹；4 处 isReverting guard + Task 兜底全删 | 双向绑定做"需校验会失败有副作用"的写入是反模式；校验前移到提交前（踩坑 #24 失败回滚）|
| 原子捕获 + 异步失效令牌 | AddFeedSheet/APISettingsView 点击瞬间捕获不可变 draft；`categoryGeneration`/`validationGeneration`/`checkGeneration` 仅在输入 onChange 递增，await 返回 `guard generation == 当前` 才回写 | 用户在异步请求期间改输入，旧请求不该回写 UI/存旧值进 prefs；令牌递增处已复位状态，过期 return 不卡"检测中" |
| RSS/open scheme 校验 | RSSService.fetchRawArticles 与 MenuBarView.openArticle 都 guard `http/https` | RSS 是外部输入；NSWorkspace.open 不应被诱导打开任意 scheme |
| URLNormalizer 保守归一化 | trim / 小写 scheme+host / 去 fragment / 删 path 尾斜杠 / **保留** query + path 大小写 | 保守：宁可漏归一化重复入库，不能误合并丢失；query 不能删 |
| summary 永久 2 行 + tooltip | RecommendItemView/ArticleRowView summary `lineLimit(2).fixedSize(vertical:true)` 恒定高度 + `.help(summary)` 系统级 tooltip 看全文 | hover 改 row 尺寸必崩（踩坑 #41）；tooltip 独立窗口不参与 popover layout |
| hasNewArticles 语义 | `FilterStageOutcome{persisted, newlyAccepted}`；用"入库即 accepted=true + filter 本轮判 true"喂 processAI，而非 RSS 入库数 | 财报 cat 本轮全 reject 时无可见新内容，不该白烧 token 重生派生 |

---

## 构建 & 运行

**开发期（debug 快速迭代）：**

```bash
cd /Users/hyf042/Projects/AINewsBar
swift build
pkill -x AINewsBar; sleep 1
cp .build/debug/AINewsBar build/AINewsBar.app/Contents/MacOS/AINewsBar
codesign --sign - --force build/AINewsBar.app
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

**发版（DMG 分发给朋友）：**

```bash
./scripts/build.sh              # 自动跑 release build + ad-hoc 签名 + 打 DMG
# 输出: build/AINewsBar-x.y.z.dmg（1.0 MB 左右）
```

发版前手动 bump `scripts/build.sh` 的 `VERSION` 与 `BUILD_NUMBER`。DMG 内部含 .app + Applications 软链。朋友首次安装需走 README "朋友友好指南"右键打开授权流程。

> **不要用 `open` 命令**（某些状态下静默失败，踩坑 #3）；**不要直接跑裸二进制**（MenuBarExtra 依赖 bundle 上下文，#4）。

## 已实现功能

完整功能清单 + 用户面向描述见 `README.md`（保持最新）。本文不重复维护。

---

## 关键文件

### App 入口
- `App/AINewsBarApp.swift` — Scene root；不持有 startup 逻辑
- `App/AppDelegate.swift` — **冷启动 entry**：`static let container` + `applicationDidFinishLaunching` 接管所有 startup + NSWorkspace.didWakeNotification 监听 + 二次失败 in-memory fallback

### Services（外观 + 组件）
- `Services/RefreshService.swift` — **外观**：`@Published private(set) states: [Category: CategoryState]` per-cat dict；公开 API：`refresh(_:)` / `forceRegenerate{Recommend,Digest}(_:)` / `refreshIfNeeded(_:)` / `handleSystemWake()` / `markAvailability(_:for:)` / `applyCredentialChange()` / `invalidatePerCatCache(for:)` / `stop()`；DEBUG-only `_testMutate(for:_:)`；per-cat `refreshTasks` inflight 复用；`refreshAllCatsSequentially`；`currentCredentials()` / `ensureCredentials(cat:)` CQS
- `Services/RefreshService+RSS.swift` — RSS 抓取/去重/清理组件；`FeedResult` / `fetchAllFeeds` / `mergeNewArticles` / `cleanupOldArticles`×2
- `Services/RefreshService+AI.swift` — AI Filter/Summary/Recommend/Digest/Commit 组件；`FilterStageOutcome` / `runFilterStage` / `processAI` / `runRecommend` / `runDigest` / `commit`×2
- `Services/SummaryPipeline.swift` — 摘要并发管道；`PipelineConcurrency.run` 替代内联循环
- `Services/RecommendEngine.swift` / `DigestEngine.swift` — 纯执行器；Outcome 含 UsageInfo
- `Services/FilterPipeline.swift` — 5 路并发 filter；返回 acceptedIds / rejectedIds / classificationFailedIds / transientFailedIds + usages
- `Services/PipelineConcurrency.swift` — 有界并发 TaskGroup 执行器（消除 SummaryPipeline / FilterPipeline 复制粘贴）
- `Services/ArticleSnapshot.swift` — Sendable 值快照；仅留 `captureOrThrow`（tolerant 版已删，踩坑 #22 同型）
- `Services/BailianService.swift` — DashScope HTTP；显式 model 参数；`BailianError`（`.httpStatus` / `.malformedResponse` / `.insufficientCandidates`）；4 prompt 工厂 per-cat 静态方法；`classifyArticle` filter API
- `Services/PreferencesService.swift` — UserDefaults 后端；per-cat key 拼接 `com.ainewsbar.<base>.<cat>`；API Key Base64 编码（C1）；读写都 trim
- `Services/ServiceProtocols.swift` — `RSSFetching` / `AISummarizing`（per-cat 显式协议无 fallback）/ `PreferencesStoring`
- `Services/RefreshDecision.swift` — 触发决策纯函数集，时钟参数注入
- `Services/RSSService.swift` — FeedKit actor；`RawArticle.publishedAt: Date?`（nil 不入库，踩坑 #17）；UA + Accept header 防 403；`preferredAtomLink` 优先 rel=alternate（踩坑 #38）
- `Services/BuiltInFeeds.swift` — **v2: 26 内置源（11 AI + 8 财报 + 7 新闻）**；`syncInto(context:)` strict 同步 + categoryChanged 路径先改 feed 再删 articles；`deduplicateArticles` 重建容灾
- `Services/FeedSettingsStore.swift` — 集中处理 feed 启停/删除：`persistBuiltInEnabledChange` / `deleteCustomFeeds` / `handleSkipFilterPendingFlipped`；strict 删 articles + 失败 rollback
- `Services/UsageRecording.swift` / `UsageRecorder.swift` / `UsageAggregator.swift` / `UsageFormatter.swift` — Token 用量协议/SwiftData 实现/纯函数聚合/格式化

### Models
- `Models/Article.swift` — `@Model` + category + accepted (Bool? nil default) + filterFailCount + `recordFilterFailure(maxBeforeReject:)` extension
- `Models/Feed.swift` — `@Model` + category + skipFilter（v2 跳过 AI filter 的"纯净源"toggle）
- `Models/Category.swift` — 3 cat enum + `from(rawValue:)` 解析失败 Log
- `Models/CategoryConfig.swift` — per-cat 配置（filterPrompt / recommendCount）
- `Models/UsageRecord.swift` — `@Model` + category + UsageScene（含 `.filter`）+ UsageInfo

### Utils
- `Utils/ModelContext+Safe.swift` — 双轨 API：失败容忍版 + 严格抛出版；含调用位置日志
- `Utils/Log.swift` — `os.Logger` 包装；subsystem=`com.ainewsbar`
- `Utils/RelativeDateFormat.swift` — 纯函数 `formatArticleRelative(_:now:calendar:)` 时钟注入；用 `startOfDay(for:)` 手算 days（踩坑 #32）
- `Utils/MarkdownStripper.swift` — strip `**` / `__` / 行首 `# ## ###`；保留行首 `- * +` 中文列表层次
- `Utils/URLNormalizer.swift` — 保守 URL 归一化

### Views
完整列表见 `Sources/AINewsBar/Views/` 子目录（MenuBar/ + Settings/ + DesignTokens/）。Banner 区分 startup/global/per-cat 三级优先级；CategoryTabBar 用自定义 HStack 替代 macOS Picker.segmented（踩坑 #35）；子 view 用 `.id(selectedTab)` 切换重建（踩坑 #36）；`Settings/FeedRowComponents.swift` 合并两 FeedRow 共享 UI（H3）。

### 其他
- `docs/plans/optimization-plan.md` — v1 阶段 4 项重构
- `docs/plans/multi-category-redesign.md` — v2 重构 spec
- `build/AINewsBar.app` — 打包好的 .app（ad-hoc 签名）

---

## 内置订阅源

v2: 26 个 = 11 AI + 8 财报 + 7 新闻。完整列表见 `Sources/AINewsBar/Services/BuiltInFeeds.swift` 或 `README.md` § 内置订阅源。

> **新闻 tab 定位**：聚焦实时/社会/国际，去科技去娱乐。7 源 = NYT World + BBC World + FT 中文新闻 + 新华网时政 + 人民日报时政 + 新华网社会 + 澎湃新闻（国内 4 / 国际 3 均衡）。`CategoryConfig.news.filterPrompt` nil（源头干净不开 filter）。

> **中文源镜像依赖**：华尔街见闻 / 第一财经 / 东方财富 / 财新 / 澎湃等官方 RSS 全部 404 或返 HTML，走 RSSHub 公共镜像 `rsshub.rssforever.com`（备用 `rss.injahow.cn`）。公共实例随时可能被反爬升级或下线 — known risk，可接受。

---

## 踩坑记录

每条精简为 "**根因** + **修复/防御**"；完整历史见对应 commit 与代码注释。

### 高价值通用陷阱（完整保留）

**#5. SwiftData `@Model` 不能跨 actor / 跨 await 传递**（原 #5 + #23 合并）
**根因**：跨 actor 边界或跨 `await` 持有 `@Model`，会静默数据丢失 / 崩溃 / 写入被吞（await 期间对象可能 detach）。**防御**：进 TaskGroup / await 前转 `Sendable` 值类型（`RawArticle` / `SummaryTask`），完成后 @MainActor 按 id 重 fetch alive Article 写回；@Model 引用安全寿命 = 同一 RunLoop turn。

**#17. RSS pubDate 缺失伪造"现在" → 脏文章每日重生**
**根因**：fallback `Date()` 使无 pubDate 的脏 URL 每天被清→次日 pubDate=now 重生循环。**防御**：`RawArticle.publishedAt: Date?`，nil 直接丢弃。

**#19. 跨日时 @Published UI 状态从未自动失效（最隐蔽）**
**根因**：SwiftData / UserDefaults 跨日清理与 `@Published` 状态清理是两件事；应用驻留时 `@Published var dailyDigest` 一直保留昨天值，仅清 prefs 无法让 UI 切换。**防御**：`resetCrossedDayStateIfNeeded()` 同时清 SwiftData + @Published + prefs 三层，timer + refreshIfNeeded 双调用。

**#21. 单字段同时做 UI 显示 + decision guard 会被业务路径漂白**
**根因**：`lastRefreshDate` 既显示 Footer 又用于跨日 guard，但 `refresh()` 末尾写 `Date()` 抹掉跨日信号 → guard 永远 false。**防御**：guard 用专用字段（`lastResetCheckDate`），仅由 guard 函数内部 set。心得：状态字段双重语义必被业务漂白，分离关注点。

**#22. `safeFetch` 失败静默空集合 → 下游"假空决策"连锁**
**根因**：持久层封装出错 fallback `[]`，下游把"真错"当"真无"。`existingURLs` 假空→重插重复；`pending` 假空→跳过摘要；`ArticleSnapshot` 假空→跳过推荐/日报。**防御**：双轨 API，关键路径用 `safeFetchOrThrow/safeSaveOrThrow`，caller 显式 catch。心得：数据库场景的"默认安全 fallback"几乎都是错的——出错就要嚷出来。

**#24. 关键写入失败被吞 + 旁路副作用仍写 → 永久数据不一致**
**根因**：DB save 失败只 Log，但 token 已记、prefs 已写、UI 已更新 → 磁盘内存永久分裂。**防御**：写入失败时所有相关副作用（token / prefs / UI 状态）必须一起回滚——`context.rollback()` + 设可观察错误状态 + token 记 success=false + 不写旁路 prefs。FeedRow toggle 同理：用自定义 `Binding(set:)` 把校验前移到提交前，失败 rollback 自动回弹。

**#25. refresh() 与 forceRegenerate\* 不互斥 → 双 commit + 双扣 token**
**根因**：各入口 guard 各自的 `isXxx` flag 互不阻断，并发发出两次 AI 请求，commit 互相覆盖。**防御**：`refreshTasks: Task<Void, Never>?` inflight 复用，所有入口 `await existing.value`。UI "是否在跑" flag 仅做进度显示；并发互斥另用 Task 字段。两套语义不要复用一个 var。

**#26. `withTaskGroup` 不响应 `Task.isCancelled` → 取消后仍跑完烧 token**
**根因**：Swift Structured Concurrency 取消是协作式的，TaskGroup 不自动传播给在跑子任务。**防御**：三点 checkpoint（addTask 前 / for await 循环内 cancelAll / runOne 内）+ `.cancelled` outcome 独立于 `.failure`（取消不是失败，不计 failed 不记 UsageRecord）。

**#28. 清理类操作 fallback 选错方向 → 极端情况清空整表**
**根因**：`cleanupOlderThan` 的 `cutoff ?? Date()` fallback 让 cutoff 落到现在，predicate 匹配全部 → 删空整表。**防御**：删除/清理/reset 类 fallback 必须朝 no-op 方向（`.distantPast`），绝不朝"全干掉"方向；重要 fallback 用 `guard let`。同理：删 store 文件失败不能让 schemaVersion guard 错误推进。

**#31. `@unchecked Sendable` mock 的 var 计数器并发数据丢失**
**根因**：`@unchecked Sendable` 是"我信任自己处理同步"的承诺不是免责声明。`MockAI` 的 `var callCount` 在 5 路并发下 read-modify-write 无内存屏障，计数丢失 → 核心断言失去检验能力，测试虚假通过。**防御**：真正被并发写的字段配 `NSLock + withLock`；只读并发安全的（setUp 写、generate 读）不锁。

**#39. SwiftData ModelContainer 被 `let (_, context)` 立即 ARC 释放 → context SIGTRAP 无 stack trace**
**根因**：ModelContext 不强引用 ModelContainer（不像 Core Data PSC），container 被 ARC 释放后 context 调任何方法触发 SIGTRAP（signal code 5），无堆栈无断言。**防御**：`let (container, context) = ...; _ = container` 显式保活，或挪 setUp storedProperty。心得：测试场景"工厂返回 (Owner, Borrowed)"永远要保活 Owner。

**#40. schemaVersion 颗粒度太粗 + 删 store 失败仍推进版本号 → v2 内部演进留 NULL 行**
**根因**：v2 phase 1 后字段 init 默认值变更（如 `Article.accepted` true→nil）虽不改物理 schema，但旧行新加列值 NULL → 非可选字段 fetch 时 mandatory 校验失败。schemaVersion 字符串没 bump → guard 跳过 nuke。叠加删 store 失败只 Log 不 throw → 版本号仍推进，旧库残留共存。**防御**：任何 @Model 字段（尤其非可选）改动都当 schema 不兼容变更，bump schemaVersion；migration func 改 throws，删 store 失败不推进版本号；启动 sanity sweep fetch 1 条触发 mandatory 校验做最后防线。心得：SwiftData 是 lazy validation，构造成功 ≠ 数据完整。

**#41. SwiftUI hover 改子 view 内在尺寸 → MenuBarExtra(.window) popover NSWindow 重算抛 NSException 必崩**
**根因**：`.lineLimit(isHovered ? nil : 1)` 让 Text 扩行 → 父容器高度变化 → NSHostingView `setFrameSize` → NSWindow KVO 链 → `_postWindowNeedsUpdateConstraints` 在 layout 周期内二次调用抛 NSException → SIGTRAP。**防御**：popover 内交互态变化优先用不改 size 的属性（颜色/透明度/阴影/scale）；看全文改 lineLimit 常量值 / 独立 `.help()` tooltip / 独立 popover。配套：`fixedSize(vertical:true)` 后 HStack 把 `.frame(maxHeight:.infinity)` 当上限不强制撑满，色条需改 `.overlay` fill receiver。

### 早期基础坑（已封装解决，一行速查）

**#1/#8/#20/#36. List/SwiftUI 渲染**：①（#1）MenuBarExtra(.window) 内 `Button + .buttonStyle(.plain)` 放 List 渲染空白 → 用 `VStack + .contentShape(Rectangle()) + .onTapGesture`；②（#8）List Section header 带系统背景色 → 改普通 HStack 行；③（#20）`Divider()` 占纵向空间切断 leading 色条 → 去 Divider 靠 padding 自然分隔；④（#36）cat-aware view 的 @State 在 cat 切换被继承 → `.id(selectedTab)` 强制重建。

**#2/#6/#7/#14/#34. SwiftData 基础**：①（#2）新增非可选字段自动迁移 fatalError → catch 块删 store 重建（v2 起 schemaVersion 检测主动 nuke）；②（#6）@Query `#Predicate` 内 `Date()` 在 init 时捕获不更新 → 日期过滤放 Service 层；③（#7）SwiftData 不支持 Bool 排序 → 拆两个 @Query；④（#14）多 ModelContext 共享容器但内存视图独立 → 统一 `container.mainContext`；⑤（#34）@Query 谓词 3 个 `&&` 让 type-checker 超时 → 谓词只放 1 条件（category），其余 view 层 filter。

**#13/#15/#37. MenuBarExtra / 启动**：①（#13）popover view lazy 创建，`.task` 冷启动不触发 → startup 全挪 AppDelegate；②（#15）`configure(usage: nil = nil)` 默认值覆盖前次注入 → 去默认值或单一调用点；③（#37）启动期 RSS fetch 常见 race（DNS/网络栈未就绪）→ UI 标数据时态 + 一键重试。

**#10/#18/#29/#30/#32. Swift 并发 / 时钟**：①（#10）TaskGroup 摘要 @Model 跨边界（同踩坑 #5）；②（#18）内置 `Text(date, style:.relative)` 无中文方向 + tick → 自定义 `formatArticleRelative`；③（#29）@Query 不响应系统时钟，跨午夜不重 eval → `@State now` + Timer + onReceive 跨日才 set；④（#30）Swift 5.9 不支持 `@MainActor isolated deinit` → 暴露 `stop()`；⑤（#32）`Calendar.isDateInToday/Yesterday` 内部以系统 `Date()` 锚定忽略参数 → `startOfDay` + `dateComponents` 手算。

**#9/#11/#12/#16/#27/#33/#35/#38. AI / UI 杂项**：①（#9）嵌套 HStack Text 高度变化不传父 → `.fixedSize(horizontal:false, vertical:true)`；②（#11）日报 prompt 只用标题忽略摘要 → `"- \(title)｜\(summary)"`；③（#12）`commit(DigestEngine.Outcome)` 不应重置 aiAvailability（Recommend 是主指示器）；④（#16）`clearDigest()` 不能连带清推荐计数 key（拆 `clearRecommendState`）；⑤（#27）`Dictionary(uniqueKeysWithValues:)` 容灾路径会 fatalError → `uniquingKeysWith`；⑥（#33）macOS `.buttonStyle(.plain)` 外层 `.foregroundStyle` 不生效 → 移到 label 内 Text 或用 `.tint()`；⑦（#35）`Picker(.segmented)` 无法等分撑满 → 自定义 HStack；⑧（#38）Atom `entry.links?.first` 可能拿到 rel=self → 优先 rel=alternate。

**#3/#4. `open` 命令静默失败 / 裸二进制图标不显示**：用 `build/AINewsBar.app/Contents/MacOS/AINewsBar &` 直接启动；MenuBarExtra 依赖 bundle 上下文 + `LSUIElement=true`。
