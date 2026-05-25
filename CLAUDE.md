# AINewsBar — Claude 工作记录

## 项目背景

macOS 菜单栏 AI 资讯阅读器。通过 `/grill-me` 技术访谈定义设计决策，从零完成全部实现（截至 2026-05-20 所有功能已完成并可运行）。当日通过第二次 `/grill-me` 16 轮访谈完成 4 项 ROI 最高的重构（错误治理/视图拆分/外观模式/全表 fetch 优化），详见 `docs/plans/optimization-plan.md`。

> **工作流约束（2026-05-24 起）**：本工程**不使用 superpowers 系列 skill**（`superpowers:*`，含 `writing-plans` / `executing-plans` / `subagent-driven-development` / `brainstorming` / `using-superpowers` 等）。规划/执行/code review 走通用流程（`/grill-me` 访谈 + 直接编辑实现 + 必要时手动调度 subagent），spec/plan 文档不再放 `docs/superpowers/`，需要时落 `docs/plans/`。

**2026-05-21 增量**：
1. **每日 AI Token 用量统计**（grill 7 轮设计）：明细级 SwiftData 记录、按场景拆分（summary/recommend/digest）、滚动 30 天保留、Footer "今日 X tokens" + Settings "用量" Tab（今日卡片 + 7/30 天堆叠柱图）。失败调用 tokens=0/success=false。
2. **Linus 标准 review 5 项修复**（详见踩坑 #13/#14/#15）：
   - P1 后台 timer 冷启动不工作 → startup 全挪到 `AppDelegate.applicationDidFinishLaunching`
   - P3 `clearDigest()` 副作用扩散 → 拆为 `clearDigest` + `clearRecommendState`，caller 显式选择
   - P10 摘要大面积失败 UI 不告知 → `completionRate < 0.8` 时设 `.unavailable("摘要调用多数失败 N/M")`
   - P11 RSS pubDate 缺失伪造为现在 → `RawArticle.publishedAt: Date?`，nil 时不入库
   - P2 `shared` + `@StateObject` 并存 → 加注释说明职责分工（启动期入口 vs SwiftUI 状态订阅）

**2026-05-22 增量**：跨日 UX 完善 + 推荐项 UI 升级
1. **相对时间格式器**（踩坑 #18）：`Utils/RelativeDateFormat.swift` 替换 SwiftUI 内置 `Text(date, style: .relative)`——内置 API 显示 "3 hours" 不带方向且会 tick 更新；自定义版本输出"刚刚 / X 分钟前 / X 小时前 / 昨天 / N 天前 / M/d"，用户能一眼识别"昨天"
2. **跨日全量重置**（踩坑 #19）：`RefreshService.resetCrossedDayStateIfNeeded()` —— 跨日时清 SwiftData 文章 + @Published UI 状态（dailyDigest / recommendedArticleIDs / lastDigest&RecommendDate / digest&recommendArticleCount）+ `prefs.clearDigest/clearRecommendState` + postUnreadCount。在 `scheduleTimer` block 与 `refreshIfNeeded` 入口**双调用**——前者覆盖 always-on 后台路径，后者覆盖用户打开菜单瞬间路径
3. **推荐项 UI 三重视觉升级**（迭代 4 版收敛）：
   - pubDate 显示在顶部一行（feedTitle ← → 相对时间），与文章列表布局对齐
   - 左侧 3pt 橙色色条（贯穿）作为未读主指示
   - Index 数字字重&色 + 标题字重&色按 isRead 联动
   - 去掉 `RecommendSectionView` 的 `Divider().padding(.leading, 34)`——会在两项之间挤入 1pt 横线切断左侧色条；改由 RecommendItemView vertical padding 自然分隔（踩坑 #20）

**2026-05-22 晚间增量**：14 项严重问题修复（commit `0e5b4fd`，140/140 测试通过）。流程：grill 收敛方案 → 6 批顺序实施 → 启动验证 → push。

1. **跨日重置三件套加固**（踩坑 #21）：
   - 拆 `lastResetCheckDate: Date?` 与 `lastRefreshDate` 解耦——旧逻辑复用 lastRefreshDate 做 guard，会被 refresh() 末尾 `lastRefreshDate = Date()` 抹掉跨日信号
   - reset 移到 `refresh / forceRegenerateRecommend / forceRegenerateDigest` 三个入口第一行
   - `AppDelegate` 加 `NSWorkspace.didWakeNotification` 监听（覆盖系统休眠跨日盲区，Timer.scheduledTimer 在 App Nap 下不按真实时间累计）
2. **Silent failure 三联根治**（踩坑 #22/#23/#24）：
   - `ModelContext+Safe` 双轨 API：保留 `safeFetch/safeSave`（失败容忍，非关键路径）+ 新增 `safeFetchOrThrow/safeSaveOrThrow`（严格抛出，关键路径）
   - `existingURLs` fetch 改 strict——失败假空会让全部抓回文章被当新文章重插（重复入库）
   - `commitSummaries` 用 id 重新 `safeFetchOrThrow` alive Article（避免 30s+ await 期间 @Model 引用 detached → 写入未定义行为）
   - `safeSaveOrThrow` 失败 → 回滚内存 aiSummary + `aiAvailability=.unavailable` + token 记 `success=false`
3. **force/auto 并发互斥**（踩坑 #25）：`refreshTask: Task<Void, Never>?` inflight 复用，refresh / forceRegenerate* 入口 `await existing.value` —— 避免双 commit 互相覆盖与双扣 token
4. **SummaryPipeline 取消支持**（踩坑 #26）：TaskGroup 多点检查 `_Concurrency.Task.isCancelled` + 新增 `.cancelled` outcome（不计 failed 不记 UsageRecord）—— 避免取消后 5 路 task 仍跑完烧 token
5. **单点**：
   - `RecommendSectionView` 用 `Dictionary(uniquingKeysWith:)` 避免重复 id `fatalError`（容灾路径已知会触发，踩坑 #27）
   - `BailianService.recommendArticles` items<3 改 `throw insufficientCandidates`（不再退化返回全部 id）
   - `UsageRecorder.cleanupOlderThan` fallback 改 `.distantPast`（旧 fallback `Date()` 会清空整表，踩坑 #28）
   - `SummaryPipeline.runOne` 空 summary trim 后降级 failure（避免 `aiSummary=""` 污染 digest prompt）
   - `AppDelegate.makeContainer` 二次失败 in-memory `ModelConfiguration` fallback（避免 SIGABRT）
   - `UsageSettingsView` 加 `Timer.publish(60s).autoconnect()` + onReceive 跨日才 set now（@Query 不响应系统时钟，踩坑 #29）
   - `RefreshService` 暴露 `stop()` 清 timer + cancel refreshTask；测试 tearDown 显式调用（踩坑 #30：Swift 5.9 不支持 `@MainActor isolated deinit`）
   - `MockAI` 计数器加 `NSLock + withLock` 保护（旧 `var summaryCallCount` 在 5 并发下数据丢失让测试虚假通过，踩坑 #31）

**2026-05-23 增量**：UI 样式 token 化（commit `363c5f2` → `59fd048` → `e1e75d4`）。流程：grill 8 轮访谈 → spec v1→v2→v3（2 轮 architect review）→ plan v1（1 轮 review）→ 分阶段执行（Phase 1-3）+ Phase 4 验证。原 spec/plan 文档已随 superpowers 工作流一起清理（2026-05-24），决策摘要见下方"设计决策记录"表 Typography / Color token / 区域背景 / 文章行未读指示 等行。

1. **DesignTokens 目录**：`Sources/AINewsBar/DesignTokens/` 新建 3 个 token enum
   - `Typography` 8 档：headline / stat / titleEmphasized / body / calloutEmphasized / callout / caption / captionEmphasized（全 relative font 跟随 Dynamic Type；captionEmphasized 锁定 bold trait）
   - `TextColor` 4 档：primary / secondary / tertiary / accent（tertiary 走 `Color(nsColor: .tertiaryLabelColor)` 桥接 —— SwiftUI 无 `Color.tertiary` 静态属性，只有 `.tertiary` ShapeStyle）
   - `BrandColor` 3 个：accent / accentSoft 用 `NSColor.dynamicProvider` + 原生 sRGB RGB 明暗双值（避免 SwiftUI Color 桥接损失）；surfaceMuted = `Color.primary.opacity(0.06)`
2. **菜单栏 popover 全量 token 化**（8 view）：HeaderView / FooterView / DigestSectionView / RecommendSectionView / RecommendItemView / ArticleListSection / ArticleRowView / MenuBarView.aiUnavailableBanner
3. **设置页同步**（4 Tab / 6 view）：UsageSettingsView (含 22pt stat 进 Typography.stat token) / FeedsSettingsView / FeedRowView / AddFeedSheet / APISettingsView / CheckStatus
4. **区域背景** `.quaternary` → `BrandColor.surfaceMuted` (6% Color.primary)，柔和米白/深灰自动适配明暗
5. **文章行未读视觉**：4pt orange leading dot（HStack 顶部对齐 padding 5pt）+ 去掉原 `accentColor.opacity(0.05)` 行底色
6. **AI banner** 背景 → `BrandColor.accentSoft`（明暗双值 0.08/0.20 保证深色可见）
7. **推荐项**色条 / index：`Color.orange` → `BrandColor.accent`（统一品牌橙）
8. **ProgressView scale 收敛 2 档**（不进 token，inline 约定）：big 0.7 / small 0.55
9. **ArticleRow 标题 fixed `Font.system(size:13)` 例外**：与 `ArticleListSection.listHeight=52` 写死互斥的已知 a11y trade-off
10. **CheckStatus / AddFeedSheet 绿/红 ✓/✗ 语义色保留**（不 brand 化）
11. **AddFeedSheet 保存按钮跟随系统强调色**（与 BrandColor 共存，已知差异）
12. **Charts 内 BarMark / chartForegroundStyleScale 不动**（保留 SwiftUI Charts 默认）
13. **修复同期发现 bug**（commit `4809064`）：`RelativeDateFormat` 内部 `Calendar.isDateInToday(date)` / `isDateInYesterday(date)` 忽略 `now` 参数，跨日 fixture 测试失败 → 改用 `startOfDay(for: now)` 手算 days，时钟注入语义闭环（踩坑 #32）
14. **新增 DesignTokensTests** 3 个 Swift Testing 单测（token 实例化 + dynamic provider 双 appearance 验证用 `NSAppearance.performAsCurrentDrawingAppearance`）；全套 143/143 通过
15. **TextColor 加中间档 `secondaryWeak = Color.primary.opacity(0.40)`**：浅色模式下 feed 来源名（"量子位"等）用 tertiary 26% 太淡看不清，但跳到 secondary 50% 又喧宾夺主。新增 40% 中间档，仅 `ArticleRowView` + `RecommendItemView` 的 `feedTitle` 使用；时间继续 tertiary 形成行内层级（先看来源后看时间）

**2026-05-24 增量**：摘要 markdown 噪声治理 + DigestSection 默认展开（grill 7 轮 → 单 commit 6 step / 149 测试覆盖）。
1. **新建 `Utils/MarkdownStripper.swift`** 纯函数 + 6 个 Swift Testing 单测：strip `**bold**` / `__bold__` / 行首 `# ## ###` 标题前缀；保留行首 `- * +` 列表符号（中文摘要合理层次表达）；单星不动避免误伤
2. **`DigestEngine.run` + `SummaryPipeline.runOne` 接入 stripper**：在 "AI 返回 → outcome / trim 判空" 边界各 strip 一次，prefs/SwiftData 存的都是 clean 版（持久化一致性 + 未来其他出口统一）
3. **Prompt 双约束**（`makeDigestPrompt` + `makeSummaryPrompt`）：在"必须用中文回复"后追加 "请用纯文本回复，不要使用 markdown 语法（不要使用 \*\*、##、- 等符号）"——列举具体符号比泛说 markdown 更可执行
4. **`DigestSectionView` 改默认展开 + 可点击折叠**（踩坑 #26）：
   - 删除 `isHovered` + `onHover` + lineLimit 三元判断（hover 自动展开 + 收起态裁 5 行的复杂状态机）
   - `isExpanded` 默认 `true` 保留点击折叠（嫌长可手动收）；chevron 跟 isExpanded 走（up/down）
   - 折叠态仅显示 header（不再裁 body 显示前 5 行）
5. **设计决策记录新增**：见末尾 "AI 输出净化" / "DigestSection 折叠策略" 行
6. **`feedback_ainewsbar_pitfalls.md` 新增 #26**：AI prompt 未约束格式→markdown 噪声，需 prompt + UI strip 双手硬

**2026-05-25 增量**：从 AINewsBar（单一 AI 资讯）扩展为「资讯助手」多分类（AI / 财报 / 新闻）。grill 16 题访谈 → 单 spec 文档（`docs/plans/multi-category-redesign.md`）→ 6 phase 顺序实施 + 实操 11 项 fix（commit `ec7f254` → `e3e8282`）。

1. **Schema v2-multi-category**：Article/Feed/UsageRecord 加 `category: String` 冗余字段（SwiftData @Query 不支持 join，冗余 1 字段换 O(1) 过滤）；Article 加 `accepted: Bool?` / `filterFailCount`；Feed 加 `skipFilter`；UsageScene 加 `.filter`
2. **Migration 全清策略**：`AppDelegate.makeContainer` schemaVersion 检测，不匹配则 nuke 旧 store + 白名单清 `com.ainewsbar.*` 旧 prefs（保留 API Key + Model + launchAtLogin + SwiftUI window 状态）+ 标 `firstLaunchAfterSchemaUpgrade`
3. **FilterPipeline + AISummarizing 协议双轨**：新增 `classifyArticle`；3 套 cat-specific prompt（summary/recommend/digest）；财报 filter 判定"是/否"（max_tokens=10 / temperature=0.1 / 首字符容错）；失败 3 次永久 reject
4. **RefreshService dict 化**：`@Published states: [Category: CategoryState]` + 12 个 backward-compat shortcut properties 走 `.ai`；per-cat `refreshTasks` inflight；timer fire `refreshAllCatsSequentially` 顺序遍历避免 QPS 峰值；首启 firstLaunch 仅触发 AI cat（财报/新闻 lazy on first tab switch）
5. **UI 全 cat 化**：新建 `CategoryTabBar` (HStack 3 等宽按钮替代 Picker.segmented 避免 macOS 内容宽度问题) + 6 子 view 接 `selectedTab` + Settings 4 Tab 加顶部 Picker；global vs per-cat banner 区分；`.id(selectedTab)` 让 cat 切换重建子 view 重置 `@State`
6. **27 内置源**（curl 验证）：AI 11 不动 + 财报 8（6 en + 2 zh，中文财报 RSS 稀缺为 known limitation）+ 新闻 8（4 en + 4 zh）
7. **测试 +37 case (149 → 186)**：FilterPipeline 10 / BailianServiceFilter 11 / RefreshServicePerCategory 8 / PreferencesServiceCategory 6 / CategoryConfig 7 / BuiltInFeeds +3
8. **修正旧记录**：实际 `BailianService.recommendArticles` 与 UI 都是 **5 篇** 不是 3 篇（旧 CLAUDE.md 错记，本次同步修正第 156 行）

---

**位置：** `/Users/hyf042/Projects/AINewsBar`  
**性质：** 个人工具，Swift Package Manager，macOS 14+，无 Xcode project 文件  
**程序名**（v2 起）：「资讯助手」（CFBundleDisplayName）；binary 仍 `AINewsBar`

---

## 设计决策记录

| 维度 | 决策 | 理由 |
|------|------|------|
| 应用类型 | macOS 菜单栏（MenuBarExtra） | RSS 需后台刷新，WidgetKit 刷新策略不适合 |
| 技术栈 | Swift + SwiftUI + macOS 14+ | 原生体验，MenuBarExtra 成熟，SwiftData 集成顺畅 |
| 数据来源 | 内置精选源 + 用户自定义 RSS | 开箱即用 + 灵活扩展 |
| UI 布局 | 文章列表 → AI 推荐 → 今日摘要 | 操作项优先，静态阅读内容置后 |
| 刷新策略 | 后台每小时 + 打开时按需（超 30 分钟触发） | 兼顾实时性和资源效率 |
| 已读状态 | 两个独立 @Query（未读在前 + 已读在后），标题色区分 | List Section header 有系统背景色问题，改用普通行充当分隔 |
| 文章点击 | 浏览器打开原文 + AI 一句话简介 | 符合用户预期 |
| AI 摘要服务 | 阿里云百炼 DashScope，模型可配置（默认 qwen3.6-plus） | 原设计 qwen-plus，升级为新模型列表；支持千问/智谱/Kimi/MiniMax |
| 密钥存储 | UserDefaults（`com.ainewsbar.claude-api-key` / `com.ainewsbar.model`） | ad-hoc 签名避免弹授权窗口；服务原名 KeychainService，已重命名为 PreferencesService 反映实际实现 |
| 数据持久化 | SwiftData（Feed / Article）+ UserDefaults（日报内容/生成时间/摘要数量） | 日报跨重启保留，次日自动失效；摘要数量用于 Plan A 增量判断 |
| 分发方式 | 仅自用，ad-hoc 签名 | 无需公证和 App Store 审核 |
| RSS 抓取并发 | TaskGroup 全并发（11 个 feed 同时抓） | 各 feed 互相独立，无需限速 |
| AI 摘要并发 | TaskGroup 最多 5 并发 | 避免触发 DashScope QPS 限制；串行改并发显著缩短刷新时间 |
| AI 生成触发策略 | 80% 完成度阈值 + Plan A delta≥3 补触发 | 避免部分失败时生成低质内容，同时保证补齐后能重新生成 |
| 手动刷新 | 推荐/摘要各有独立刷新按钮，绕过所有自动触发条件 | 用户主动操作意图明确，两个区域各自独立控制 |
| 服务架构 | 外观 (RefreshService) + SummaryPipeline + RecommendEngine + DigestEngine + ArticleSnapshot | force/auto 路径统一为 `run(trigger:)` + Trigger enum，零重复；Engine 纯业务可独立单测 |
| 视图组织 | `Views/MenuBar/` + `Views/Settings/` 子目录；EnvironmentObject 注入 RefreshService | 单文件 <200 行；singleton 散布点 12+ → 1 处（AINewsBarApp） |
| 错误处理 | `ModelContext+Safe` 扩展统一 `safeFetch/safeSave` + `Log.write("[DB] ...")` | 替代散落 25+ 处 `try?` 吞错，可观察性大幅提升，UI 行为零变更 |
| AI DI | `AISummarizing` 方法签名带 `model: String` 显式参数；BailianService 不读 prefs | 解除 `PreferencesService.shared.getModel()` 单例后门，测试可完全 mock |
| Token 用量存储 | 明细级 `UsageRecord` @Model（id/timestamp/scene/model/in+out tokens/success），SwiftData 持久化 | 数据量可控（30 天 ≤ 400 条），查询灵活，未来可扩展导出 |
| Token 用量 scene | 仅 3 业务场景 summary/recommend/digest；testConnection 不入库 | 3 档堆叠柱图干净；test 量极小（≤ 5 token）不影响"今日总量" |
| Token 用量 UI | Settings 新增"用量" Tab（今日卡片 + 7/30 天 SwiftUI Charts 堆叠柱图）+ Footer "· 今日 X tokens"（@Query 反应式） | 菜单栏不拥挤，详情进 Tab；K/M 格式化 |
| Token 失败语义 | 失败调用入库 tokens=0 success=false；趋势图 filter success | 能在 UI 上看到"AI 服务质量"信号；趋势图按 token 求和不被失败污染 |
| Token 写入路径 | `AISummarizing` 三方法返回 `(value, UsageInfo)`；Pipeline/Engine 把 usage 传回 `RefreshService`，由外观集中 `record(...)` | BailianService 保持纯 HTTP 不耦合 UsageRecording；测试边界清晰 |
| Startup 启动逻辑 | 全部在 `AppDelegate.applicationDidFinishLaunching`：container 创建、UsageRecorder + cleanup、`configure`、feed sync、`postUnreadCount`、`launchBackgroundRefreshIfNeeded` | 避免依赖 `MenuBarView.task`（popover lazy view，用户点击前不触发）|
| 跨日重置 | `resetCrossedDayStateIfNeeded()` 在 timer 与 refreshIfNeeded 双调用；清 SwiftData + @Published + prefs 三层 | SwiftUI `@Published` 状态在跨日时从未自动失效，仅清 prefs 无法让 UI 立即切换 |
| 相对时间显示 | 自定义 `formatArticleRelative(_:now:calendar:)` 纯函数 | SwiftUI 内置 `.relative` style 无方向感（"3 hours" 而非"3 小时前"），且会 tick 更新与"今日新闻"语义不符 |
| 推荐项未读指示 | 左侧 3pt 贯穿橙色色条 + Index 联动 + 标题联动（三重叠加，不加整行底色） | 单一信号在 12pt + quaternary 背景下不够明显；色条用 Mail.app leading-bar 范式且与 Index 色调统一；整行底色会与父容器 quaternary 层叠杂乱 |
| ModelContext 错误处理 | 双轨 API：`safeFetch/safeSave`（失败容忍）+ `safeFetchOrThrow/safeSaveOrThrow`（严格抛出） | 容忍版本用于非关键路径（cleanup/postUnreadCount），严格版本用于关键路径（去重 fetch/commit summaries），让 caller 显式区分"真的无数据"与"fetch 失败" |
| 跨日 guard 字段 | `lastResetCheckDate: Date?` 与 `lastRefreshDate` 解耦 | 旧实现复用 lastRefreshDate 做 guard 被 refresh() 末尾 `lastRefreshDate = Date()` 抹掉跨日信号，永久丢失重置机会；新字段仅 reset 内部 set，保证 guard 不被外部漂白 |
| force/auto 并发互斥 | `refreshTask: Task<Void, Never>?` inflight 复用，所有入口 `await existing.value` | 避免双发 AI/双 commit/双扣 token；用户体感最多等几秒可接受。比加 isInflight flag 静默 skip force 的 UX 更友好 |
| Pipeline 取消语义 | `.cancelled` 状态独立于 `.failure`，不计 failed 不记 UsageRecord | 取消（用户关菜单/退出）不是 AI 失败，不应污染 aiAvailability 与失败率；同时 Task.isCancelled 多点检查避免烧 token |
| 启动数据库容灾 | 二次构造失败 in-memory `ModelConfiguration` fallback，三次失败才 fatalError | 个人工具优先可用性：用户至少能看到菜单栏，本次会话数据不持久化；下次启动若磁盘恢复会自动重试持久化容器 |
| 测试 Timer 清理 | RefreshService 暴露 `stop()` 清 timer + cancel refreshTask；测试 tearDown 显式调用 | Swift 5.9 不支持 `@MainActor isolated deinit`，无法在 deinit 兜底；singleton 生产侧不释放无需 deinit，仅测试需要 |
| Typography 体系 | relative font 8 档（headline/stat/titleEmphasized/body/calloutEmphasized/callout/caption/captionEmphasized） | 跟随系统 Dynamic Type；ArticleRow 因 listHeight 写死保留 fixed `Font.system(size:13)` 作为已知 a11y trade-off |
| Color token | TextColor 5 档（primary/secondary/**secondaryWeak**/tertiary/accent） + BrandColor accent/accentSoft/surfaceMuted | tertiary 用 `Color(nsColor: .tertiaryLabelColor)` 桥接（SwiftUI 无 Color.tertiary 静态属性）；secondaryWeak = `Color.primary.opacity(0.40)` 为 feed 来源名提供"略显眼但不抢戏"中间档（介于 secondary 50% 与 tertiary 26%）；BrandColor 用 `NSColor.dynamicProvider` + 原生 sRGB 避免 SwiftUI Color 桥接损失；surfaceMuted = `Color.primary.opacity(0.06)` |
| ProgressView scale 约定 | inline 收敛 2 档：big 0.7 (Header refresh) / small 0.55 (inline)，**不进 token** | 单点散点，token 化 ROI 低；plan §7 明确不交付 |
| 区域背景 | `BrandColor.surfaceMuted` (6% Color.primary) 替换 `.quaternary` | 浅色模式三块灰背景叠加观感过重；6% 是肉眼可辨 + 不压迫的平衡点 |
| 文章行未读指示 | 4pt orange leading dot（HStack 顶部对齐 padding 5pt），不加行底色 | 推荐区色条 + 文章行 dot 两套差异化方案：推荐有 index 数字占位，文章行结构更紧凑；dot 与色条同用 BrandColor.accent 视觉协调 |
| AI banner 双值 opacity | accentSoft 浅色 0.08 / 深色 0.20 | 深色下 8% 几乎不可见，必须双值；浅色 8% 已足够 |
| AI 输出净化 | `MarkdownStripper.strip` 纯函数在 `DigestEngine.run` 与 `SummaryPipeline.runOne` 双点接入；prompt 端同步追加"不要使用 markdown 语法"约束 | 单靠 prompt 不可靠（temperature > 0 + 模型自由度）；单靠 strip 易出"strip 后纯文本结构错乱"。两手都要硬，prompt 主防 + UI strip 兜底；处理范围保守（`**` / `__` / 行首 `# ## ###`），保留 `- * +` 中文列表层次 |
| DigestSection 折叠策略 | 默认 `isExpanded=true` 全展开 + 点击可折叠；去掉 hover 自动展开与 lineLimit(5) 收起态裁切 | 摘要本就是"一眼看完"，折叠违背设计意图；用户痛点是"差 1-2 行"——根因是 lineLimit(5) + AI 偶发输出 6-7 行（含 markdown 噪声更糟），双 bug 互相强化；保留点击折叠让"嫌长可手动收"的少数派可用 |
| Category 维度落位（v2）| Feed/Article/UsageRecord 加 `category: String` 冗余字段（Article 从 feed 派生写入时保证一致）；Feed:Category 1:1；3 cat 硬编码 enum (`.ai/.earnings/.news`)；CategoryConfig 持有 per-cat filterPrompt + recommendCount | SwiftData @Query 不支持 join，1 字段冗余换 O(1) 过滤；3 cat 是产品决策不是数据（未来加 cat 必然要改 prompt/UI），enum 简单到位 |
| Filter Stage 落位 | 入库后标 `accepted: Bool?`（nil/true/false）；财报 cat 必备 + 其他 cat 可选（CategoryConfig.filterPrompt 为 nil 则 skip）；filter 失败 3 次永久 reject | A "入库前 filter 丢 reject" 看似省事实际每次抓 RSS 都重判同一篇 reject 反复花 token；B 保留原始数据让 prompt 迭代时能 review "被错杀"案例 |
| 协议双轨策略 | 改协议加 cat 参数时同步保留旧无 cat 签名走 protocol extension delegate to .ai（PreferencesStoring / AISummarizing / UsageRecording）| 让 Phase N 改协议时零侵入 Phase N+1 才改的调用方（如 Prefs 改造时 RefreshService 不动）；Phase 4 改造完后可删旧签名 |
| RefreshService dict 化（v2）| `@Published states: [Category: CategoryState]` + 12 个 backward-compat shortcut computed properties 走 `.ai`；per-cat `refreshTasks` inflight；timer fire 顺序遍历避免 QPS 峰值；首启 firstLaunchAfterSchemaUpgrade 仅触发 AI cat | 保留 backward-compat properties 让旧测试 149 个零侵入；timer 顺序而非并发避免 3 cat × 5 并发 = 15 并发触 DashScope QPS 上限；首启 27 源全抓 1-2 分钟体验差，only AI 优先保首屏 |
| Migration 全清策略（v2）| schemaVersion="v2-multi-category" 不匹配则 nuke 旧 store + 白名单清 `com.ainewsbar.*` 业务 key（保留 API Key + Model + launchAtLogin + SwiftUI window 状态）+ 标 firstLaunchAfterSchemaUpgrade | 用户接受历史数据全清；白名单 vs 全 domain 清掉是为保 launchAtLogin 等系统级 key |
| CategoryTabBar 实现（v2）| HStack 3 个 Button 等宽 `.frame(maxWidth: .infinity)` 替代 `Picker(.segmented)`；选中态 `unemphasizedSelectedContentBackgroundColor` + 0.5pt primary border + shadow + semibold 字重 | macOS Picker(.segmented) 按内容宽度无法等分撑满（vs iOS 行为不同，踩坑 #35）；选中态用 macOS native segmented selected 色保证明暗双适配（vs 自己用 dynamic provider 风险高）|

```bash
cd /Users/hyf042/Projects/AINewsBar
swift build
pkill -x AINewsBar; sleep 1
cp .build/debug/AINewsBar build/AINewsBar.app/Contents/MacOS/AINewsBar
codesign --sign - --force build/AINewsBar.app
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

> **不要用 `open` 命令**——在某些状态下会静默失败，进程不启动。  
> **不要直接跑裸二进制**——MenuBarExtra 依赖 bundle 上下文和 Info.plist 的 `LSUIElement=true`。

---

## 已实现功能（持续迭代中，最后更新 2026-05-21）

**核心功能**
1. RSS 抓取，11 个内置源，**全并发抓取**，每小时刷新，只保留当天文章，过期自动清理
2. AI 单篇摘要：最多 5 并发生成，使用前 1500 字符内容，强制中文，无论原文语言
3. 今日 AI 资讯摘要：基于标题+摘要生成 2-3 句概述，悬停临时展开/点击固定展开，max_tokens=300；含手动刷新按钮
4. AI 今日推荐：AI 挑选 5 篇，基于标题+摘要综合判断，附摘要，不受已读状态影响；含手动刷新按钮
5. 推荐区/摘要区**骨架占位**：未生成时显示灰条 + "生成中…" 提示
6. 已读文章显示在列表底部（"已读 (n)" 分隔行），标题色降低；Header 显示 [未读/总数]
7. 订阅源开关：设置页 Toggle，关闭时删除该源文章
8. 去重：refresh 时跨批次双重去重（existingURLs + seenURLs）；ModelContainer 重建后容灾去重（`BuiltInFeeds.deduplicateArticles`）；正常启动不再扫全表
9. Footer：最后更新精确时间 + feed 失败数提示（橙色，点击跳设置）+ 设置 + 退出
10. **Token 用量统计**（2026-05-21）：每次 AI 调用入库 `UsageRecord`，scene 含 summary/recommend/digest；失败 tokens=0 + success=false；滚动 30 天保留；Footer "今日 X tokens"；Settings → 用量 Tab（今日卡片 + 7/30 天 SwiftUI Charts 堆叠柱图）

**UI 交互**
- 文章行：悬停展开摘要（默认 1 行，悬停显示全文），带 easeInOut 动画
- 文章列表高度：自适应（min 120px / max 460px，按文章数量计算）
- 推荐区：同上，提取为独立 `RecommendItemView`（需 `.fixedSize(vertical:true)` 才能在 HStack 中正确撑高）
- 摘要区：悬停临时展开 + 点击固定展开，chevron 跟随两个状态变化
- 区域布局：文章列表 → AI 推荐（`.quaternary` 背景）→ 今日摘要（`.quaternary` 背景）
- AI 不可用时 Header 下方显示橙色 Banner，含"去设置"快捷按钮

**设置页**
- RSS 源检测：每行"检测"按钮 + "检测全部"批量检测，行内绿勾/红叉状态图标，底部汇总
- 添加新源时自动验证，失败弹 Alert 允许强制保存
- AI 模型选择：预设 9 个模型（千问 5 / 智谱 2 / Kimi 1 / MiniMax 1）+ 自定义输入
- API 可用性检测：保存时自动检测 + 手动"检测可用性"按钮，行内状态显示

**AI 调用优化**
- 文章摘要：只处理 `aiSummary == nil` 的；最多 5 并发；完成率 ≥80% 才触发推荐/日报生成
- AI 推荐：有新文章 OR 推荐列表为空 OR 新增摘要 ≥3 篇（Plan A）时调用；生成时记录文章数量到 UserDefaults
- 今日日报：`dailyDigest == nil` 时无条件生成；已有内容则需（有新文章 AND >3h）OR 新增摘要 ≥3 篇（Plan A）；内容+生成时间+文章数持久化到 UserDefaults，跨重启恢复；次日自动失效
- 手动刷新：推荐/摘要各自独立，绕过所有自动触发条件，立即重新生成

---

## 关键文件

### App 入口
| 文件 | 说明 |
|------|------|
| `App/AINewsBarApp.swift` | Scene root 注入 `.modelContainer(AppDelegate.container)` + `.environmentObject(refreshService)`；不再持有 startup 逻辑 |
| `App/AppDelegate.swift` | **冷启动 entry**：`static let container` + `applicationDidFinishLaunching` 执行所有 startup（UsageRecorder + cleanup + configure + feed sync + postUnreadCount + launchBackgroundRefreshIfNeeded + NSWorkspace.didWakeNotification 监听）；隐藏 Dock 图标；`makeContainer` 二次失败 in-memory fallback 避免 SIGABRT |

### Services（外观 + 组件）
| 文件 | 说明 |
|------|------|
| `Services/RefreshService.swift` | **外观** (~470 行)：聚合 @Published UI 状态 + 编排 RSS/Pipeline/Engine + 原子 `commit(Outcome)`；`refresh` / `forceRegenerateRecommend` / `forceRegenerateDigest` 三个公开入口（前置统一调 `resetCrossedDayStateIfNeeded`）；`refreshTask: Task<Void,Never>?` inflight 复用避免双 commit；`lastResetCheckDate` 与 lastRefreshDate 解耦；`commitSummaries` 用 id 重 fetch alive Article；暴露 `stop()` 清 timer+task 给测试 tearDown |
| `Services/SummaryPipeline.swift` | 摘要并发管道：`run(tasks:apiKey:model:) -> Result` 有界并发（5 路）；多点检查 `_Concurrency.Task.isCancelled` 支持取消（取消独立 `.cancelled` 状态不计 failed 不记 UsageRecord）；空 summary trim 后降级 failure |
| `Services/RecommendEngine.swift` | AI 推荐生成：`run(trigger:snapshot:apiKey:model:) -> Outcome?`；`Trigger.auto(...) / .forced` 枚举区分决策路径 |
| `Services/DigestEngine.swift` | 今日日报生成：同 RecommendEngine 对称结构 |
| `Services/ArticleSnapshot.swift` | Sendable 值类型，封装一次性快照；`pickInputs / summarizedPairs / summarizedCount` 三种投影供 Engine 复用 |
| `Services/BailianService.swift` | DashScope HTTP 调用（曾名 ClaudeService.swift）；方法签名带 `model: String` 显式参数（不再读 prefs 单例）；含 `BailianError` 自定义错误（含 `.insufficientCandidates`，recommend items<3 时 throw 不再退化全选）；prompt 构造与序号解析为可单测的静态方法 |
| `Services/PreferencesService.swift` | UserDefaults 后端（曾名 KeychainService），构造可注入 UserDefaults 以便测试隔离；conform `PreferencesStoring`；含模型/日报内容/日报生成时间/推荐摘要数/日报摘要数持久化 |
| `Services/ServiceProtocols.swift` | `RSSFetching` / `AISummarizing`（含 model 参数）/ `PreferencesStoring`（含 getModel） |
| `Services/RefreshDecision.swift` | 触发决策纯函数集：`completionRate` / `shouldRegenerateRecommend` / `shouldRegenerateDigest` / `withinRegenerationWindow`；时钟通过 `now:` 参数注入 |
| `Services/RSSService.swift` | FeedKit 包装 actor；返回 `RawArticle: Sendable` 跨 actor 边界；`publishedAt: Date?` 缺失 pubDate 不伪造 |
| `Services/BuiltInFeeds.swift` | 11 个内置源数据 + `syncInto(context:)`（启动时同步）+ `deduplicateArticles(context:)`（重建路径容灾） |
| `Services/UsageRecording.swift` | UsageRecording 协议（`record` / `cleanupOlderThan`）+ extension 便利方法（`record(info:)` / `recordFailure`） |
| `Services/UsageRecorder.swift` | SwiftData 后端 `UsageRecording` 实现，@MainActor；含静态查询 `todayTotalTokens(in:now:)` |
| `Services/UsageAggregator.swift` | 纯函数 `todayStats` / `dailyByScene`，时钟通过参数注入；UI 与测试共用 |
| `Services/UsageFormatter.swift` | `formatTokens(Int) -> String` 纯函数，`<1K` 原值 / `<1M` K 后缀 / 否则 M 后缀 |

### Views（拆分后子目录）
| 文件 | 说明 |
|------|------|
| `Views/MenuBarView.swift` | 主视图框架 (169 行)：两个独立 @Query + body 组合 + 辅助 view（loading/empty/error/banner）+ openArticle |
| `Views/ArticleRowView.swift` | 文章行；用 `onTapGesture` 而非 `Button`（见踩坑 #1） |
| `Views/SettingsView.swift` | 仅 TabView 容器，4 个 Tab：订阅源 / API / 用量 / 通用 |
| `Views/Settings/UsageSettingsView.swift` | 用量 Tab：今日卡片（Tokens / 调用 / 失败）+ 7/30 天 SwiftUI Charts 堆叠柱图 |
| `Views/MenuBar/HeaderView.swift` | 标题 + 未读计数 + 刷新按钮 |
| `Views/MenuBar/FooterView.swift` | 最后更新 + feed 失败数 + 设置/退出 |
| `Views/MenuBar/DigestSectionView.swift` | 今日日报区，含 `@State isExpanded/isHovered` |
| `Views/MenuBar/RecommendSectionView.swift` | AI 推荐区；**复用 `unreadArticles + readArticles` 内存查找**（O(n) + 保序，零 IO）；**无 Divider**（避免切断 RecommendItemView 左色条） |
| `Views/MenuBar/RecommendItemView.swift` | 单条推荐：左 3pt 橙色色条（未读贯穿/已读透明占位）+ 顶行 feedTitle/相对时间 + Index 数字与标题双联动 isRead |
| `Views/Settings/CheckStatus.swift` | `CheckStatus` enum + `CheckStatusIcon` 通用组件 |
| `Views/Settings/FeedRowView.swift` | `FeedRowView` + `BuiltInFeedRowView`（Toggle + handleToggle） |
| `Views/Settings/FeedsSettingsView.swift` | RSS 源列表 + 行内/批量检测 |
| `Views/Settings/AddFeedSheet.swift` | 添加自定义源（validation + force-add alert） |
| `Views/Settings/APISettingsView.swift` | API Key + 模型选择 + 可用性检测 |
| `Views/Settings/GeneralSettingsView.swift` | 开机启动开关 |

### Models
| 文件 | 说明 |
|------|------|
| `Models/Article.swift` | SwiftData `@Model`，id/title/url/content/publishedAt/feedID/feedTitle/isRead/aiSummary |
| `Models/Feed.swift` | SwiftData `@Model`，title/url/iconURL/isBuiltIn/isEnabled/addedAt |
| `Models/UsageRecord.swift` | SwiftData `@Model`（id/timestamp/scene/model/in+out tokens/success）+ `UsageScene` enum（summary/recommend/digest）+ `UsageInfo` Sendable 值类型 |

### Utils
| 文件 | 说明 |
|------|------|
| `Utils/ModelContext+Safe.swift` | 双轨 API：`safeFetch / safeSave / safeFetchCount`（失败容忍版，返回空集合 / false / 0）+ `safeFetchOrThrow / safeSaveOrThrow`（严格抛出版）；均含调用位置日志 `[DB] file:line — error` |
| `Utils/Log.swift` | 包装 `os.Logger`，subsystem=`com.ainewsbar`；Console.app 可见 |
| `Utils/RelativeDateFormat.swift` | 纯函数 `formatArticleRelative(_:now:calendar:)`：刚刚 / X 分钟前 / X 小时前 / 昨天 / N 天前 / M-d；时钟可注入；ArticleRowView + RecommendItemView 共用 |
| `Utils/MarkdownStripper.swift` | 纯函数 `strip(_:)`：去 `**` / `__` 粗体标记 + 行首 `# ## ###` 标题前缀；保留行首 `- * +` 列表符号与单星强调；DigestEngine.run / SummaryPipeline.runOne 双点接入 |

### 其他
| 路径 | 说明 |
|------|------|
| `docs/plans/optimization-plan.md` | 4 项重构执行计划（含子决策树/验收/回滚） |
| `build/AINewsBar.app` | 打包好的 .app（ad-hoc 签名） |

---

## 内置订阅源（11 个）

OpenAI News, Google DeepMind, Hugging Face Blog, TechCrunch AI, The Verge AI, Ars Technica AI, The Decoder, MIT Tech Review, VentureBeat AI, TLDR AI, 量子位

---

## 踩坑记录

### 1. List 里的 Button 导致行渲染空白

`ArticleRowView` 里**不能用 `Button`**，必须用 `VStack + .contentShape(Rectangle()) + .onTapGesture`。

`MenuBarExtra(.window)` 样式下，`Button + .buttonStyle(.plain)` 放进 `List` 整行渲染空白（SwiftUI bug）。`LazyVStack+ScrollView` 也渲染空白，必须用 `List`。

### 2. SwiftData 新增非可选字段导致迁移崩溃

给 `@Model` 加新的非可选属性后，自动迁移会失败并 fatalError。需在 `AINewsBarApp.swift` 的 catch 块里删除旧数据库并重建。每次改 Model schema 后，先删 `~/Library/Application Support/default.store*` 再运行。

### 3. `open` 命令静默失败

用 `build/AINewsBar.app/Contents/MacOS/AINewsBar &` 直接启动，不用 `open build/AINewsBar.app`。

### 4. 裸二进制运行 MenuBarExtra 图标不显示

必须把二进制放进 .app bundle 再运行，不能直接跑 `.build/debug/AINewsBar`。

### 5. SwiftData @Model 对象不能跨 actor 传递

RSSService 抓完 RSS 后必须返回 `RawArticle: Sendable` 值类型，不能在 actor 里创建 `Article` 对象。跨边界使用会导致静默数据丢失或崩溃。同理，TaskGroup 并发生成摘要时，需先将 Article 属性提取为 `SummaryTask: Sendable` 值类型，结果回到 @MainActor 后再写回 Article 对象。

### 6. @Query 的日期谓词在初始化时捕获，不会自动更新

不能在 `@Query` 的 `#Predicate` 里用 `Date()` 做当天过滤。日期过滤放在 Service 层（RefreshService 插入时过滤 + 刷新时清理旧数据），@Query 只做 isRead 过滤。

### 7. SwiftData 不支持对 Bool 字段排序

`SortDescriptor(\Article.isRead)` 编译报错（`NSObject` 限制）。解决方案：拆成两个独立 `@Query`：一个过滤 `isRead == false`，另一个过滤 `isRead == true`，分别在 List 中 ForEach，中间插入普通行充当分隔符。

### 8. List 的 Section header 带系统背景色

`List` + `.listStyle(.plain)` 下，`Section { } header: { }` 会带 macOS 系统默认的 section header 背景（浅灰/暖色），在浅色外观下明显偏红。解决方案：不用 `Section`，改用普通 `HStack` 行 + `.listRowBackground(Color(nsColor: .separatorColor).opacity(0.12))` 自定义背景。

### 9. 嵌套 HStack 中 Text 高度变化不传导父容器

在 `RecommendItemView` 的 `HStack → VStack → Text` 结构中，`lineLimit` 从 1 变 nil 时文字内容撑高，但父 HStack 不跟随扩展，导致文字被裁剪。修复：在可变高 Text 上加 `.fixedSize(horizontal: false, vertical: true)`，强制父容器按文字自然高度布局。

### 10. TaskGroup 并发摘要时 @Model 跨边界问题

在 `withTaskGroup` 的子任务中不能访问 `@Model` 对象（SwiftData/MainActor 边界）。解决方案：进入 TaskGroup 前将所需字段提取为 `struct SummaryTask: Sendable { id, title, content }`，子任务只持有 Sendable 值；TaskGroup 完成后在 @MainActor 上通过 id 查找原始 Article 对象并写入结果。

### 11. 日报 prompt 只用标题忽略摘要（已修复）

`generateDigest(articleSummaries:)` 参数带有摘要，但原始实现的 map 只用了 `.title`，摘要字段被忽略。修复：prompt 改为 `"- \(title)｜\(summary)"` 格式，质量明显提升。

### 12. `commit(DigestEngine.Outcome)` 不能重置 `aiAvailability`

重构 RefreshService 为外观时，给 `commit(Recommend.Outcome)` 和 `commit(Digest.Outcome)` 都加了 `aiAvailability = .available` —— 测试 `testRefreshHandlesAIErrors` 失败：Recommend 失败设了 `.unavailable`，但紧随其后的 Digest 成功又把它覆盖回 `.available`，UI 不再显示 AI 不可用 Banner。

**修复**：`commit(DigestEngine.Outcome)` 仅写日报内容/时间/计数，**不动 aiAvailability**。Recommend 是 AI 状态的主指示器，Digest 成功不应"治愈"它的失败。原始代码就是这个语义，重构时漏掉了。

### 13. MenuBarExtra 的 popover view 是 lazy 创建，`.task` 冷启动不触发

`MenuBarExtra(.window)` 下，菜单栏图标 always-on，但 popover 内的 view（`MenuBarView`）只在用户**首次点击图标**时才构造，因此 `MenuBarView.task` 直到那一刻前不触发。导致："每小时后台刷新"定时器在 `configure → scheduleTimer` 里，若用户从未点过菜单栏，timer 永不启动。

**修复**：所有启动期逻辑（container 创建、UsageRecorder cleanup、`refreshService.configure`、feed sync、unread count、launchBackgroundRefreshIfNeeded）全部挪到 `AppDelegate.applicationDidFinishLaunching`。`AppDelegate.container` 改为 `static let`，AINewsBarApp.body 通过 `.modelContainer(AppDelegate.container)` 注入。`MenuBarView.task` 不再含 startup。

### 14. SwiftData 多 ModelContext 导致 @Query 看不到 Service 写入

实现 Token 用量时一度让 `AINewsBarApp.onAppear` 用 `ModelContext(container)` 构造 ad-hoc context 注入给 `RefreshService`，而 SwiftUI `@Query` 用的是 `\.modelContext` 环境注入的 main context —— 两个 context 共享容器但内存视图独立，Service 写入的 `UsageRecord` 在 view 端 `@Query` 看不到。

**修复**：统一用同一个 context。AppDelegate 中 `Self.container.mainContext` 同时给 UsageRecorder 和 RefreshService.configure，SwiftUI 自动注入的也是同一个 main context。

### 15. `configure(with:usage:)` 的可选参数默认 nil 会覆盖之前的注入

初版实现里 AINewsBarApp.onAppear 和 MenuBarView.task **两处**都调 `refreshService.configure(...)`，第二次以 `usage: nil` 默认值覆盖前次注入，导致用量统计完全不工作。

**修复**：configure 统一为单一调用点（AppDelegate.applicationDidFinishLaunching）。如未来需要多次 configure，应拆为独立的 `attachUsage(_:)` 方法显式管理。

### 16. `clearDigest()` 命名说谎：副作用扩散到推荐

原 `PreferencesService.clearDigest()` 同时清掉了 `digestArticleCountKey` 与 `recommendArticleCountKey`，后者属于"推荐"概念。caller `loadPersistedState` 跨日时调 clearDigest 会顺带清推荐计数，行为耦合且名字不诚实。

**修复**：拆为 `clearDigest()`（仅 3 个日报 key）+ `clearRecommendState()`（仅推荐计数）。caller 显式两次调用（跨日同时清）。`PreferencesStoring` 协议+`InMemoryPrefs` mock 跟进。

### 17. RSS pubDate 缺失伪造为"现在"导致脏文章每日重生

`RSSService.extract` 三分支原本对无 pubDate 的项 fallback 为 `Date()`，使这些文章永远被视为"今天发布"。配合"过期清理"与"今日入库"逻辑，同一脏 URL 可能每天被清→次日再次以 pubDate=now 出现 →循环重生。

**修复**：`RawArticle.publishedAt` 改为 `Date?`，`extract` 不再 fallback；`RefreshService.mergeNewArticles` 用 `guard let pubDate = raw.publishedAt`，nil 直接丢弃。语义诚实优于"保留更多内容"。

### 18. SwiftUI 内置 `Text(date, style: .relative)` 无方向且自动 tick

ArticleRowView 原本用 `Text(article.publishedAt, style: .relative)`，渲染为 "3 hours" / "in 2 minutes" 这种无"前/后"中文方向，且会实时 tick（菜单栏 popover 关闭打开会重新计数）。用户跨日打开应用时无法直观区分"3 小时前（今天）"和"昨晚 23:50"。

**修复**：新增 `Utils/RelativeDateFormat.swift` 纯函数 `formatArticleRelative(_:now:calendar:)`，规则：刚刚 / X 分钟前 / X 小时前 / **昨天** / N 天前 / M/d。时钟 + 日历参数注入便于单测。ArticleRowView 与 RecommendItemView 共用。

### 19. 跨日时 `@Published` UI 状态从未自动失效（最隐蔽 bug）

应用驻留菜单栏 always-on，跨过午夜后用户打开菜单，"今日 AI 资讯摘要"仍显示**昨天的内容**——直到下次 refresh 跑完 DigestEngine 写入新值才更新。

**Root cause 链**：
1. `loadPersistedState()` 跨日逻辑（清 prefs）只在 `configure()` 时跑一次（启动期）
2. 应用不重启 → 不会触发跨日检查
3. `@Published var dailyDigest` / `recommendedArticleIDs` 一直保留昨天的值
4. 即使 `cleanupOldArticles` 清了 SwiftData 里昨天的 `Article`，`@Published` 状态完全独立

**修复**：`RefreshService.resetCrossedDayStateIfNeeded()` 跨日时同时清：
- SwiftData 里 publishedAt < startOfToday 的 Article
- 所有跨日相关 `@Published`（dailyDigest / recommendedArticleIDs / lastDigest&RecommendDate / digest&recommendArticleCount）
- prefs 持久化（`clearDigest` + `clearRecommendState`）
- `postUnreadCount` 同步未读徽章

调用点 **两处**：
- `scheduleTimer` block —— 后台 timer 触发路径
- `refreshIfNeeded` 第一行 —— 用户打开菜单触发路径（这条是关键，覆盖"应用一直驻留 + 用户跨日打开"场景）

幂等：guard `lastRefreshDate` 跨日才执行，可重复调用。

### 20. `Divider().padding(.leading, 34)` 会切断 RecommendItemView 左侧色条

实现推荐项左侧未读色条（3pt 橙色贯穿整 item 高度）后，截图显示色条在 item 之间有 1pt 断点。Root cause：`RecommendSectionView.pickRows` 在每两个 RecommendItemView 之间放了 `Divider().padding(.leading, 34)`。Divider 虽然从 leading 34pt 起绘制（避开 index 数字区），但其自身 1pt 高度**会在 item 之间占用纵向 1pt 空间**——这 1pt 横向空白会让父容器的 `.quaternary` 背景从最左侧 0-34pt 区域透出，把色条切成多段。

**修复**：去掉 Divider，靠 RecommendItemView 自身的 `.padding(.vertical, 6)` 自然分隔；色条 = `Rectangle().frame(width: 3)`（高度自动 = HStack 高度）在所有未读项之间连续无断点。

**心得**：SwiftUI 任何"行间分隔元素"（Divider / Spacer / 显式 padding）都会占用纵向空间，与"贯穿色条"目标天然冲突。要么 leading bar 完全跳过 divider，要么 divider 改用 background overlay 形式不占空间。

### 21. 复用单字段做"UI 显示"和"跨日 guard"会被业务路径漂白

跨日重置初版只有一个 `lastRefreshDate` 字段——既用于 Footer "最后更新" 显示，又用于 `resetCrossedDayStateIfNeeded` 的 guard（`isDateInToday(last)` 则 noop）。但 `refresh()` 末尾会写 `lastRefreshDate = Date()`，**任何裸调 refresh() 的路径跨过午夜后都会把跨日信号抹掉**——guard 永远 false，跨日重置机会永久丢失。

**修复**：拆出 `lastResetCheckDate: Date?` 做专用 guard，仅由 `resetCrossedDayStateIfNeeded` 内部 set。`lastRefreshDate` 继续做 UI 显示，互不干扰。

**心得**：状态字段如果同时承担 UI 显示与决策 guard 两种语义，几乎一定会被业务路径无意识漂白。分离关注点。

### 22. SwiftData `safeFetch` 失败静默返回空集合 → 下游"假空决策"连锁

`ModelContext+Safe` 初版只有 `safeFetch` 返回空数组 + Log 一行的版本。容忍空集合对 cleanup/postUnreadCount 是 OK 的，但对**关键路径**会引发连锁假象决策：
- `existingURLs = Set(safeFetch.map(\.url))` 失败假空 → 全部抓回文章被当新文章重插（重复入库）
- `pending = safeFetch(predicate: aiSummary==nil)` 失败假空 → 跳过本次摘要
- `ArticleSnapshot.capture` 失败 → 跳过推荐与日报
- `cleanupOldArticles` fetch 失败 → 旧文章不清

**修复**：双轨 API。保留旧 `safeFetch/safeSave`（失败容忍）+ 新增 `safeFetchOrThrow/safeSaveOrThrow`（严格抛出）。关键路径用 strict 版本，caller 显式区分"真的无数据"与"fetch 失败"。

**心得**："默认安全值 fallback" 在数据库场景几乎都是错的——真错和真无差别消失，下游决策被污染却看不出来。出错就要嚷出来。

### 23. SwiftData `@Model` 引用跨 `await` 30s+ 持有可能 detached

`commitSummaries` 旧实现签名 `(pending: [Article], result: ...)`，pending 在 `await summaryPipeline.run` 之前 fetch，await 期间（可能 30s+）外部 cleanup / 用户标记已读 / 其他 context 操作都可能让 Article detach。回来后 `for article in pending { article.aiSummary = ... }` 写 detached 对象是 SwiftData 未定义行为。

**修复**：不持有跨 await 的 `[Article]`。`processAI` 只把 `pending` 转成 `[SummaryPipeline.Task: Sendable]` 喂给 pipeline。`commitSummaries` 在 await 后用 `result.completed` 里的 id 重新 `safeFetchOrThrow` alive Article，对它们写 aiSummary。

**心得**：@Model 引用的安全寿命 = 同一 RunLoop turn。跨 await 想再访问，重新 fetch 一次而非持有引用。

### 24. `safeSave` 失败被吞 + prefs 仍写 → 永久数据不一致

`commitSummaries` 写完所有 `article.aiSummary = ...` 后调 `safeSave`，失败时只 Log 不抛——但 caller 已经记完 token（success=true）且后续写 prefs.articleCount。结果：磁盘上 aiSummary 全 nil 但 prefs 显示"已生成 N 条"，下次刷新 Plan A delta 判断永久错乱。

**修复**：commitSummaries 用 `safeSaveOrThrow` + 整体 try/catch。失败时：
1. 回滚内存 `aiSummary = nil`（让 `ArticleSnapshot.summarizedCount` 不被假象污染）
2. 设 `aiAvailability = .unavailable("摘要保存失败")`
3. token 改记 `success=false`（同一份 UsageInfo 但语义为"花了 token 但没生效"）
4. 不写 prefs.articleCount

**心得**：写入失败时，**所有相关副作用（token/prefs/UI 状态）必须一起回滚**，否则磁盘和内存状态分裂会自我累积。

### 25. `refresh()` 与 `forceRegenerate*` 互不互斥导致双 commit

三个公开入口各 guard 自己的 `isXxx` flag，互不阻断。用户在 auto refresh 中点 force → 第二个 AI 请求并发发出，两次的 commit 都写 `recommendedArticleIDs / lastRecommendDate / recommendArticleCount`，谁后到谁覆盖。后果：UsageRecord 双扣 token、prefs 写错基线、UI 状态闪烁。

**修复**：`refreshTask: Task<Void, Never>?` inflight 复用。`refresh()` 入口先 `if let existing { await existing.value; return }`，自己 spawn 时 set refreshTask，complete 后清空。`forceRegenerate*` 入口先 `if let existing = refreshTask { await existing.value }` 等 auto 完成，再走自己的 isRegenerating* 重入保护。

**心得**：UI 上"是否正在跑"flag 仅做 progress 显示；并发互斥另外用 inflight Task 字段。两套语义不要复用一个 var。

### 26. `withTaskGroup` 不响应 `Task.isCancelled` → 取消后仍跑完

外部 Task 被 cancel 后（用户关菜单 / app 退出），SummaryPipeline 内的 `withTaskGroup` 仍把全部 N 个 task 跑完——`group.cancelAll()` 不会自动触发。结果：用户已退出仍在烧 token，下次 refresh 重入时（isRefreshing 复位）跟第一批并存，真实并发翻倍。

**修复**：在三个点检查 `_Concurrency.Task.isCancelled`：
1. addTask 前（不种入新任务）
2. for await outcome in group 循环内（取消时 `group.cancelAll()`）
3. runOne 内部 await 前后（直接 return `.cancelled`）

且新增 `.cancelled` outcome 独立于 `.failure`，不计入 failedIds 不记 UsageRecord——取消不是 AI 失败。

**心得**：Swift Structured Concurrency 的取消是协作式的，TaskGroup 不自动传播。每个长任务都要显式 checkpoint。

### 27. `Dictionary(uniqueKeysWithValues:)` 容灾路径已知会触发 fatalError

`RecommendSectionView.picks` 用 `Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })` 按 id 索引推荐文章。理论上 SwiftData @Model 的 id 唯一，但 `BuiltInFeeds.deduplicateArticles` 的存在本身就证明历史上出现过重复 Article 行——一旦真出现，推荐区直接 crash。

**修复**：改 `Dictionary(articles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })`，重复时保留首项。

**心得**：当你的代码同时存在"主路径假设唯一" + "容灾路径处理重复"时，主路径的强假设就是漏洞。要么彻底相信唯一性，要么处处用容忍版本。

### 28. 计算 fallback 选错方向：清理类操作 fallback `Date()` 会清空整表

`UsageRecorder.cleanupOlderThan` 初版：`let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()`。一旦 fallback 触发（极罕见但可能），cutoff 落到"现在"，predicate `$0.timestamp < cutoff` 匹配几乎所有记录 → 删空整张表。

**修复**：fallback 改 `.distantPast`，异常时变 no-op 保护历史数据。或 `guard let cutoff = ... else { return }`。

**心得**：所有"删除 / 清理 / reset"类操作的 fallback 必须朝"什么都不做"方向，绝不朝"全干掉"方向。设计 fallback 时问自己：fallback 触发的极端场景下，这个值会让操作变成 no-op 还是 nuke？

### 29. SwiftUI `@Query` 不响应系统时钟，跨日午夜不会重新 eval

`UsageSettingsView` 用 `@Query(sort: ...)` 拿全部 UsageRecord，然后在 body 里 `UsageAggregator.todayStats(records, now: Date())` 算今日数。问题：`@Query` 只对 SwiftData 变更（insert/delete）响应，**不对时钟变化响应**。用户晚上 23:55 打开 Tab 留着不关，跨过零点没有新调用进来，view 不会重 eval，"今日 Tokens" 仍显示昨日数。

**修复**：`@State now: Date` + `Timer.publish(every: 60, on: .main, in: .common).autoconnect()` + `onReceive` 仅跨日（`!isDate(tick, inSameDayAs: now)`）才 set now。所有 `UsageAggregator.*` 调用显式传 `now: now`。比 `TimelineView(.everyMinute)` 省 CPU（不每分钟整 view 重绘）。

**心得**："view 自动响应数据变化" 不等于 "view 自动响应时间变化"。任何依赖"现在"的计算都需要显式 tick state。

### 30. Swift 5.9 不支持 `@MainActor isolated deinit`，清理需 stop()

测试 tearDown 中 `service = nil` 之后 RefreshService 的 Timer 不会自动 invalidate——Timer 被 RunLoop 持有，weak self 让 fire 时 noop 但 timer 对象本身仍占 RunLoop 槽位。N 个测试堆 N 个孤儿 timer。理想做法是 `deinit { timer?.invalidate() }`，但 Swift 5.9：从 nonisolated deinit 访问 `@MainActor` isolated 的 `timer` 字段编译失败；`isolated deinit` 是 Swift 6.2+ 特性。

**修复**：暴露 `func stop()` 清 timer + cancel refreshTask；测试 tearDown 显式 `service?.stop()`。生产 singleton 不释放无需。

**心得**：Swift 5.x 项目里别指望 deinit 兜底持有外部资源的 actor-isolated class。要清理就显式 stop()，让 caller 负责。

### 31. `@unchecked Sendable` mock 的 `var` 计数器在并发下数据丢失

`MockAI` 标 `@unchecked Sendable`，把 `var summaryCallCount = 0` 直接 `summaryCallCount += 1` 在 generateSummary 内部。SummaryPipeline 5 路并发调时多个 child task 并发 mutate 同一字段——Swift Int 写虽 word-atomic 但跨 line 的 read-modify-write 无内存屏障，计数会丢。测试断言 `ai.summaryCallCount == N` 间歇性失败 / 虚假通过。

**修复**：`private let countLock = NSLock()` + `_summaryCallCount` 私有底层 + 计算属性 `countLock.withLock { _summaryCallCount }` 读 + `countLock.withLock { _summaryCallCount += 1 }` 写。provider/usage/error 这些只在 setUp 写一次的 var 保持原样不锁。

**心得**：`@unchecked Sendable` 是"信任 me 自己处理同步"的承诺，不是免责声明。被 mock 的协议如果生产侧有并发调用，mock 也必须配套加锁——否则测试虚假通过会让你以为修复生效。

### 32. `Calendar.isDateInToday(date)` / `isDateInYesterday(date)` 忽略外部时钟参数

`RelativeDateFormat` 函数签名 `formatArticleRelative(_:now:calendar:)` 接受 `now: Date` 参数让单测注入时钟（踩坑 #18 的设计目标）。但实现里用了 `calendar.isDateInToday(date)` / `isDateInYesterday(date)` —— 这两个 macOS API **内部以系统 `Date()` 锚定，完全忽略传入的 calendar 参数对应的"当前时刻"**。结果：fixture `now = 2026-05-22` 测试在真实跑测试日 ≠ 2026-05-22 时，"3 小时前 / 昨天 / 昨日 23:59" 全线返回 "0 天前 / 1 天前"，3 个测试 fail。

**修复**：抛弃 `isDateInToday / isDateInYesterday`，统一用 `calendar.startOfDay(for: now)` + `dateComponents([.day], from:, to:).day` 手算 days，再 if/else 路由到"今天 X 小时前 / 昨天 / N 天前 / 更早 M/d"。让 `now` 参数语义闭环——传 fixture 就按 fixture 算，传当下就按当下算。

**心得**：Apple 提供的 `is*` 便捷 API 多数以**系统当前**为隐式锚点，没有显式时钟注入入口。时钟注入风格的纯函数里**严禁**用任何 `is*Today/Yesterday/Date` 类便捷判定——它们是单元测试时钟注入的"暗门污染"。要么自己用 `startOfDay(for:)` 手算，要么把"今天"概念也作为参数注入。

### 33. macOS SwiftUI `.buttonStyle(.plain) + .foregroundStyle(...)` 不生效

实测 macOS 14：

```swift
// 不生效（按钮文字仍是系统强调色，默认蓝）
Button("检测") { Task { await onCheck() } }
    .buttonStyle(.plain)
    .foregroundStyle(BrandColor.accent)
```

SwiftUI `.buttonStyle(.plain)` 在 macOS 下对 Button 整体调用的 `.foregroundStyle` 不响应——系统强行使用 `accentColor` 当文字色。Plan §7.2 表格描述"plain Button 跟 BrandColor.accent"基于这个错误假设。Phase 4 走查时用户发现 "检测可用性" 等按钮全是系统蓝。

**修复（按按钮形态分两策）**：

```swift
// 策略 A：plain Button —— 把 .foregroundStyle 移到 label 内的 Text 上
Button { Task { await onCheck() } } label: {
    Text("检测")
        .font(Typography.caption)
        .foregroundStyle(BrandColor.accent)  // 装在 label 内才生效
}
.buttonStyle(.plain)

// 策略 B：系统默认 Button（无 .buttonStyle 调用）—— 用 .tint() 修饰符
Button("检测可用性") { Task { await checkConnection() } }
    .tint(BrandColor.accent)
    .disabled(...)
```

涉及 6 个按钮修复：APISettingsView "显示/隐藏"（策略 A）/ "检测可用性"（策略 B）/ FeedRowView 自定义 + builtin 行的 "检测"（策略 A）/ FooterView "⚠ N 个源失败"（策略 A）/ MenuBarView aiUnavailableBanner "去设置"（策略 A）。

**心得**：SwiftUI 容器组件（Button / Label / ToolbarItem 等）对其 root-level modifier 与 label-internal modifier 的语义不一致是一类常见陷阱。**外层 `.foregroundStyle` 在控件类型上语义≠在普通 View 上语义** —— Button 的外层 modifier 是给"按钮外壳"（背景/边框/聚焦环）而非 label 内容用的。任何"想给按钮文字染色"的需求，**默认走 label-internal**；用 `.tint()` 是系统强调色全局染色的快捷方式，但只对**系统主样式 Button** 生效，plain 也不响应 `.tint`。

### 34. SwiftData `@Query` 谓词 3 个 `&&` 条件链让 type-checker 超时

`@Query(filter: #Predicate<Article> { $0.isRead == false && $0.category == "ai" && $0.accepted == true })` 三个条件用 `&&` 连接编译时 "the compiler is unable to type-check this expression in reasonable time"。SwiftData 谓词 macro 展开 + Swift type-check 复杂度爆炸。

**修复**：拆分。@Query 谓词只放 1 个简单条件 (category)，其他过滤 (isRead / accepted) 放在 view 层 `articles.filter { ... }`。

```swift
// FAIL：3 条件谓词超时
@Query(filter: #Predicate<Article> { $0.isRead == false && $0.category == "ai" && $0.accepted == true })

// OK：单条件 @Query + view 层 filter
@Query(filter: #Predicate<Article> { $0.category == "ai" })
private var aiArticles: [Article]
private var aiUnread: [Article] { aiArticles.filter { !$0.isRead && $0.accepted == true } }
```

**心得**：SwiftData @Query 谓词复杂度阈值很低（2 条件 OK，3 条件超时）；超时直接表现为编译失败而非性能问题。数据量小时（每 cat 几十-上百）内存 filter 性能开销忽略，安全可靠。

### 35. macOS `Picker(.segmented)` 按内容宽度，无法等分撑满容器

`Picker("", selection:).pickerStyle(.segmented)` 在 macOS 上 3 个 segment 按内容宽度绘制，给 Picker 加 `.frame(maxWidth: .infinity)` 也只让容器变宽，segment 仍居中。与 iOS 行为不同。

**修复**：自定义 HStack 3 个 Button 等宽 (`.frame(maxWidth: .infinity)`) + 选中态用 `Color(nsColor: .unemphasizedSelectedContentBackgroundColor)` 模仿 native segmented。

**心得**：iOS / macOS 同样 `.pickerStyle(.segmented)` API 但行为差异大；macOS Picker segmented 设计假设是"按需宽度"（compact toolbar 场景）。需要 tab-style 等宽必须自定义。`unemphasizedSelectedContentBackgroundColor` 是 macOS native segmented selected segment 的色，明暗双适配优于自己用 dynamic provider。

### 36. SwiftUI cat-aware view 的 `@State` 在 cat 切换时被继承

主 view 通过 `selectedTab` 参数传给子 view（如 `ArticleListSection(category: selectedTab)`），切 cat 时子 view 的 `@State isExpanded` 保留——SwiftUI 通过 view 类型识别 identity，cat 参数变化不触发重建。

**修复**：`.id(selectedTab)` 让 SwiftUI 把不同 cat 的子 view 当作不同 view 实例，自动重置 `@State`。

```swift
ArticleListSection(category: selectedTab, ...)
    .id(selectedTab)  // cat 切换强制重建 → 重置 @State isExpanded
```

**心得**：SwiftUI view identity 默认走类型；同类型 + 参数不同不会重建。需要"参数变就重置内部状态"语义时显式 `.id(参数)`。代价：每次切换重建子 view 树（@Query 也重新构造），性能开销在菜单栏小 view 可忽略。

### 37. 启动期 RSS fetch 失败常见 race（DNS / 网络栈未就绪）

AppDelegate `applicationDidFinishLaunching` 触发 refresh，此时 macOS networking 可能未完全就绪，11 个 AI 源全 throw（DNS 超时）。但用户后续在 Settings 手动检测时一切正常，看到 Footer "11 个源失败" 困惑。

**修复**：UI 提示错误是历史快照 + 让按钮直接重试当前 cat（而非跳设置）。文案 `"⚠ 上次 X 源失败 · 点击重试"` 明示"过去时态"。

**心得**：网络相关的"启动期 race"在 macOS 桌面 app 是常见模式（不像 iOS 有 background launch states）。最佳实践：UI 标明数据时态 + 提供一键重试，避免用户误以为现网失败。延迟启动 N 秒不是好方案（影响首屏体验）。
