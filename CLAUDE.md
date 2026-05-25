# AINewsBar — Claude 工作记录

## 项目背景

macOS 菜单栏多分类资讯阅读器（v2 起：「资讯助手」 - AI / 财报 / 新闻 三 tab；v1 单 AI tab 阶段）。通过 `/grill-me` 技术访谈定义设计决策。v1 重构详见 `docs/plans/optimization-plan.md`；v2 multi-category 重构详见 `docs/plans/multi-category-redesign.md`。

**位置：** `/Users/hyf042/Projects/AINewsBar`
**性质：** 个人工具，Swift Package Manager，macOS 14+，无 Xcode project 文件
**程序名**（v2 起）：「资讯助手」（CFBundleDisplayName）；binary 仍 `AINewsBar`

> **工作流约束（2026-05-24 起）**：本工程**不使用 superpowers 系列 skill**。规划/执行/code review 走通用流程（`/grill-me` 访谈 + 直接编辑实现 + 必要时手动调度 subagent），spec/plan 需要时落 `docs/plans/`。

## 演进时间线

| 日期 | 增量 | commit |
|---|---|---|
| ~2026-05-20 | v1 阶段全功能完成（单 AI tab）；外观+Pipeline+Engine 拆分；ModelContext+Safe；UsageInfo 三方法返回；AISummarizing 显式 model 参数 | — |
| 2026-05-21 | 每日 Token 用量统计（grill 7 轮）+ Linus review 5 项（详见踩坑 #13-#15 / #17）| — |
| 2026-05-22 早 | 相对时间格式器（#18）+ 跨日全量重置（#19）+ 推荐项三重未读视觉（#20）| — |
| 2026-05-22 晚 | 14 项严重 review 修复：跨日 guard 解耦 / Silent failure 三联（#22-#24）/ force-auto 互斥（#25）/ Pipeline 取消（#26）/ 8 项单点 | `0e5b4fd` |
| 2026-05-23 | DesignTokens 体系（Typography 8 / TextColor 5 / BrandColor 3）+ 8 view token 化 + 5 项 UI 视觉收敛 | `363c5f2` → `e1e75d4` |
| 2026-05-24 | MarkdownStripper（AI 输出净化）+ DigestSection 默认展开 + Prompt 加纯文本约束 | — |
| 2026-05-25 | v2 多分类重构（Schema v2 / FilterPipeline / 27 源 / RefreshService dict 化 / Migration 全清 / CategoryTabBar）；测试 149 → 186 | `ec7f254` → `e3e8282` |
| 2026-05-25 晚 | **Linus review 16 项**（C1+H1-H6+M1-M5+L1-L3）；测试 186 → 208 | `3d57710` `a11a8f5` |
| 2026-05-25 夜 | 6 项设置持久化 / RSS Atom 边界加固：FeedSettingsStore 抽出 / openArticle 失败处理 / Atom rel=alternate 优先（踩坑 #38）；测试 208 → 212 | `b7a917f` |
| 2026-05-25 深夜 | 第二轮 review 5 项：cleanup 严格化 / FeedRow guard 时序 / APISettings 设 globalAIError / UsageRecording 契约统一 (success=false 强制 0) / AppDelegate syncInto 失败处理；测试 212 → 214 | `bb866b0` |
| 2026-05-25 深夜 (二) | 第三轮 review 3 项：跨日 cleanup 一致 strict / scheduleTimer 拆出 configure / summary commit 漏走 helper 修复 | `bbb9234` |
| 2026-05-25 深夜 (三) | 第四轮 review 4 项：auto path 并发→顺序（QPS 15→5）/ postUnreadCount 失败保留 badge / startupError 拆出与 globalAIError 隔离 / recommendCount 真正接入配置 | `496d4a6` |
| 2026-05-25 深夜 (四) | 第五轮 review 4 项：onboarding 断点修复（applyCredentialChange）/ feed 禁用/删除后 badge 同步 / AddFeedSheet URL 去重 / ArticleSnapshot 旧 tolerant API 删除；测试 214 → 216 | `8761c22` |
| 2026-05-25 深夜 (五) | 第六轮 review 5 项：APISettings 验后保存 / RSS+open 文章 scheme 校验 / AddFeed strict fetch 去重 + trim URL / applyCredentialChange 精确 reason 匹配 / AddFeed 成功触发 refresh；测试 216 → 219 (+RSS scheme +applyCredential 精确化拆 2) | `8866473` |
| 2026-05-25 深夜 (六) | 第七轮 review 4 项：FilterPipeline 拆 transient vs classification（财报永久 reject 漏洞）/ Filter 后补 postUnreadCount / 检测可用性按钮不动 globalAIError / BuiltInFeeds 插入扫全表去重；测试 219 → 222 | `456aeeb` |
| 2026-05-25 深夜 (七) | 第八轮 review 4 项：ArticleSnapshot 按 publishedAt 倒序排序 / 删源后清 per-cat digest+recommend 缓存 / saveAndCheck 失败不污染 globalAIError / parseRecommendResponse 改正则提取（支持 "1. 2. 3." 等格式）；测试 222 → 227 + 踩坑 #39 | — |

具体决策见下方设计决策表；具体踩坑见后段；增量段历史详情已沉淀到 git log。

### 2026-05-25 晚 review 全清单（速查）

| 等级 | 项 | 核心修复 |
|---|---|---|
| 🔴 C1 | 跨日 reset dead code | 11 行 if/else → `lastResetCheckDate != nil` |
| 🟠 H1 | 12 个 .ai shortcut 蔓延 | 全删；states `private(set)`；公开 `markAvailability(_:for:)` + DEBUG `_testMutate` |
| 🟠 H2 | commitSummaries 内存回滚舞蹈 | 改用 `context.rollback()` |
| 🟠 H3 | runRefresh 漏写 fetchError | defer + captured value 保证写入 |
| 🟠 H4 | 401/403 一锅炖 | 新增 `.forbidden`，UI 文案区分 |
| 🟠 H5 | 三 cat 串行刷新 | `refreshAllCatsConcurrently` 用 TaskGroup，冷启动 1-2 分钟 → ~30s |
| 🟠 H6 | states setter internal | 已并入 H1 |
| 🟡 M1 | filter 失败状态机散三处 | `Article.recordFilterFailure(maxBeforeReject:)` extension |
| 🟡 M2 | syncInto 删→改顺序坑 | 先改 feed.category 再用 feedID 删 articles |
| 🟡 M3 | currentCredentials 名实不符 | CQS 拆 `currentCredentials()` + `ensureCredentials(cat:)` |
| 🟡 M4 | mutate 递归隐患 | 注释禁止递归（防御性） |
| 🟡 M5 | Schema migration `try?` 静默 | do/catch + 区分 `fileNoSuchFile` + Log |
| 🟢 L1 | prompt 函数 `.ai` 默认 | 删 default，测试显式传 |
| 🟢 L2 | `Article.accepted = true` 默认 | 改 `nil`，"通过"成显式行为 |
| 🟢 L3 | `Category.from` 静默 fallback | Log 非 nil 解析失败 |

**意外副带 bug**：APISettingsView.checkConnection 成功路径原只 set `.ai` cat availability，财报/新闻留 .unknown；改为只清 globalAIError。

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
| 手动刷新 | 推荐/摘要各有独立刷新按钮，绕过所有自动触发条件 | 用户主动操作意图明确 |
| 服务架构 | 外观 (RefreshService) + SummaryPipeline + RecommendEngine + DigestEngine + ArticleSnapshot + FilterPipeline (v2) | Engine 纯业务可独立单测；外观集中编排 + 原子 commit |
| 视图组织 | `Views/MenuBar/` + `Views/Settings/` 子目录；EnvironmentObject 注入 RefreshService | 单文件 <200 行；singleton 散布点 12+ → 1 处（AINewsBarApp） |
| 错误处理 | `ModelContext+Safe` 双轨 API：`safeFetch/safeSave`（失败容忍）+ `safeFetchOrThrow/safeSaveOrThrow`（严格抛出，关键路径） | 替代散落 25+ 处 `try?` 吞错；caller 显式区分"真的无数据"与"fetch 失败" |
| AI DI | `AISummarizing` 方法签名带 `model: String` 显式参数；BailianService 不读 prefs | 解除 `PreferencesService.shared.getModel()` 单例后门，测试可完全 mock |
| Token 用量存储 | 明细级 `UsageRecord` @Model（id/timestamp/scene/model/in+out tokens/success/category v2） | 数据量可控（30 天 ≤ 400 条），查询灵活 |
| Token 用量 scene | 4 业务场景 summary/recommend/digest/**filter** (v2)；testConnection 不入库 | 干净的堆叠柱图；test 量极小不污染 |
| Token 用量 UI | Settings "用量" Tab（今日卡片 + 7/30 天 Charts 堆叠柱图）+ Footer "· 今日 X tokens" | 菜单栏不拥挤；K/M 格式化 |
| Token 失败语义 | 失败入库 tokens=0 + success=false；趋势图 filter success | "AI 服务质量"信号；趋势按 token 求和不被失败污染 |
| Token 写入路径 | `AISummarizing` 三方法返回 `(value, UsageInfo)`；Pipeline/Engine 传 usage 给 RefreshService 集中 `record(...)` | BailianService 保持纯 HTTP 不耦合 UsageRecording |
| Startup 启动逻辑 | 全部在 `AppDelegate.applicationDidFinishLaunching`（container / UsageRecorder / configure / feed sync / postUnreadCount / launchBackgroundRefreshIfNeeded / NSWorkspace.didWakeNotification） | 避免依赖 `MenuBarView.task`（popover lazy view，用户点击前不触发，踩坑 #13）|
| 跨日重置 | `resetCrossedDayStateIfNeeded()` 在 timer 与 refreshIfNeeded 双调用；清 SwiftData + @Published + prefs 三层 | `@Published` 状态在跨日时从未自动失效，仅清 prefs 无法让 UI 立即切换（#19）|
| 跨日 guard 字段 | `lastResetCheckDate: Date?` 与 `lastRefreshDate` 解耦 | 旧实现复用 lastRefreshDate 被 refresh() 末尾抹掉跨日信号（#21）|
| 相对时间显示 | 自定义 `formatArticleRelative(_:now:calendar:)` 纯函数 | SwiftUI 内置 `.relative` 无方向（"3 hours" 而非"3 小时前"）+ tick 更新（#18）|
| 推荐项未读指示 | 左侧 3pt 贯穿橙色色条 + Index 联动 + 标题联动（三重，不加整行底色） | 单一信号在 12pt + quaternary 背景下不够明显；色条用 Mail.app leading-bar 范式 |
| force/auto 并发互斥 | `refreshTask: Task<Void, Never>?` inflight 复用，所有入口 `await existing.value` | 避免双发 AI/双 commit/双扣 token；用户体感最多等几秒可接受（#25）|
| Pipeline 取消语义 | `.cancelled` 状态独立于 `.failure`，不计 failed 不记 UsageRecord | 取消不是 AI 失败，不应污染 aiAvailability；Task.isCancelled 多点 checkpoint（#26）|
| 启动数据库容灾 | 二次构造失败 in-memory ModelConfiguration fallback，三次失败 fatalError | 个人工具优先可用性：用户至少能看到菜单栏，下次启动若磁盘恢复自动重试持久化 |
| 测试 Timer 清理 | RefreshService 暴露 `stop()`；测试 tearDown 显式调用 | Swift 5.9 不支持 `@MainActor isolated deinit`（#30）|
| Typography 体系 | relative font 8 档 | 跟随系统 Dynamic Type；ArticleRow 标题 fixed `Font.system(size:13)` 为 listHeight 写死的 a11y trade-off |
| Color token | TextColor 5 档（含 `secondaryWeak = .primary.opacity(0.40)` feed 来源名专用）+ BrandColor accent/accentSoft/surfaceMuted | tertiary 走 `Color(nsColor: .tertiaryLabelColor)` 桥接；BrandColor 用 `NSColor.dynamicProvider` + 原生 sRGB 避免桥接损失 |
| 区域背景 | `BrandColor.surfaceMuted` (6% Color.primary) 替换 `.quaternary` | 浅色三块叠加观感过重；6% 是肉眼可辨 + 不压迫的平衡点 |
| 文章行未读指示 | 4pt orange leading dot（不加行底色） | 与推荐区色条形成差异化方案，dot 与色条同用 BrandColor.accent 视觉协调 |
| AI banner 双值 opacity | accentSoft 浅 0.08 / 深 0.20 | 深色下 8% 几乎不可见 |
| AI 输出净化 | `MarkdownStripper.strip` 在 DigestEngine.run + SummaryPipeline.runOne 双点接入；prompt 端追加纯文本约束 | 单 prompt 不可靠（temperature > 0）；单 strip 易出结构错乱；两手都要硬，处理范围保守（保留 `- * +` 列表层次） |
| DigestSection 折叠策略 | 默认 `isExpanded=true` 全展开 + 点击可折叠 | 摘要本就是"一眼看完"；旧 lineLimit(5) + AI 偶发 6-7 行双 bug 互相强化 |
| Category 维度落位（v2）| Feed/Article/UsageRecord 加 `category: String` 冗余字段；Feed:Category 1:1；3 cat 硬编码 enum；CategoryConfig 持有 per-cat filterPrompt + recommendCount | SwiftData @Query 不支持 join，冗余 1 字段换 O(1) 过滤；3 cat 是产品决策不是数据 |
| Filter Stage 落位 | 入库后标 `accepted: Bool?`（nil/true/false）；财报 cat 必备其他 cat 可选；失败 3 次永久 reject | 入库前 filter 会每次抓 RSS 重判同一篇 reject 反复花 token；保留原始数据让 prompt 迭代时能 review |
| 协议双轨策略 | v2 阶段 PreferencesStoring / AISummarizing / UsageRecording 改协议加 cat 时保留旧无 cat fallback；**2026-05-25 (27ff4a6) 全删过渡 fallback** | 过渡期降低 phase 间耦合；过渡结束必须删，否则新增 cat 时 caller "默认落 .ai" 静默漏改 |
| RefreshService dict 化（v2 → review 后）| `@Published private(set) var states: [Category: CategoryState]`（H1 删 12 .ai shortcut + 收紧 private(set)）；公开 `markAvailability(_:for:)`；DEBUG `_testMutate`；per-cat `refreshTasks` inflight；`refreshAllCatsConcurrently`（H5）；首启 firstLaunchAfterSchemaUpgrade 仅触发 AI cat | shortcut 是过渡期遗留会让 caller 图省事丢失 per-cat 状态；并发 QPS 3×5=15 对 30 安全，冷启动 1-2 分钟 → ~30s |
| Migration 全清策略（v2）| schemaVersion="v2-multi-category" 不匹配则 nuke 旧 store + 白名单清 `com.ainewsbar.*` 业务 key（保留 API Key + Model + launchAtLogin）+ 标 firstLaunchAfterSchemaUpgrade。**review 后 (M5)** 删 sidecar 由 `try?` 改 do/catch + 区分 `fileNoSuchFile` + Log | 接受历史数据全清；白名单为保 launchAtLogin；静默删除失败会让用户数据隐性丢失 → 必须可观测 |
| CategoryTabBar 实现（v2）| HStack 3 Button 等宽替代 Picker.segmented；选中态 `unemphasizedSelectedContentBackgroundColor` + 0.5pt border + shadow + semibold | macOS Picker.segmented 按内容宽度无法等分撑满（#35）；native segmented selected 色保证明暗双适配 |
| 跨日重置 guard 简化（review 后）| shouldClearState 从 11 行 if/else 简化为 `lastResetCheckDate != nil` | guard 已排除今日 + loadPersistedState 已清非今日，原 else 分支永远 false |
| 摘要保存失败回滚（review 后）| `commitSummaries` 失败用 `context.rollback()` 替代旧手动 fetch+nil+save 舞蹈 | 手动舞蹈第二次 save 失败时内存与磁盘永久错位 |
| AI 错误分级映射（review 后）| `GlobalAIError` 新增 `.forbidden` 与 `.invalidAPIKey` 分离：401→invalidAPIKey / 403→forbidden / 429→quotaExceeded / 5xx→other / 网络→networkUnreachable | DashScope 403 常见是模型未授权，一锅炖让用户怀疑代码 bug |
| credentials 查询 CQS（review 后）| `currentCredentials()` 纯查询 + `ensureCredentials(cat:)` 显式 command | 旧 `currentCredentials(cat:)` 名似 query 实是 command（设 globalAIError + per-cat unavailable）|
| Article filter 失败状态机（review 后）| 收敛到 `Article.recordFilterFailure(maxBeforeReject:)` extension | 旧 7 行 if/else 散在 RefreshService.runFilterStage；状态机归属 model 自身 |
| Article.accepted 默认 nil（review 后）| init default 从 `true` 改 `nil`：未跑 filter 应为 nil；要跳过 filter 须显式传 `accepted: true` | 旧 default 与设计意图相悖，新建路径漏传时财报噪声泄漏到 UI |
| Category.from fallback 可观测（review 后）| 解析失败 fallback `.ai` 前 Log；nil 不报（合法首启路径） | 脏数据静默打到 AI tab 污染推荐/日报 |
| cleanupOldArticles 一致 strict（bb866b0 + bbb9234）| per-cat 与全 cat 两版 cleanupOldArticles 都改 throw；runRefresh / resetCrossedDayStateIfNeeded 失败 rollback + return + 不推进 lastResetCheckDate | tolerant cleanup 失败被当空结果继续推进 → 留 pending delete 或推进 guard 当天不再重试 |
| Timer 启动与 sync 成功解耦（bbb9234）| configure() 只注入依赖；scheduleTimer 移到 launchBackgroundRefreshIfNeeded 内部（!configured 守护）。AppDelegate sync 成功才调 launch... | sync 失败时旧路径 timer 仍 hourly 触发 → 0 文章 + lastRefreshDate 更新 → UI 显示"刚刚更新但永远是空" |
| UsageRecording 契约：失败 ⇒ tokens=0（bb866b0）| helper `record(info:success:)` 在 success=false 时强制 input/output=0；caller 仍传真实 UsageInfo 由 helper 自动丢；协议文档明确"成功生效的用量"语义 | 旧契约自相矛盾（协议说失败=0 但 helper 透传 token）；与"今日用量按 success 过滤"UI 语义对齐；caller 不用每处自己归零 |
| FeedRowView toggle guard 确定性时序（bb866b0）| catch 顺序：**先** arm guard → rollback + 改 oldValue → 末尾 `Task { @MainActor }` 兜底 reset。无论 onChange 实际触发与否 guard 都能解除 | 旧顺序 rollback 在前可能让 feed.isEnabled 已变回 oldValue → 改 oldValue 不触发 onChange → guard 永久卡 true → 吃掉下次真实 toggle |
| APISettings 失败设 globalAIError（bb866b0）| checkConnection catch 调 `GlobalAIError.from(error) ?? .other(localizedDescription)` 设 refreshService.globalAIError | 旧路径只更新行内 checkStatus，菜单 UI 仍显示旧可用状态直到下轮 refresh，违背"用户在设置页看到失败时主 UI 也应同步"语义 |
| AppDelegate syncInto 失败可见（bb866b0）| 检查 Bool 返回；失败 set globalAIError + skip launchBackgroundRefreshIfNeeded | 旧实现忽略返回值；feed 表可能空但 refresh 仍跑 → 0 文章 + lastRefreshDate 更新 |
| Auto path 并发→顺序（第四轮 review）| `refreshAllCatsConcurrently` → `refreshAllCatsSequentially`，timer/wake/launch 三入口顺序 await `refreshIfNeeded(_:)`；手动单 cat / force* 不变 | 旧 3×5=15 峰值靠 "DashScope 30 QPS" provider 不变量保护，限速调整 / key 多端共享一旦发生整次刷新失败；后台路径优先可靠性，峰值降到 5，最坏冷启动 ~1-2 分钟可接受 |
| postUnreadCount 失败保留 badge（第四轮 review）| `safeFetch` → `safeFetchOrThrow` + do/catch；失败仅 Log 不广播通知 | badge 是用户可见状态，错发 count=0 会让用户以为"全读完了"；保留上一次值是最安全的失败行为 |
| startupError 与 globalAIError 隔离（第四轮 review）| 新增 `@Published var startupError: String?`；AppDelegate syncInto 失败写 startupError 而非 globalAIError；MenuBarView banner 优先级 startup > global > per-cat | 复用 globalAIError 会被任意 AI 成功 `clearGlobalAIErrorAfterAISuccess` 静默清除；启动错误根因仍在却消失，且 UI 文案"AI 不可用"误导用户怀疑代码 bug |
| recommendCount 真正接入（第四轮 review）| BailianService.recommendArticles/makeRecommendPrompt/parseRecommendResponse + RecommendEngine 阈值 + RecommendSectionView 全部从 `CategoryConfig.for(cat).recommendCount` 取；协议加 `count: Int` 显式参数 | 旧 3 个硬编码 5 让 CategoryConfig.recommendCount 成"会撒谎的配置"；未来调单 cat 数（如新闻 3 条）只改一处即可 |
| Onboarding 断点修复（第五轮 review）| RefreshService 新增 `applyCredentialChange()`：清 globalAIError + 重置 credential 相关 per-cat unavailable → .unknown + 顺序 await refresh 三 cat。APISettings.checkConnection 成功 fire-and-forget 调用 | 旧路径：无 key 首启 runRefresh 跑到 AI 段才退出 → lastRefreshDate 已 set；用户保存 key 后 refreshIfNeeded 因 stale 阈值跳过、tab lazy load 因 lastRefreshDate 非 nil 不触发 → AI tab 摘要/推荐空白要等 30 分钟或手动刷新 |
| Feed 禁用/删除后 badge 同步（第五轮 review）| FeedRowView.handleToggle 成功路径 + FeedsSettingsView.deleteCustomFeeds 成功路径调 `refreshService.postUnreadCount(context:)` | 主列表靠 @Query 自动更新；菜单栏 badge 只靠 NotificationCenter，不主动 post 会 stale 直到下次 refresh/打开菜单 |
| AddFeedSheet URL 去重（第五轮 review）| 静态 `normalize(_:)` 小写+去尾斜杠；insert 前 fetch 全量 Feed 比对，重复弹 alert 拒绝 | 旧路径无 URL 去重，同 URL 重复 feed 会重复抓 RSS / 重复显示 / 失败统计噪声；article URL 去重只能救文章层不能救 feed 层 |
| ArticleSnapshot tolerant API 删除（第五轮 review）| 删 `capture(from:)` 与 `capture(from:category:)`（safeFetch 静默空快照），仅留 `captureOrThrow` | 生产路径已全部迁到 captureOrThrow；留着 tolerant 版本只会让后人在"DB 查询失败"和"无文章"间挖坑（踩坑 #22 同型陷阱） |
| APISettings 验后保存（第六轮 review）| saveAndCheck 先 testConnection 局部 apiKey/model，成功才 saveAPIKey/saveModel；失败时 prefs 完全不动 | 旧路径先持久化再检测；用户手滑输错就覆盖上一套可用配置，主流程开始用坏配置 |
| RSS+open 文章 scheme 校验（第六轮 review）| RSSService.fetchRawArticles 与 MenuBarView.openArticle 都 guard `scheme == "http" || "https"`；拒绝 file://、javascript:、shell: | RSS 是外部输入；NSWorkspace.open 不应被诱导打开任意 scheme |
| applyCredentialChange 精确 reason 匹配（第六轮 review）| 静态常量 `RefreshService.missingCredentialReason = "未配置 API Key"`；ensureCredentials set 该 reason，applyCredentialChange 精确比对，**只清** credential 那一条 | 第五轮注释说"non-credential 不清"但实现 set all .unavailable→.unknown；会掩盖"摘要调用多数失败/摘要保存失败"等真业务错误 |
| AddFeed strict fetch + trim + 触发 refresh（第六轮 review）| 重复检测改 `try modelContext.fetch` strict，失败弹 alert；URL/title 存盘前 trim 空白；保存成功后 fire-and-forget `service.refresh(selectedCategory)` | 旧 `try? ... ?? []` 是 false-empty 写路径；空白字符进库；添加后若该 tab 刚刷新过 lastRefreshDate 挡住 lazy refresh 让用户体感"加了没用" |
| FilterPipeline 拆 transient vs classification（第七轮 P1）| `Result` 新增 `classificationFailedIds` / `transientFailedIds` / `firstTransientGlobalError`。只有 `BailianError.malformedResponse` 计 classificationFailed→ recordFilterFailure；其他错误（HTTP 401/403/429/5xx、网络、未知）算 transient，保持 accepted=nil 下轮重试 + 设 globalAIError 提示用户 | 旧实现 `.failed(id)` 一锅炖，网络抖动/401/429 都累计 filterFailCount 3 次后永久 reject 财报文章；这是个真实数据丢失漏洞 |
| Filter 持久化后补 postUnreadCount（第七轮 P2）| runFilterStage `persistSucceeded && !writeIds.isEmpty` 时调 `postUnreadCount(context:)` | 财报文章 accepted=nil 时不计入 badge；filter 通过后 accepted=true，badge 应该立即更新；menu bar label 只听通知不补就 stale 到下次 refresh / 菜单打开 |
| 检测可用性按钮不动 globalAIError（第七轮 P3）| `checkConnection()` 完全删 set/clear globalAIError；只更新本页 checkStatus；`saveAndCheck` 仍维持成功 set/失败 set globalAIError（持久化路径） | 检测候选 ≠ 主流程持久化值；旧实现成功清/失败设 globalAIError 让候选好 key 误清主 UI 错误，或候选坏 key 误显示全局错误 |
| BuiltInFeeds 插入扫全表去重（第七轮 P3）| 新增源插入前从 `context.fetch(FetchDescriptor<Feed>())` 扫全表（含 custom）比对 URL；删除/元数据同步仍只动 built-in | 旧实现只扫 built-in，如果某 URL 被加入 built-in 时用户已有同 URL custom 源，会插入重复 feed；重复 fetch + 重复显示 + 失败统计噪声 |
| ArticleSnapshot 内存 sort by publishedAt（第八轮 P2）| `captureOrThrow` fetch 后 `articles.sorted { $0.publishedAt > $1.publishedAt }`；不用 `FetchDescriptor.sortBy` 避开 SwiftData 边界 SIGTRAP | 旧实现不带 sort 让 prompt prefix(50) / prefix(20) 切到的不一定是最新文章；AI 推荐/日报内容依赖 SwiftData 默认返回顺序 + RSS 并发完成顺序 |
| 删源后清 per-cat digest+recommend 缓存（第八轮 P2）| RefreshService 新增 `invalidatePerCatCache(for:)` 公开方法；FeedRowView.handleToggle / FeedsSettingsView.deleteCustomFeeds 成功路径调用 | 旧路径删源后只更 badge；digest 文本可能含已删源标题；recommendedArticleIDs 非空让 auto refresh 不重生（陈旧永留） |
| saveAndCheck 失败不污染 globalAIError（第八轮 P3）| `saveAndCheck` 失败 catch 删 `globalAIError = ...` 这一行；只更新本页 checkStatus | 持久化失败时 prefs 未变，主 UI 反映的应该是"当前持久化配置"，不该被未保存候选输入污染 |
| parseRecommendResponse 改正则提取（第八轮 P3）| 旧 `components(separatedBy:)` 改 `NSRegularExpression("\d+")` 匹配所有数字串；空 prompt cap 用 `count > 0 && totalCount > 0` guard | 旧实现遇 "1. 2. 3."/"[1] [2]"/"推荐：1,3,7" 等模型啰嗦输出会 split 后整数解析失败返空；正则提取数字鲁棒得多 |

---

## 构建 & 运行

```bash
cd /Users/hyf042/Projects/AINewsBar
swift build
pkill -x AINewsBar; sleep 1
cp .build/debug/AINewsBar build/AINewsBar.app/Contents/MacOS/AINewsBar
codesign --sign - --force build/AINewsBar.app
build/AINewsBar.app/Contents/MacOS/AINewsBar &
```

> **不要用 `open` 命令**（某些状态下静默失败，踩坑 #3）；**不要直接跑裸二进制**（MenuBarExtra 依赖 bundle 上下文，#4）。

## 已实现功能

完整功能清单 + 用户面向描述见 `README.md`（保持最新）。本文不重复维护。

---

## 关键文件

### App 入口
- `App/AINewsBarApp.swift` — Scene root；不持有 startup 逻辑
- `App/AppDelegate.swift` — **冷启动 entry**：`static let container` + `applicationDidFinishLaunching` 接管所有 startup + NSWorkspace.didWakeNotification 监听 + 二次失败 in-memory fallback

### Services（外观 + 组件）
- `Services/RefreshService.swift` — **外观** (~890 行 v2 多分类后)：`@Published private(set) states: [Category: CategoryState]` per-cat dict；公开 API：`refresh(_:)` / `forceRegenerate{Recommend,Digest}(_:)` / `refreshIfNeeded(_:)` / `handleSystemWake()` / `markAvailability(_:for:)` / `state(for:)` / `isSummarizing(category:)` / `stop()`；DEBUG-only `_testMutate(for:_:)`；per-cat `refreshTasks` inflight 复用；`refreshAllCatsConcurrently` TaskGroup（H5）；`runRefresh` defer + capturedFetchErrors（H3）；`commitSummaries` 用 `context.rollback()`（H2）；`currentCredentials()` / `ensureCredentials(cat:)` CQS（M3）
- `Services/SummaryPipeline.swift` — 摘要并发管道（5 路）；多点 `Task.isCancelled` checkpoint；`.cancelled` 不计 failed
- `Services/RecommendEngine.swift` / `DigestEngine.swift` — 纯执行器；Outcome 含 UsageInfo
- `Services/FilterPipeline.swift`（v2）— 5 路并发 filter；同 SummaryPipeline 结构；返回 acceptedIds / rejectedIds / failedIds + usages
- `Services/ArticleSnapshot.swift` — Sendable 值快照；`capture(from:category:)` + `captureOrThrow(from:category:)`（严格版供关键路径）
- `Services/BailianService.swift` — DashScope HTTP（曾名 ClaudeService）；显式 model 参数；`BailianError`（`.httpStatus` / `.malformedResponse` / `.insufficientCandidates`）；4 prompt 工厂 per-cat 静态方法（L1 删 .ai default）；`classifyArticle` filter API
- `Services/PreferencesService.swift` — UserDefaults 后端（曾名 KeychainService）；per-cat key 拼接 `com.ainewsbar.<base>.<cat>`；`clearDigest` / `clearRecommendState` 拆开（#16）
- `Services/ServiceProtocols.swift` — `RSSFetching` / `AISummarizing`（per-cat 显式协议无 fallback）/ `PreferencesStoring`
- `Services/RefreshDecision.swift` — 触发决策纯函数集，时钟参数注入
- `Services/RSSService.swift` — FeedKit actor；`RawArticle.publishedAt: Date?`（nil 不入库 #17）；UA + Accept header 防 403
- `Services/BuiltInFeeds.swift` — **v2: 27 内置源**；`syncInto(context:)` strict 同步 + categoryChanged 路径先改 feed 再删 articles（M2）；`deduplicateArticles` 重建容灾
- `Services/FeedSettingsStore.swift` — 集中处理 feed 启停/删除：`persistBuiltInEnabledChange` / `deleteCustomFeeds`；strict 删 articles + 失败 rollback；调用方负责 UI 状态回滚
- `Services/UsageRecording.swift` / `UsageRecorder.swift` / `UsageAggregator.swift` / `UsageFormatter.swift` — Token 用量协议/SwiftData 实现/纯函数聚合/格式化

### Models
- `Models/Article.swift` — `@Model` + category +accepted (Bool? L2 nil default) +filterFailCount +`recordFilterFailure(maxBeforeReject:)` extension（M1）
- `Models/Feed.swift` — `@Model` + category + skipFilter（v2 跳过 AI filter 的"纯净源"toggle）
- `Models/Category.swift` — 3 cat enum + `from(rawValue:)` 解析失败 Log（L3）
- `Models/CategoryConfig.swift` — per-cat 配置（filterPrompt / recommendCount）
- `Models/UsageRecord.swift` — `@Model` + category + UsageScene（含 `.filter` v2）+ UsageInfo

### Utils
- `Utils/ModelContext+Safe.swift` — 双轨 API：失败容忍版 + 严格抛出版；含调用位置日志
- `Utils/Log.swift` — `os.Logger` 包装；subsystem=`com.ainewsbar`
- `Utils/RelativeDateFormat.swift` — 纯函数 `formatArticleRelative(_:now:calendar:)` 时钟注入；用 `startOfDay(for:)` 手算 days（#32）
- `Utils/MarkdownStripper.swift` — strip `**` / `__` / 行首 `# ## ###`；保留行首 `- * +` 中文列表层次

### Views
完整列表见 `Sources/AINewsBar/Views/` 子目录（拆分 MenuBar/ + Settings/ + DesignTokens/）。Banner 区分 global vs per-cat；CategoryTabBar 用自定义 HStack 替代 macOS Picker.segmented（#35）；子 view 用 `.id(selectedTab)` 切换重建（#36）。

### 其他
- `docs/plans/optimization-plan.md` — v1 阶段 4 项重构
- `docs/plans/multi-category-redesign.md` — v2 重构 spec
- `build/AINewsBar.app` — 打包好的 .app（ad-hoc 签名）

---

## 内置订阅源

v2: 27 个 = 11 AI + 8 财报 + 8 新闻。完整列表见 `Sources/AINewsBar/Services/BuiltInFeeds.swift` 或 `README.md` § 内置订阅源。

> **中文财报源镜像依赖**：华尔街见闻 / 第一财经 / 东方财富 / 财新等官方 RSS 全部 404 或返 HTML。2026-05-25 通过 RSSHub 公共镜像 `rsshub.rssforever.com` 引入财联社头条 + 华尔街见闻全球；备用镜像 `rss.injahow.cn` 同路径可用。RSSHub 公共实例随时可能被反爬升级或下线 — known risk，可接受。

---

## 踩坑记录

每条精简为 "**根因** + **修复**"；详情见对应 commit 与代码注释。

### 1. List 里 Button 渲染空白
**根因**：MenuBarExtra(.window) + Button + .buttonStyle(.plain) + List 是 SwiftUI bug，LazyVStack+ScrollView 同样空白。**修复**：`VStack + .contentShape(Rectangle()) + .onTapGesture` 替代 Button。

### 2. SwiftData 新增非可选字段崩溃
**根因**：自动迁移不支持新增非可选属性。**修复**：catch 块删 `~/Library/Application Support/default.store*` 重建。v2 起 schemaVersion 检测主动 nuke。

### 3. `open` 命令静默失败
**修复**：`build/AINewsBar.app/Contents/MacOS/AINewsBar &` 直接启动，不用 `open`。

### 4. 裸二进制 MenuBarExtra 图标不显示
**修复**：必须放进 .app bundle（依赖 bundle 上下文 + Info.plist 的 `LSUIElement=true`）。

### 5. SwiftData @Model 不能跨 actor 传递
**根因**：跨边界使用导致静默数据丢失或崩溃。**修复**：RSSService 返回 `RawArticle: Sendable` 值类型；TaskGroup 子任务用 `SummaryTask: Sendable`，结果回 @MainActor 后按 id 重 fetch 写回。

### 6. @Query 日期谓词初始化时捕获
**根因**：`#Predicate` 里 `Date()` 在 init 时求值，不会更新。**修复**：日期过滤放 Service 层；@Query 只做 isRead / category 过滤。

### 7. SwiftData 不支持对 Bool 排序
**根因**：`SortDescriptor(\.isRead)` 编译报错（`NSObject` 限制）。**修复**：拆两个独立 @Query（isRead==false / ==true），中间插入普通行作分隔。

### 8. List Section header 带系统背景色
**根因**：`.listStyle(.plain)` 下 Section header 在浅色外观下明显偏红。**修复**：不用 Section，改普通 HStack 行 + 自定义 `.listRowBackground`。

### 9. 嵌套 HStack 中 Text 高度变化不传父容器
**根因**：lineLimit 从 1 变 nil 时文字撑高，父 HStack 不跟随。**修复**：可变高 Text 加 `.fixedSize(horizontal: false, vertical: true)`。

### 10. TaskGroup 摘要 @Model 跨边界
**修复**：进入 TaskGroup 前提取 `SummaryTask: Sendable`；完成后 @MainActor 按 id 查找原 Article 写入。（同 #5 的具体场景）

### 11. 日报 prompt 只用标题忽略摘要
**修复**：prompt 改 `"- \(title)｜\(summary)"` 格式。

### 12. `commit(DigestEngine.Outcome)` 不能重置 aiAvailability
**根因**：Recommend 失败设 .unavailable 被 Digest 成功覆盖。**修复**：Digest commit 不动 aiAvailability；Recommend 是 AI 状态主指示器。

### 13. MenuBarExtra popover view lazy 创建，`.task` 冷启动不触发
**根因**：popover 内 view 只在用户首次点击时构造，timer 永不启动。**修复**：所有 startup 挪到 `AppDelegate.applicationDidFinishLaunching`。

### 14. 多 ModelContext 导致 @Query 看不到 Service 写入
**根因**：ad-hoc context 与 SwiftUI 注入的 main context 共享容器但内存视图独立。**修复**：统一用 `AppDelegate.container.mainContext`。

### 15. `configure(with:usage:)` 默认 nil 覆盖前次注入
**根因**：两处调 configure，第二次 `usage: nil` 默认值覆盖第一次。**修复**：configure 统一为单一调用点。

### 16. `clearDigest()` 副作用扩散到推荐
**根因**：clearDigest 同时清推荐计数 key，命名说谎。**修复**：拆 `clearDigest` + `clearRecommendState`，caller 显式两次调用。

### 17. RSS pubDate 缺失伪造"现在"导致脏文章每日重生
**根因**：fallback `Date()` 使无 pubDate 的脏 URL 每天被清→次日 pubDate=now 重生循环。**修复**：`RawArticle.publishedAt: Date?`，nil 直接丢弃。

### 18. SwiftUI 内置 `Text(date, style: .relative)` 无方向且 tick
**根因**：内置 API 显示 "3 hours" 无中文方向 + tick 更新。**修复**：自定义 `formatArticleRelative(_:now:calendar:)`：刚刚/X分钟前/X小时前/昨天/N天前/M-d。

### 19. 跨日时 @Published UI 状态从未自动失效（最隐蔽 bug）
**根因**：loadPersistedState 跨日逻辑只在 configure() 跑一次；应用驻留时 @Published var dailyDigest 一直保留昨天值。**修复**：`resetCrossedDayStateIfNeeded()` 在 timer + refreshIfNeeded 双调用，清 SwiftData + @Published + prefs 三层。

### 20. `Divider().padding(.leading, 34)` 切断 RecommendItemView 左色条
**根因**：Divider 自身 1pt 高度让父容器 quaternary 背景从最左侧透出。**修复**：去 Divider，靠 RecommendItemView 自身 padding 自然分隔。心得：任何"行间分隔元素"都会占纵向空间，与"贯穿色条"冲突。

### 21. 复用单字段做 UI 显示 + 跨日 guard 会被业务路径漂白
**根因**：lastRefreshDate 被 refresh() 末尾抹掉跨日信号，guard 永远 false。**修复**：拆 `lastResetCheckDate: Date?` 专用 guard，仅 reset 内部 set。心得：状态字段双重语义必被业务漂白，分离关注点。

### 22. `safeFetch` 失败静默空集合 → 下游"假空决策"连锁
**根因**：existingURLs 假空让全部抓回文章重插；pending 假空跳过摘要；ArticleSnapshot 假空跳过推荐/日报。**修复**：双轨 API。关键路径用 `safeFetchOrThrow/safeSaveOrThrow`，caller 显式区分"真无"vs"fetch 失败"。心得：数据库场景的"默认安全值 fallback"几乎都是错的。

### 23. SwiftData @Model 跨 await 持有可能 detached
**根因**：`pending` 跨 30s+ await 期间外部操作让 Article detach，写入未定义行为。**修复**：不持有跨 await 的 @Model；commitSummaries 用 id 重 fetch alive Article。心得：@Model 引用安全寿命 = 同一 RunLoop turn。

### 24. `safeSave` 失败被吞 + prefs 仍写 → 永久数据不一致
**根因**：磁盘 aiSummary 全 nil 但 prefs 显示"已生成 N 条"，Plan A 永久错乱。**修复**：commitSummaries 用 strict save + 失败时回滚内存 + 设 .unavailable + token 记 success=false + 不写 prefs.articleCount。心得：写入失败时所有相关副作用必须一起回滚。

### 25. refresh() 与 forceRegenerate* 互不互斥导致双 commit
**根因**：双 commit 互相覆盖 + UsageRecord 双扣 token + UI 状态闪烁。**修复**：`refreshTask: Task<Void, Never>?` inflight 复用，所有入口 `await existing.value`。心得：UI flag 仅做进度显示；并发互斥用 inflight Task 字段。

### 26. `withTaskGroup` 不响应 `Task.isCancelled` 取消后仍跑完
**根因**：用户关菜单后 5 路 task 仍跑完烧 token；下次 refresh 与之并存真实并发翻倍。**修复**：三点 checkpoint（addTask 前 / for await 循环内 cancelAll / runOne 内）+ `.cancelled` 状态独立。心得：Swift Structured Concurrency 取消是协作式，TaskGroup 不自动传播。

### 27. `Dictionary(uniqueKeysWithValues:)` 容灾路径会 fatalError
**根因**：deduplicateArticles 存在证明历史出现过重复 id，一旦真出现推荐区 crash。**修复**：改 `Dictionary(_, uniquingKeysWith: { first, _ in first })`。心得：主路径强假设 + 容灾路径处理重复 = 漏洞。

### 28. fallback 选错方向：清理类 fallback `Date()` 清空整表
**根因**：cleanupOlderThan 的 `?? Date()` fallback 让 cutoff 落到现在，删空整表。**修复**：fallback 改 `.distantPast` 或 `guard let`。心得：删除/清理/reset 类 fallback 必须朝"什么都不做"方向，绝不朝"全干掉"方向。

### 29. SwiftUI @Query 不响应系统时钟，跨日午夜不重新 eval
**根因**：@Query 只对 SwiftData 变更响应，不对时钟变化响应。23:55 打开留着不关，跨零点仍显示昨日数。**修复**：`@State now: Date` + `Timer.publish(60s)` + `onReceive` 仅跨日才 set now。心得：view 自动响应数据变化 ≠ 响应时间变化。

### 30. Swift 5.9 不支持 @MainActor isolated deinit
**根因**：从 nonisolated deinit 访问 @MainActor isolated 字段编译失败；isolated deinit 是 Swift 6.2+ 特性。测试堆 N 个孤儿 timer。**修复**：暴露 `stop()`；测试 tearDown 显式调用。心得：Swift 5.x 别指望 deinit 兜底外部资源。

### 31. `@unchecked Sendable` mock 的 var 计数器并发数据丢失
**根因**：read-modify-write 无内存屏障，计数会丢，测试断言间歇性失败/虚假通过。**修复**：mock 配套加 `NSLock + withLock`。心得：`@unchecked Sendable` 是"信任 me 处理同步"的承诺，不是免责声明。

### 32. `Calendar.isDateInToday(date)` 忽略外部时钟参数
**根因**：`isDateInToday/isDateInYesterday` 内部以系统 `Date()` 锚定，完全忽略 calendar 参数，时钟注入测试失效。**修复**：用 `startOfDay(for:)` + `dateComponents` 手算 days。心得：时钟注入纯函数严禁用任何 `is*Today/Yesterday` 类便捷判定。

### 33. macOS SwiftUI `.buttonStyle(.plain) + .foregroundStyle()` 不生效
**根因**：plain Button 外层 `.foregroundStyle` 不响应，系统强行用 accentColor。**修复**：策略 A：plain Button → `.foregroundStyle` 移到 label 内 Text；策略 B：系统默认 Button → 用 `.tint()`。心得：Button 外层 modifier 给"按钮外壳"用，不是 label；任何"给按钮文字染色"默认走 label-internal。

### 34. SwiftData @Query 谓词 3 个 `&&` 让 type-checker 超时
**根因**：SwiftData 谓词 macro 展开 + Swift type-check 复杂度爆炸。**修复**：@Query 谓词只放 1 条件（category），其他过滤（isRead / accepted）放 view 层 `articles.filter`。心得：2 条件 OK 3 条件超时；数据量小时内存 filter 开销忽略。

### 35. macOS `Picker(.segmented)` 按内容宽度无法等分撑满
**根因**：与 iOS 行为不同，macOS 按需宽度（compact toolbar 设计假设）。**修复**：自定义 HStack 3 Button 等宽 + `unemphasizedSelectedContentBackgroundColor` 模仿 native selected。

### 36. SwiftUI cat-aware view 的 @State 在 cat 切换时被继承
**根因**：SwiftUI view identity 默认走类型，参数变化不触发重建。**修复**：`.id(selectedTab)` 强制重建子 view + 重置 @State。代价：每次切换重建子 view 树，菜单栏小 view 性能可忽略。

### 37. 启动期 RSS fetch 失败常见 race（DNS / 网络栈未就绪）
**根因**：AppDelegate 启动期触发 refresh 时 macOS networking 可能未就绪。**修复**：UI 标明数据时态（"⚠ 上次 X 源失败 · 点击重试"）+ 按钮直接重试当前 cat。心得：延迟启动 N 秒影响首屏；正解是标"过去时态" + 一键重试。

### 38. Atom 解析 `entry.links?.first` 可能拿到 rel=self 非文章 URL
**根因**：Atom 规范允许 `<link rel="self">` 指向 feed 自身、`<link rel="alternate">` 才是文章 HTML 链接。FeedKit 返回顺序无保证，`first` 可能拿到 rel=self URL → UI 打开文章却跳到 RSS 源本身。**修复**：`preferredAtomLink` 静态方法优先选 `rel=alternate + type=text/html`，再 fallback `rel=alternate`，最后 fallback first（兼容缺 rel 的源）。心得：标准里有多个等价语义的字段时，规范的优先级永远不能依赖第三方库的迭代顺序。

### 39. SwiftData ModelContainer 在测试中被 `let (_, context) = TestContainer.make()` 立即 ARC 释放 → context.insert SIGTRAP
**根因**：`(_, context)` 让 container 在表达式结束后立即被 ARC 释放；mainContext 底层 store 是 container 拥有的，container 释放后 context 调用任何方法（insert/save/fetch）触发 trap，xctest 报 "exited with unexpected signal code 5"，没有 stack trace 也没有断言失败信息。**修复**：`let (container, context) = TestContainer.make(); _ = container`（或挪到 setUp 让 storedProperty 保留）。心得：SwiftData ModelContext 的有效寿命强依赖 ModelContainer 的 strong reference，不像 Core Data 有显式 persistentStoreCoordinator weak/strong 选择。命名绑定别用 `_` 丢掉 container。
