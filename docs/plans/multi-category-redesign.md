# Multi-Category Redesign

> 把 AINewsBar 从单一 AI 资讯阅读器扩展为多分类（AI / 财报 / 新闻）个人资讯阅读器。
> 决策来源：2026-05-24 grill-me 16 轮访谈 + RSS URL 验证。
> 流程：单文档（spec + plan 合并）→ 用户一次 review → 6 phase 顺序实施，每 phase build + test pass 自动进下一。

---

## 1. 决策汇总（16 题）

| # | 维度 | 决策 |
|---|------|------|
| 1 | 三 tab 业务对称性 | 引擎对称（同一 SummaryPipeline / RecommendEngine / DigestEngine）+ Prompt 文案 per-cat 差异化 |
| 2 | Filter Stage 覆盖面 | 每 tab 可选（`CategoryConfig.filterPrompt: String?`）；first release 仅财报启用 |
| 3 | Filter 落位 | 入库后标 `accepted: Bool?`（nil / true / false），summary 仅跑 `accepted == true`；filter 用 `title + RSS description 前 200 字` |
| 4 | 数据模型 | Feed / Article 冗余存 `category: String`（避免 SwiftData 跨表查询）；Feed : Cat 1:1 |
| 5 | UI 形态 | 顶部 segmented control 切 tab；记忆 `selectedTab`；tab badge 未读数；Cmd+1/2/3/R；切 tab 不刷；per-tab AI banner + global API Key 错 banner；Footer 显示三 tab 总 token |
| 6 | Service 结构 | RefreshService 单实例 + `[Category: CategoryState]` dict + per-cat inflight task；timer 1h 顺序遍历 3 cat |
| 7 | Filter Pipeline | 单篇 5 并发（mirror SummaryPipeline）+ per-feed `skipFilter` toggle + 失败 3 次永久 reject；输出 "是"/"否" + `max_tokens=10` + `temperature=0.1` |
| 8 | Settings | 订阅源 / 用量 Tab 加顶部 Picker 切 cat；API / 通用 Tab 不变；AddFeedSheet 加 cat Picker；skipFilter toggle 仅财报 / 新闻显示 |
| 9 | Prefs Key | `com.ainewsbar.<base>.<cat>` 拼接后缀；PreferencesStoring 协议 per-cat 方法加 `for cat: Category` 参数 |
| 10 | 内置源清单 | AI 11（不动）+ 财报 8（6 en + 2 zh）+ 新闻 8（4 en + 4 zh）= 27；一起上线 |
| 11 | 测试策略 | Cat-agnostic 用 `.ai` 覆盖通用逻辑 + Cat-specific 单独测；新增 ~38 case，总 ~200 case |
| 12 | Migration | `schemaVersion` 检测；不匹配则全清 store + prefs（仅保留 API Key + Model）|
| 13 | Timer + Force 并发 | Force 不阻塞 timer 顺序遍历（per-cat inflight 互斥即可，跨 cat 并发对 DashScope 30 QPS 安全）|
| 14 | 首次启动 UX | 只触发 AI cat refresh，财报 / 新闻 lazy on first tab switch；后续 1h timer 覆盖全部 |
| 15 | AI Banner | 区分 global error（API Key / 网络）vs cat-specific 业务错；global banner 顶部 sticky，per-cat banner 在 tab 内 |
| 16 | 菜单栏 Badge & Cmd+R | 总未读数（三 cat 累加）；Cmd+R 仅刷新当前 tab |

---

## 2. Schema 变更

### 2.1 Category enum（新建）

```swift
// Sources/AINewsBar/Models/Category.swift
enum Category: String, CaseIterable, Codable, Sendable {
    case ai, earnings, news

    var displayName: String {
        switch self {
        case .ai: return "AI"
        case .earnings: return "财报"
        case .news: return "新闻"
        }
    }
}
```

### 2.2 Article 字段新增（3 个）

```swift
@Model
final class Article {
    // 现有字段 ...

    var category: String         // = Category.rawValue（冗余 from Feed，写入时 RefreshService 保证一致）
    var accepted: Bool?          // nil/未分类  true/通过  false/拒绝
    var filterFailCount: Int     // filter 失败 ≥3 自动 accepted=false 永久 reject

    // init: category 必填；accepted=nil；filterFailCount=0
}
```

**accepted 默认值规则**：
- 未配 filter 的 cat（AI tab + skipFilter feed）：入库时立刻 `accepted = true`
- 配 filter 的 cat：入库时 `accepted = nil`，等 FilterPipeline 跑完写入 true/false

### 2.3 Feed 字段新增（2 个）

```swift
@Model
final class Feed {
    // 现有字段 ...

    var category: String         // = Category.rawValue
    var skipFilter: Bool         // 仅财报/新闻 cat 有效；true 时入库 accepted 直接为 true
}
```

### 2.4 UsageRecord + UsageScene 扩展

```swift
enum UsageScene: String, CaseIterable, Sendable {
    case summary, recommend, digest
    case filter   // 新增
}

@Model
final class UsageRecord {
    // 现有字段 ...

    var category: String         // = Category.rawValue
}
```

### 2.5 CategoryConfig（新建）

```swift
// Sources/AINewsBar/Models/CategoryConfig.swift
struct CategoryConfig {
    let category: Category
    let filterPrompt: String?        // nil 表示该 cat 不跑 filter
    let recommendCount: Int          // 默认 5

    /// 内置硬编码配置，3 cat 各一项
    static let all: [Category: CategoryConfig] = [...]
}
```

注：Summary / Recommend / Digest prompt 通过 `BailianService.makeXxxPrompt(category:)` 内部 switch 选择，**不进 CategoryConfig**（prompt 是 BailianService 内部细节，外暴露 API contract）。

### 2.6 Prefs key 命名规范

模板：`com.ainewsbar.<base>.<category>`

**per-cat key**（base 沿用现有命名）:
- `dailyDigest.<cat>`
- `dailyDigestDate.<cat>`
- `digestArticleCount.<cat>`
- `recommendDate.<cat>`
- `recommendArticleCount.<cat>`
- `lastRefreshDate.<cat>`

**全局 key**（不动）:
- `com.ainewsbar.claude-api-key`
- `com.ainewsbar.model`
- `lastResetCheckDate`
- 开机启动

**新增全局 key**（UI 状态记忆）:
- `selectedTab`（默认 `.ai`）
- `settingsFeedsTab`（默认 `.ai`）

### 2.7 PreferencesStoring 协议改造

```swift
protocol PreferencesStoring: AnyObject {
    // 全局（不变）
    func getAPIKey() -> String?
    func getModel() -> String

    // 新增全局（UI 状态记忆）
    func loadSelectedTab() -> Category
    func saveSelectedTab(_ cat: Category)
    func loadSettingsFeedsTab() -> Category
    func saveSettingsFeedsTab(_ cat: Category)

    // per-cat（旧方法加 for cat 参数；命名沿用现有 load/save 风格）
    func loadDigest(for cat: Category) -> (content: String, date: Date)?
    func saveDigest(content: String, date: Date, for cat: Category)
    func clearDigest(for cat: Category)
    func clearRecommendState(for cat: Category)
    func loadDigestArticleCount(for cat: Category) -> Int
    func saveDigestArticleCount(_ count: Int, for cat: Category)
    func loadRecommendArticleCount(for cat: Category) -> Int
    func saveRecommendArticleCount(_ count: Int, for cat: Category)
}
```

### 2.8 AISummarizing 协议扩展

```swift
protocol AISummarizing: Sendable {
    // 现有 3 方法签名加 category 参数（影响 prompt 选择）
    func generateSummary(title: String, content: String?, category: Category, apiKey: String, model: String)
        async throws -> (summary: String, usage: UsageInfo)

    func recommendArticles(_ items: [ArticleSnapshot.Item], category: Category, apiKey: String, model: String)
        async throws -> (ids: [UUID], usage: UsageInfo)

    func generateDigest(items: [ArticleSnapshot.Item], category: Category, apiKey: String, model: String)
        async throws -> (content: String, usage: UsageInfo)

    // 新增
    func classifyArticle(title: String, description: String, prompt: String, apiKey: String, model: String)
        async throws -> (accepted: Bool, usage: UsageInfo)
}
```

### 2.9 UsageRecording 协议扩展

```swift
protocol UsageRecording: AnyObject {
    func record(scene: UsageScene, category: Category, model: String, info: UsageInfo, success: Bool)
    func cleanupOlderThan(days: Int)
}
```

### 2.10 Migration

```swift
// AppDelegate.makeContainer 改造
private static let currentSchemaVersion = "v2-multi-category"

static let container: ModelContainer = {
    let url = ApplicationSupport.appendingPathComponent("default.store")
    let defaults = UserDefaults.standard
    let storedVersion = defaults.string(forKey: "schemaVersion")

    if storedVersion != currentSchemaVersion {
        // 保留 API Key + Model
        let apiKey = defaults.string(forKey: "com.ainewsbar.claude-api-key")
        let model  = defaults.string(forKey: "com.ainewsbar.model")

        // 全清旧 store（含 -shm / -wal）
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: url.appendingPathExtension("-shm"))
        try? FileManager.default.removeItem(at: url.appendingPathExtension("-wal"))

        // 全清旧 prefs domain
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainewsbar"
        defaults.removePersistentDomain(forName: bundleID)

        // 恢复保留项
        if let apiKey { defaults.set(apiKey, forKey: "com.ainewsbar.claude-api-key") }
        if let model  { defaults.set(model,  forKey: "com.ainewsbar.model") }
        defaults.set(currentSchemaVersion, forKey: "schemaVersion")

        // 标记首次启动（供 Phase 4 launchBackgroundRefreshIfNeeded 用）
        defaults.set(true, forKey: "firstLaunchAfterSchemaUpgrade")
    }

    return try! ModelContainer(for: Feed.self, Article.self, UsageRecord.self, ...)
}()
```

---

## 3. 内置源清单（27 finalize，已 curl 验证）

### 3.1 AI tab（11 - 沿用现有）

| # | 源 | URL |
|---|----|-----|
| 1 | OpenAI News | https://openai.com/news/rss.xml |
| 2 | Google DeepMind | https://deepmind.google/blog/rss.xml |
| 3 | Hugging Face Blog | https://huggingface.co/blog/feed.xml |
| 4 | TechCrunch AI | https://techcrunch.com/category/artificial-intelligence/feed/ |
| 5 | The Verge AI | https://www.theverge.com/rss/ai-artificial-intelligence/index.xml |
| 6 | Ars Technica AI | https://arstechnica.com/ai/feed |
| 7 | The Decoder | https://the-decoder.com/feed/ |
| 8 | MIT Technology Review | https://www.technologyreview.com/topic/artificial-intelligence/feed |
| 9 | VentureBeat AI | https://venturebeat.com/category/ai/feed/ |
| 10 | TLDR AI | https://tldr.tech/api/rss/ai |
| 11 | 量子位 | https://www.qbitai.com/feed |

### 3.2 财报 tab（8 - 6 en + 2 zh）

| # | 源 | URL | 语言 |
|---|----|-----|------|
| 1 | Seeking Alpha | https://seekingalpha.com/feed.xml | en |
| 2 | Apple Newsroom | https://www.apple.com/newsroom/rss-feed.rss | en |
| 3 | CNBC Top News | https://www.cnbc.com/id/100727362/device/rss/rss.html | en |
| 4 | Bloomberg Markets | https://feeds.bloomberg.com/markets/news.rss | en |
| 5 | Yahoo Finance | https://finance.yahoo.com/news/rssindex | en |
| 6 | MarketWatch | https://feeds.marketwatch.com/marketwatch/topstories/ | en |
| 7 | FT Chinese Finance | https://www.ftchinese.com/rss/feed | zh |
| 8 | 雪球热门 | https://xueqiu.com/hots/topic/rss | zh |

### 3.3 新闻 tab（8 - 4 en + 4 zh）

| # | 源 | URL | 语言 |
|---|----|-----|------|
| 1 | BBC News | https://feeds.bbci.co.uk/news/rss.xml | en |
| 2 | NYT World | https://rss.nytimes.com/services/xml/rss/nyt/World.xml | en |
| 3 | Hacker News Top | https://hnrss.org/frontpage | en |
| 4 | The Verge | https://www.theverge.com/rss/index.xml | en |
| 5 | 36 氪 | https://36kr.com/feed | zh |
| 6 | 新华网 | http://www.xinhuanet.com/politics/news_politics.xml | zh |
| 7 | 人民日报 | http://www.people.com.cn/rss/politics.xml | zh |
| 8 | FT Chinese News | https://www.ftchinese.com/rss/news | zh |

---

## 4. Prompt 文案定稿

### 4.1 Summary Prompts × 3

通用约束：强制中文回复 + 50 字内 + 纯文本（防 markdown 噪声，沿用踩坑 #26 双约束模式）。

**AI**:
```
请用中文一句话（不超过50字）概括以下 AI / 科技资讯的核心内容（如新模型发布、能力突破、关键观点），无论原文是何种语言，必须用中文回复。请用纯文本回复，不要使用 markdown 语法（不要使用 **、##、- 等符号）：

标题：<title>
内容：<content prefix 1500>
```

**财报**:
```
请用中文一句话（不超过50字）概括以下财经资讯的核心内容（如财报数据、营收/EPS、业绩指引、关键决策），无论原文是何种语言，必须用中文回复。请用纯文本回复，不要使用 markdown 语法（不要使用 **、##、- 等符号）：

标题：<title>
内容：<content prefix 1500>
```

**新闻**:
```
请用中文一句话（不超过50字）概括以下新闻的核心内容（如时政事件、社会动态、关键决策），无论原文是何种语言，必须用中文回复。请用纯文本回复，不要使用 markdown 语法（不要使用 **、##、- 等符号）：

标题：<title>
内容：<content prefix 1500>
```

### 4.2 Digest Prompts × 3

**AI**（沿用现有，含 markdown 双约束）:
```
以下是今日 AI 资讯（标题｜摘要），请用中文写 2-3 句话概括今日最重要的 AI 进展。必须用中文回复。请用纯文本回复，不要使用 markdown 语法（不要使用 **、##、- 等符号）：

<lines>
```

**财报**:
```
以下是今日财经资讯（标题｜摘要），请用中文写 2-3 句话概括今日最重要的财报与公司动态，重点关注哪些公司发布业绩、关键数据如何。必须用中文回复。请用纯文本回复，不要使用 markdown 语法（不要使用 **、##、- 等符号）：

<lines>
```

**新闻**:
```
以下是今日新闻（标题｜摘要），请用中文写 2-3 句话概括今日最重要的国际国内动态。必须用中文回复。请用纯文本回复，不要使用 markdown 语法（不要使用 **、##、- 等符号）：

<lines>
```

### 4.3 Recommend Prompts × 3

**AI**:
```
以下是今日 AI 资讯列表（标题｜摘要），请从中挑选 5 篇最值得 AI 从业者阅读的文章，并按推荐度由高到低排序。只返回序号，用英文逗号分隔，不要其他内容，例如：7,2,15,9,4

<list>
```

**财报**:
```
以下是今日财经资讯列表（标题｜摘要），请从中挑选 5 篇对个人投资者最有参考价值的文章（重点是知名公司财报、业绩超预期/不达预期、重要并购/人事），按推荐度由高到低排序。只返回序号，用英文逗号分隔，不要其他内容，例如：7,2,15,9,4

<list>
```

**新闻**:
```
以下是今日新闻列表（标题｜摘要），请从中挑选 5 篇最重要的新闻（重点是国际国内重大事件、影响广泛的决策），按推荐度由高到低排序。只返回序号，用英文逗号分隔，不要其他内容，例如：7,2,15,9,4

<list>
```

### 4.4 Filter Prompt × 1（仅财报）

```
判断下列文章是否属于"公司财报类"。

通过条件（任一即通过）：
- 单家公司的财报发布、业绩预告
- 营收 / EPS / 毛利率 / 业绩指引
- 重要并购、股东大会、重要人事变动

拒绝条件：
- 宏观经济、行业综述
- 第三方分析、市场点评、政策解读
- 单纯股价涨跌、技术分析

标题：<title>
描述：<description prefix 200>

仅回复"是"或"否"，不要其他内容。
```

**LLM 输出解析（`parseFilterResponse`）**：

```swift
static func parseFilterResponse(_ response: String) -> Bool? {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return nil }  // 空响应 → nil 重试
    switch first {
    case "是": return true
    case "否": return false
    default: return nil  // 解析失败 → caller 走 filterFailCount++ 路径
    }
}
```

---

## 5. Phase 拆分 + 验收（6 个）

### Phase 1 — Schema + Migration + 内置源注入

**Goal**: 新 schema 落地 + 旧数据全清 + 27 源入库

**改动文件**（~6）:
- `Models/Category.swift` (新建)
- `Models/Article.swift` (+ category / accepted / filterFailCount)
- `Models/Feed.swift` (+ category / skipFilter)
- `Models/UsageRecord.swift` (+ category；UsageScene + `.filter`)
- `Services/BuiltInFeeds.swift` (扩展 27 源含 category，syncInto 按 cat 处理)
- `App/AppDelegate.swift` (`makeContainer` + `schemaVersion` 检测 + 全清逻辑 + `firstLaunchAfterSchemaUpgrade` 标记)

**验收**:
- `swift build` pass
- 启动后旧 store + 旧 prefs 全清（仅保留 API Key + Model）
- SwiftData 看到 27 个内置 Feed 入库（11 AI / 8 财报 / 8 新闻）
- Article / UsageRecord 新字段可读写

---

### Phase 2 — CategoryConfig + Prefs per-cat

**Goal**: per-cat 配置定型 + Prefs 协议全面 cat 参数化

**改动文件**（~4）:
- `Models/CategoryConfig.swift` (新建)
- `Services/ServiceProtocols.swift` (PreferencesStoring 协议 cat 参数化 + 新增 selectedTab / settingsFeedsTab)
- `Services/PreferencesService.swift` (实现侧 key 拼接 helper + 安全 fallback)
- 测试 fixture: `InMemoryPrefs` per-cat 字典实现

**验收**:
- `swift test` 通过 PreferencesService + 调用方所有现有测试（per-cat 参数沿全链路传递）
- 新增 ~5 case 验证 per-cat 隔离（clearDigest 单 cat / selectedTab 持久化 / Category.rawValue 安全 fallback）
- CategoryConfig.all 含 3 cat 完整配置

---

### Phase 3 — FilterPipeline + Engines 接入 Category

**Goal**: 新 FilterPipeline 落地 + 3 引擎全部加 cat 参数 + AI 接口扩展 classifyArticle

**改动文件**（~8）:
- `Services/FilterPipeline.swift` (新建 ~80 行, mirror SummaryPipeline)
- `Services/BailianService.swift` (新增 `classifyArticle` / `makeFilterPrompt` / `parseFilterResponse` 静态方法 + 3 个 `makeXxxPrompt` 加 cat 参数)
- `Services/ServiceProtocols.swift` (AISummarizing + classifyArticle + 3 方法加 cat 参数)
- `Services/SummaryPipeline.swift` (Task 增加 cat 字段；调用 BailianService 传 cat)
- `Services/RecommendEngine.swift` (run 加 cat 参数透传)
- `Services/DigestEngine.swift` (同上)
- `Services/UsageRecording.swift` + `Services/UsageRecorder.swift` (record 加 cat 参数；implementation 写 cat 字段)
- `Services/UsageAggregator.swift` (`todayStats` 加 cat filter 可选参数；UI 用)

**验收**:
- 新增 ~13 case：FilterPipelineTests（8: accepted / rejected / 失败 3 次永久 reject / cancel / skipFilter feed / max_tokens=10 / temperature 0.1 / 解析容错）+ BailianServiceFilterTests（5: prompt 构造 / "是"/"否"解析 / "是的" 容错 / 空响应 / "请用纯文本"约束）
- 现有测试通过（cat 参数传递正确）

---

### Phase 4 — RefreshService dict 化 + per-cat 协同

**Goal**: RefreshService 单实例 + per-cat 状态 + per-cat inflight + timer 顺序遍历 + 首次启动 AI-only + 跨日全 cat 遍历

**改动文件**（~3）:
- `Services/RefreshService.swift` (`states: [Category: CategoryState]` / `state(for:)` / `mutate(_:_:)` / 3 个入口加 cat 参数 / `refreshTasks: [Category: Task]` / `launchBackgroundRefreshIfNeeded` 首次 AI-only / `resetCrossedDayStateIfNeeded` for all cats / timer fire 顺序 `for cat in Category.allCases` / `postUnreadCount` 三 cat 累加 / `globalAIError` per-tab vs global 区分)
- `Services/RefreshDecision.swift` (decision 函数加 cat 参数；prefs 调用传 cat)
- `App/AppDelegate.swift` (configure 接 `prefs.loadSelectedTab()`；首次启动检测 `firstLaunchAfterSchemaUpgrade` 标记并仅触发 AI cat refresh)

**验收**:
- 新增 ~6 case：per-cat 状态隔离 / force 不动其他 cat / timer 顺序遍历 / 跨日 for all cats / 首次启动只跑 AI / cross-cat 并发 (force vs timer 不阻塞)
- 启动验证：build & run，三 cat 数据分别正确存储；切 cat tab 状态不串

---

### Phase 5 — UI: Segmented Control + Settings 重构

**Goal**: 主 popover 加 segmented + per-cat view；Settings 4 Tab 重构

**改动文件**（~10）:
- `Views/MenuBarView.swift` (顶部 segmented + selection state + `@AppStorage` 或 prefs 桥接 + global API Key 错 banner + Cmd+1/2/3/R 快捷键)
- `Views/MenuBar/HeaderView.swift` (按 selectedTab 显示标题 / unread count)
- `Views/MenuBar/FooterView.swift` (今日 X tokens 三 cat 总和 - 用 `UsageAggregator.todayStats(records, now:, category: nil)`)
- `Views/MenuBar/DigestSectionView.swift` (按 selectedTab 取 `service.state(for:).dailyDigest`)
- `Views/MenuBar/RecommendSectionView.swift` (按 selectedTab 取 state；显示 5 篇 — 与 `BailianService.recommendArticles` 已是 5 篇对齐，**修正 CLAUDE.md 错记录的 "3 篇"**)
- `Views/Settings/FeedsSettingsView.swift` (顶部 Picker + 范围内"检测全部" + `prefs.saveSettingsFeedsTab` 记忆)
- `Views/Settings/FeedRowView.swift` (skipFilter toggle 仅财报/新闻显示)
- `Views/Settings/AddFeedSheet.swift` (Category Picker + default = 当前 picker 选中)
- `Views/Settings/UsageSettingsView.swift` (顶部 Picker "全部 / AI / 财报 / 新闻" + filter 数据可见)
- `Views/MenuBar/AIUnavailableBannerView.swift` (新建或就地：区分 global vs per-cat 错误)

**验收**:
- 三 tab 切换正常；Cmd+1/2/3 切 tab；Cmd+R 仅刷新当前 tab
- Settings 4 Tab 切换不丢状态；新增源时 category 选择正确
- 全 UI 沿用现有 token 体系（BrandColor / TextColor / Typography）
- 启动验证：实际操作三 tab 体验流畅，badge 数字正确，AI 推荐 5 篇

---

### Phase 6 — 集成验证 + 测试补完

**Goal**: 全部测试补齐 + 三 tab 实际跑通端到端

**改动文件**:
- 任何 Phase 1-5 漏写的测试（目标新增 ~38 case，总 ~200）
- CLAUDE.md 同步更新（AI 推荐 3 → 5 修正 + multi-category 增量段落）
- 集成测试 fixture 调整

**验收**:
- `swift test` 全部 pass（~200 case）
- 启动后三 tab 各自完成 RSS 抓取 → filter → summary → recommend → digest 全链路
- 跨日重置 + 首次启动 AI-only + 用户切 tab lazy load 路径全部手动验证
- AI banner global vs per-cat 显示正确
- Footer "今日 X tokens" 三 cat 累加正确
- 用量 Tab 三 cat 数据分别正确（含 `.filter` scene）

---

## 6. 已知 Limitations

| Limitation | 说明 | 缓解 |
|------------|------|------|
| **中文财报 RSS 稀缺** | 华尔街见闻 / 第一财经 / 东方财富 / 财新 / 财联社 等官方 RSS 全部 404 或返 HTML；仅 FT Chinese + 雪球热门 2 个标准 RSS 可用 | 财报 tab 比例妥协为 6 en + 2 zh；用户可在 first release 后加自定义中文源补足（如自部署 RSSHub）|
| **Sina 自定义 XML 格式** | 新浪财经 API 返回 `<root><result><data>` 格式而非 `<rss><channel><item>` 标准 RSS，FeedKit 无法解析 | 排除新浪系内置源；未来若需要可单独写 parser（不在本次 scope）|
| **API Key 仍存 UserDefaults** | 非 Keychain 存储 | 个人工具 + ad-hoc 签名 trade-off，避免弹授权窗口；known design decision，不改 |
| **第三方代发 RSS** | 部分中文源（如 ThePaper.cn 通过 feedx.net）稳定性次于官方 | 首发不内置；用户可手动加 |
| **首次启动 27 源全抓时间** | 27 源 + filter + summary 估计 30-90s（AI tab 只跑 11 源约 30s）| 首次只触发 AI cat（首屏体验关键）；财报 / 新闻 lazy on first tab switch；后续 1h timer 覆盖全部 |
| **TaskGroup 并发取消语义** | Swift Structured Concurrency 协作式取消，需多点 checkpoint | FilterPipeline 与 SummaryPipeline 同模式：addTask 前 / for-await loop / runOne 内部 await 前后 都检查 `Task.isCancelled` |

---

## 7. 实施约束

- 每 phase build + test pass 才进下一 phase
- Phase 5 UI 大改后**停下来等用户体验确认**（其他 phase 自动推进）
- 遇 spec 没覆盖的边界 case 立刻 ask，不擅自决定
- 不做 superpowers 多轮 architect / code reviewer subagent dispatch（除非真遇到设计争议）
- 实施时用 TodoWrite 即时跟踪 phase 内 sub-tasks
- commit 频率：每 phase 一个 commit（commit message 含 phase 编号）

---

## 8. 决策记录追溯

完整 grill 过程见 conversation history（2026-05-24 session）。本文档为决策快照，实施中如有偏离需更新此文档对应章节并 commit。
