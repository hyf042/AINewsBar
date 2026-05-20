# AINewsBar — Claude 工作记录

## 项目背景

macOS 菜单栏 AI 资讯阅读器。通过 `/grill-me` 技术访谈定义设计决策，从零完成全部实现（截至 2026-05-20 所有功能已完成并可运行）。当日通过第二次 `/grill-me` 16 轮访谈完成 4 项 ROI 最高的重构（错误治理/视图拆分/外观模式/全表 fetch 优化），详见 `docs/plans/optimization-plan.md`。

**位置：** `/Users/hyf042/Projects/AINewsBar`  
**性质：** 个人工具，Swift Package Manager，macOS 14+，无 Xcode project 文件

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

> **不要用 `open` 命令**——在某些状态下会静默失败，进程不启动。  
> **不要直接跑裸二进制**——MenuBarExtra 依赖 bundle 上下文和 Info.plist 的 `LSUIElement=true`。

---

## 已实现功能（持续迭代中，最后更新 2026-05-20）

**核心功能**
1. RSS 抓取，11 个内置源，**全并发抓取**，每小时刷新，只保留当天文章，过期自动清理
2. AI 单篇摘要：最多 5 并发生成，使用前 1500 字符内容，强制中文，无论原文语言
3. 今日 AI 资讯摘要：基于标题+摘要生成 2-3 句概述，悬停临时展开/点击固定展开，max_tokens=300；含手动刷新按钮
4. AI 今日推荐：AI 挑选 3 篇，基于标题+摘要综合判断，附摘要，不受已读状态影响；含手动刷新按钮
5. 推荐区/摘要区**骨架占位**：未生成时显示灰条 + "生成中…" 提示
6. 已读文章显示在列表底部（"已读 (n)" 分隔行），标题色降低；Header 显示 [未读/总数]
7. 订阅源开关：设置页 Toggle，关闭时删除该源文章
8. 去重：refresh 时跨批次双重去重（existingURLs + seenURLs）；ModelContainer 重建后容灾去重（`BuiltInFeeds.deduplicateArticles`）；正常启动不再扫全表
9. Footer：最后更新精确时间 + feed 失败数提示（橙色，点击跳设置）+ 设置 + 退出

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
| `App/AINewsBarApp.swift` | ModelContainer + SwiftData 迁移失败自动重建（含容灾 `BuiltInFeeds.deduplicateArticles`）；Scene root 注入 `.environmentObject(refreshService)` |
| `App/AppDelegate.swift` | 隐藏 Dock 图标 |

### Services（外观 + 组件）
| 文件 | 说明 |
|------|------|
| `Services/RefreshService.swift` | **外观** (~388 行)：聚合 @Published UI 状态 + 编排 RSS/Pipeline/Engine + 原子 `commit(Outcome)`；`refresh` / `forceRegenerateRecommend` / `forceRegenerateDigest` 三个公开入口；force/auto 路径通过 Trigger enum 合一，零重复代码 |
| `Services/SummaryPipeline.swift` | 摘要并发管道：`run(tasks:apiKey:model:) -> Result` 有界并发（5 路），返回 `completed/total` 由外观回写 SwiftData |
| `Services/RecommendEngine.swift` | AI 推荐生成：`run(trigger:snapshot:apiKey:model:) -> Outcome?`；`Trigger.auto(...) / .forced` 枚举区分决策路径 |
| `Services/DigestEngine.swift` | 今日日报生成：同 RecommendEngine 对称结构 |
| `Services/ArticleSnapshot.swift` | Sendable 值类型，封装一次性快照；`pickInputs / summarizedPairs / summarizedCount` 三种投影供 Engine 复用 |
| `Services/BailianService.swift` | DashScope HTTP 调用（曾名 ClaudeService.swift）；方法签名带 `model: String` 显式参数（不再读 prefs 单例）；含 `BailianError` 自定义错误；prompt 构造与序号解析为可单测的静态方法 |
| `Services/PreferencesService.swift` | UserDefaults 后端（曾名 KeychainService），构造可注入 UserDefaults 以便测试隔离；conform `PreferencesStoring`；含模型/日报内容/日报生成时间/推荐摘要数/日报摘要数持久化 |
| `Services/ServiceProtocols.swift` | `RSSFetching` / `AISummarizing`（含 model 参数）/ `PreferencesStoring`（含 getModel） |
| `Services/RefreshDecision.swift` | 触发决策纯函数集：`completionRate` / `shouldRegenerateRecommend` / `shouldRegenerateDigest` / `withinRegenerationWindow`；时钟通过 `now:` 参数注入 |
| `Services/RSSService.swift` | FeedKit 包装 actor；返回 `RawArticle: Sendable` 跨 actor 边界 |
| `Services/BuiltInFeeds.swift` | 11 个内置源数据 + `syncInto(context:)`（启动时同步）+ `deduplicateArticles(context:)`（重建路径容灾） |

### Views（拆分后子目录）
| 文件 | 说明 |
|------|------|
| `Views/MenuBarView.swift` | 主视图框架 (169 行)：两个独立 @Query + body 组合 + 辅助 view（loading/empty/error/banner）+ openArticle |
| `Views/ArticleRowView.swift` | 文章行；用 `onTapGesture` 而非 `Button`（见踩坑 #1） |
| `Views/SettingsView.swift` | 仅 TabView 容器 (15 行) |
| `Views/MenuBar/HeaderView.swift` | 标题 + 未读计数 + 刷新按钮 |
| `Views/MenuBar/FooterView.swift` | 最后更新 + feed 失败数 + 设置/退出 |
| `Views/MenuBar/DigestSectionView.swift` | 今日日报区，含 `@State isExpanded/isHovered` |
| `Views/MenuBar/RecommendSectionView.swift` | AI 推荐区；**复用 `unreadArticles + readArticles` 内存查找**（O(n) + 保序，零 IO） |
| `Views/MenuBar/RecommendItemView.swift` | 单条推荐 |
| `Views/Settings/CheckStatus.swift` | `CheckStatus` enum + `CheckStatusIcon` 通用组件 |
| `Views/Settings/FeedRowView.swift` | `FeedRowView` + `BuiltInFeedRowView`（Toggle + handleToggle） |
| `Views/Settings/FeedsSettingsView.swift` | RSS 源列表 + 行内/批量检测 |
| `Views/Settings/AddFeedSheet.swift` | 添加自定义源（validation + force-add alert） |
| `Views/Settings/APISettingsView.swift` | API Key + 模型选择 + 可用性检测 |
| `Views/Settings/GeneralSettingsView.swift` | 开机启动开关 |

### Utils
| 文件 | 说明 |
|------|------|
| `Utils/ModelContext+Safe.swift` | `safeFetch / safeSave / safeFetchCount` 扩展，失败 Log 到 `[DB] file:line — error`，替代 `try? context.*` |
| `Utils/Log.swift` | 日志写到 `~/Downloads/AINewsBar-debug.log` |

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
