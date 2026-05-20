# AINewsBar 代码优化执行计划

**生成时间**: 2026-05-20  
**方案来源**: `/grill-me` 16 轮访谈逐分支决策  
**范围**: 4 项 ROI 最高的重构 (#1 / #2 / #4 / #5)  
**目标**: 拆解超大类、消除全表 fetch 热路径、统一错误可观察性、解除单例耦合，整体不增加功能。

---

## 0. 全局原则

- **不破坏 UI**：行为完全不变，用户感知 0 差异
- **不增加新功能**：仅结构性重构
- **可测试性优先**：每个新组件都必须可独立单测
- **遵循 KISS / YAGNI**：拒绝过度抽象（拒绝了 4 类拆 / 全局 toast / @Observable 升级等更"工程"的方案）
- **回归保护**：现有 6 个测试文件 (`RefreshServiceTests` 等) 必须全绿；视情况补充新测试

---

## 执行顺序

```
#5 错误吞噬 (机械低风险)
    ↓
#2 视图拆分 (独立工作)
    ↓
#1 RefreshService 拆分 (架构核心)
    ↓
#4 全表 fetch 优化 (在新架构里收尾)
```

理由：
- #5 是横切、最低风险，先做能让后续重构在更可观察的环境下进行
- #2 与 #1 独立，先做 #2 避免 #1 完成后再大改视图
- #1 涉及 RefreshService 内部结构，#4 的 ArticleSnapshot 是 #1 的自然产物
- #4 残余项放最后做收尾

---

# #5 错误吞噬治理

## 决策摘要

| 决策点 | 选择 |
|--------|------|
| 治理方式 | `ModelContext+Safe` 扩展统一 `safeFetch/safeSave` |
| UI 反馈 | 不引入；Log 集中 |

## 文件清单

**新增 1 个**:
- `Sources/AINewsBar/Utils/ModelContext+Safe.swift` (~35 行)

**修改 3 个**:
- `Sources/AINewsBar/Services/RefreshService.swift` (替换 12 处)
- `Sources/AINewsBar/Views/MenuBarView.swift` (替换 8 处)
- `Sources/AINewsBar/Views/SettingsView.swift` (替换 5 处)

## 实施步骤

1. **新建 `ModelContext+Safe.swift`**：

```swift
import Foundation
import SwiftData

extension ModelContext {
    @discardableResult
    func safeSave(file: String = #fileID, line: Int = #line) -> Bool {
        do { try save(); return true }
        catch {
            Log.write("[DB] save failed at \(file):\(line) — \(error)")
            return false
        }
    }
    
    func safeFetch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        file: String = #fileID, line: Int = #line
    ) -> [T] {
        do { return try fetch(descriptor) }
        catch {
            Log.write("[DB] fetch failed at \(file):\(line) — \(error)")
            return []
        }
    }
    
    func safeFetchCount<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        file: String = #fileID, line: Int = #line
    ) -> Int {
        do { return try fetchCount(descriptor) }
        catch {
            Log.write("[DB] fetchCount failed at \(file):\(line) — \(error)")
            return 0
        }
    }
}
```

2. **机械替换**（语义不变）：

```
try? context.fetch(D)                  → context.safeFetch(D)
(try? context.fetch(D)) ?? []          → context.safeFetch(D)
((try? context.fetch(D)) ?? []).map…   → context.safeFetch(D).map…
try? context.save()                    → context.safeSave()
try? context.fetchCount(D)             → context.safeFetchCount(D)
(try? context.fetchCount(D)) ?? 0      → context.safeFetchCount(D)
```

3. **手工确认** AI 调用相关的 `try?`（如 `try? await ai.generateSummary(...)`）保留——这些已有 `Log.write("[Summary] failed: ...")`，不必改动。

## 测试影响

- 无新增测试
- 现有测试不应受影响（语义未变）
- 测试时可注入 `InMemoryPrefs` 类似的 `failingContext` mock 用于验证 Log 行为（可选）

## 验收标准

- [ ] 项目内不再有 `try? .*context\.(fetch|save|fetchCount)` 匹配（grep 验证）
- [ ] `~/Downloads/AINewsBar-debug.log` 在正常运行下不出现 `[DB]` 日志（基线）
- [ ] 现有所有测试通过

## 回滚

修改集中在 ~25 个调用点，且语义零变更，可逐文件 revert。

---

# #2 视图拆分

## 决策摘要

| 决策点 | 选择 |
|--------|------|
| 拆分粒度 | 6 个新视图文件 + 子目录组织 |
| DI 模式 | `@EnvironmentObject` 注入 `RefreshService` |
| 非视图职责 | `BuiltInFeeds.syncInto(context:)` 静态方法 + `deduplicateArticles` 移至 App 容灾路径 |

## 目标文件结构

```
Sources/AINewsBar/Views/
├── MenuBarView.swift              (~180 行，仅 body + 框架)
├── ArticleRowView.swift            (现有，不动)
├── MenuBar/
│   ├── HeaderView.swift           (~50)
│   ├── DigestSectionView.swift    (~110，含两个 @State)
│   ├── RecommendSectionView.swift (~80)
│   ├── RecommendItemView.swift    (~50，从 MenuBarView 升格)
│   └── FooterView.swift           (~60)
├── SettingsView.swift             (~30，仅 TabView)
└── Settings/
    ├── FeedsSettingsView.swift    (~140)
    ├── FeedRowView.swift          (~90，含 FeedRowView + BuiltInFeedRowView + CheckStatusIcon)
    ├── AddFeedSheet.swift         (~110)
    ├── APISettingsView.swift      (~150)
    └── GeneralSettingsView.swift  (~30)
```

## 实施步骤

### 阶段 A：DI 改造（不动视图代码）

1. 修改 `AINewsBarApp.swift`：

```swift
@main
struct AINewsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var refreshService = RefreshService.shared
    private let container: ModelContainer = { ... }()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .modelContainer(container)
                .environmentObject(refreshService)      // ← 新增
        } label: { MenuBarLabel() }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .modelContainer(container)
                .environmentObject(refreshService)      // ← 新增
        }
    }
}
```

2. 修改 `MenuBarView`、`SettingsView` 及未来抽出的子视图：

```swift
- @ObservedObject private var refreshService = RefreshService.shared
+ @EnvironmentObject var refreshService: RefreshService
```

3. 跑测试，确认行为不变。

### 阶段 B：视图职责剥离

1. 在 `BuiltInFeeds.swift` 增加：

```swift
extension BuiltInFeeds {
    @MainActor
    static func syncInto(context: ModelContext) {
        let expectedURLs = Set(all.map(\.url))
        let existing = context.safeFetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.isBuiltIn == true })
        )
        // 删除已失效内置源 + 其文章
        let toRemove = existing.filter { !expectedURLs.contains($0.url) }
        for feed in toRemove {
            let fid = feed.id
            context.safeFetch(
                FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == fid })
            ).forEach { context.delete($0) }
            context.delete(feed)
        }
        // 添加缺失新源
        let existingURLs = Set(existing.map(\.url))
        all.filter { !existingURLs.contains($0.url) }
           .map { Feed(title: $0.title, url: $0.url, isBuiltIn: true) }
           .forEach { context.insert($0) }
        context.safeSave()
    }
}
```

2. 修改 `AINewsBarApp.swift` 的 ModelContainer catch 块：

```swift
} catch {
    Log.write("ModelContainer failed, resetting store: \(error)")
    // ... 删除 .store 文件 ...
    let c = try! ModelContainer(for: schema, configurations: config)
    Log.write("ModelContainer recreated OK")
    // 重建后跑一次去重（容灾路径）
    Task { @MainActor in
        let ctx = ModelContext(c)
        deduplicateArticles(context: ctx)   // ← 从 MenuBarView 迁移过来的私有函数
    }
    return c
}

@MainActor
private func deduplicateArticles(context: ModelContext) {
    let all = context.safeFetch(
        FetchDescriptor<Article>(sortBy: [SortDescriptor(\.publishedAt, order: .reverse)])
    )
    var seen = Set<String>()
    for article in all {
        if seen.contains(article.url) { context.delete(article) }
        else { seen.insert(article.url) }
    }
    context.safeSave()
}
```

3. 从 `MenuBarView` 删除 `syncBuiltInFeeds` 和 `deduplicateArticles`，`.task` 改为：

```swift
.task {
    refreshService.configure(with: modelContext)
    BuiltInFeeds.syncInto(context: modelContext)
    refreshService.postUnreadCount(context: modelContext)
    refreshService.launchBackgroundRefreshIfNeeded()
}
```

### 阶段 C：子视图抽出（按文件组织）

按以下顺序抽（依赖少→依赖多）：

1. `RecommendItemView.swift` — 从 MenuBarView 文件末尾的 `fileprivate struct` 升格为公开独立文件
2. `HeaderView.swift` / `FooterView.swift` — 纯展示，仅读 `@EnvironmentObject`
3. `DigestSectionView.swift` — 自含 `@State private var isExpanded/isHovered`
4. `RecommendSectionView.swift` — 自含 loading/loaded 切换
5. Settings 系列：`FeedRowView` → `FeedsSettingsView` → `AddFeedSheet` → `APISettingsView` → `GeneralSettingsView`

每抽一个，编译一次 + 手动开 app 验证 UI 不变。

## 测试影响

- 现有测试不应受影响（视图层无单测）
- 若未来要为子视图加 Preview，需要在 `#Preview { ... .environmentObject(...) }` 中注入 mock RefreshService

## 验收标准

- [ ] `MenuBarView.swift` < 300 行
- [ ] `SettingsView.swift` < 60 行（仅 TabView 容器）
- [ ] 单文件最大 < 200 行（除 APISettingsView ~150 可接受）
- [ ] 项目内 `RefreshService.shared` 仅出现在 AINewsBarApp.swift 1 处
- [ ] 应用启动、刷新、推荐、日报、设置 5 个核心路径手动通过
- [ ] 现有测试全绿

## 回滚

按文件回退即可。最大风险是 EnvironmentObject 注入位置错误导致子视图崩溃——开发期可见性高。

---

# #1 RefreshService 拆分

## 决策摘要

| 决策点 | 选择 |
|--------|------|
| 拆分粒度 | 外观 + SummaryPipeline + RecommendEngine + DigestEngine (4 类) |
| 状态归属 | `@Published` 全留 RefreshService |
| Engine 入口 | 单一 `run(trigger:)` + `Trigger` enum |
| 持久化时机 | Engine 返 Outcome，外观集中 commit |
| AI DI | model 升为方法显式参数，BailianService 不读 prefs |
| 共享数据 | `ArticleSnapshot` 值类型，调用方 fetch 一次传给两个 Engine |

## 目标文件结构

```
Sources/AINewsBar/Services/
├── RefreshService.swift            (~160 行，外观)
├── SummaryPipeline.swift           (~100，新)
├── RecommendEngine.swift           (~70，新)
├── DigestEngine.swift              (~80，新)
├── ArticleSnapshot.swift           (~40，新)
├── BailianService.swift            (修：方法签名加 model 参数)
├── PreferencesService.swift        (修：补 getModel/saveModel 进协议)
├── ServiceProtocols.swift          (修：AISummarizing 加 model，PreferencesStoring 补 getModel)
├── RefreshDecision.swift           (不动)
├── RSSService.swift                (不动)
└── BuiltInFeeds.swift              (#2 已加 syncInto)
```

## 实施步骤

### 阶段 A：扩展协议与 DI（向后兼容）

1. 修改 `ServiceProtocols.swift`：

```swift
protocol AISummarizing: Sendable {
    func generateSummary(title: String, content: String?, apiKey: String, model: String) async throws -> String
    func recommendArticles(_ articles: [(id: UUID, title: String, summary: String?)],
                           apiKey: String, model: String) async throws -> [UUID]
    func generateDigest(articleSummaries: [(title: String, summary: String)],
                        apiKey: String, model: String) async throws -> String
}

protocol PreferencesStoring: AnyObject {
    func getAPIKey() -> String?
    func getModel() -> String                      // 新增
    func loadDigest() -> (content: String, date: Date)?
    func clearDigest()
    func saveDigest(content: String, date: Date)
    func loadDigestArticleCount() -> Int
    func saveDigestArticleCount(_ count: Int)
    func loadRecommendArticleCount() -> Int
    func saveRecommendArticleCount(_ count: Int)
}
```

2. 修改 `BailianService.swift`：

```swift
// 删掉 PreferencesService.shared.getModel() 调用
// chat 内部不再用 modelOverride 兜底，model 必传

private func chat(prompt: String, maxTokens: Int, apiKey: String, model: String) async throws -> String {
    let body: [String: Any] = [
        "model": model,
        "messages": [["role": "user", "content": prompt]],
        ...
    ]
    // ...
}

// 公开方法全部带 model 参数
func generateSummary(title: String, content: String?, apiKey: String, model: String) async throws -> String { ... }
```

3. 修改 `RefreshService.swift` 调用点：

```swift
let model = prefs.getModel()
let summary = try await ai.generateSummary(title: ..., content: ..., apiKey: key, model: model)
```

4. 修改 `InMemoryPrefs` mock 与 `MockAI`：方法签名加 model 参数。

5. 跑测试，确认绿。

### 阶段 B：抽出 ArticleSnapshot 值类型

新建 `ArticleSnapshot.swift`：

```swift
import Foundation
import SwiftData

struct ArticleSnapshot: Sendable {
    struct Item: Sendable {
        let id: UUID
        let title: String
        let summary: String?
    }
    let all: [Item]
    
    var summarized: [Item] {
        all.filter { $0.summary != nil }
    }
    
    var summarizedCount: Int { summarized.count }
    
    /// 用于 DigestEngine：(title, summary) 仅含已有摘要
    var summarizedPairs: [(title: String, summary: String)] {
        all.compactMap { item in
            guard let s = item.summary else { return nil }
            return (title: item.title, summary: s)
        }
    }
    
    /// 用于 RecommendEngine：所有文章及可选摘要
    var pickInputs: [(id: UUID, title: String, summary: String?)] {
        all.map { ($0.id, $0.title, $0.summary) }
    }
    
    @MainActor
    static func capture(from context: ModelContext) -> ArticleSnapshot {
        let articles = context.safeFetch(FetchDescriptor<Article>())
        return ArticleSnapshot(all: articles.map { 
            Item(id: $0.id, title: $0.title, summary: $0.aiSummary)
        })
    }
}
```

### 阶段 C：抽出 SummaryPipeline

新建 `SummaryPipeline.swift`：

```swift
import Foundation
import SwiftData

/// 扫描 pending → 有界并发摘要 → 返回回写所需结果
struct SummaryPipeline {
    let ai: any AISummarizing
    let maxConcurrent: Int
    
    struct Result: Sendable {
        let completed: [(id: UUID, summary: String)]
        let total: Int
        var completionRate: Double {
            RefreshDecision.completionRate(completed: completed.count, total: total)
        }
    }
    
    /// 输入 pending tasks (Sendable), 输出完成 map; 调用方负责回写 @Model
    func run(tasks: [SummaryTask], apiKey: String, model: String) async -> Result {
        guard !tasks.isEmpty else { return Result(completed: [], total: 0) }
        var completed: [(UUID, String)] = []
        let aiRef = ai
        let cap = maxConcurrent
        
        await withTaskGroup(of: (UUID, String?).self) { group in
            var next = min(cap, tasks.count)
            for i in 0..<next {
                let t = tasks[i]
                group.addTask {
                    guard let s = try? await aiRef.generateSummary(
                        title: t.title, content: t.content, apiKey: apiKey, model: model
                    ) else {
                        Log.write("[Summary] failed: \(t.title.prefix(30))")
                        return (t.id, nil)
                    }
                    return (t.id, s)
                }
            }
            for await (id, s) in group {
                if let s { completed.append((id, s)) }
                if next < tasks.count {
                    let t = tasks[next]
                    next += 1
                    group.addTask {
                        guard let s = try? await aiRef.generateSummary(
                            title: t.title, content: t.content, apiKey: apiKey, model: model
                        ) else { return (t.id, nil) }
                        return (t.id, s)
                    }
                }
            }
        }
        return Result(completed: completed, total: tasks.count)
    }
    
    struct SummaryTask: Sendable {
        let id: UUID
        let title: String
        let content: String?
    }
}
```

### 阶段 D：抽出 RecommendEngine

新建 `RecommendEngine.swift`：

```swift
import Foundation

struct RecommendEngine {
    enum Trigger: Sendable {
        case auto(hasNewArticles: Bool, isEmpty: Bool, currentCount: Int, lastCount: Int, deltaThreshold: Int)
        case forced
    }
    
    struct State: Sendable {
        let lastCount: Int
    }
    
    struct Outcome: Sendable {
        let ids: [UUID]
        let generatedAt: Date
        let articleCount: Int
    }
    
    let ai: any AISummarizing
    
    /// 返回 nil = 决策不执行；throws = AI 调用失败
    func run(trigger: Trigger,
             snapshot: ArticleSnapshot,
             apiKey: String,
             model: String) async throws -> Outcome? {
        // Gate
        switch trigger {
        case .auto(let hasNew, let isEmpty, let curr, let last, let delta):
            guard RefreshDecision.shouldRegenerateRecommend(
                hasNewArticles: hasNew, isEmpty: isEmpty,
                currentCount: curr, lastCount: last, deltaThreshold: delta
            ) else { return nil }
        case .forced:
            break
        }
        guard snapshot.all.count >= 3 else { return nil }
        
        // Execute
        let ids = try await ai.recommendArticles(snapshot.pickInputs, apiKey: apiKey, model: model)
        return Outcome(ids: ids, generatedAt: Date(), articleCount: snapshot.summarizedCount)
    }
}
```

### 阶段 E：抽出 DigestEngine

新建 `DigestEngine.swift`：

```swift
import Foundation

struct DigestEngine {
    enum Trigger: Sendable {
        case auto(hasNewArticles: Bool, isPresent: Bool, lastDate: Date?, currentCount: Int, lastCount: Int, hasEnoughCoverage: Bool, regenerateInterval: TimeInterval, deltaThreshold: Int)
        case forced
    }
    
    struct Outcome: Sendable {
        let content: String
        let generatedAt: Date
        let articleCount: Int
    }
    
    let ai: any AISummarizing
    
    func run(trigger: Trigger,
             snapshot: ArticleSnapshot,
             apiKey: String,
             model: String) async throws -> Outcome? {
        // Gate
        switch trigger {
        case .auto(let hasNew, let isPresent, let lastDate, let curr, let last, let coverage, let interval, let delta):
            guard coverage else {
                Log.write("[Digest] skip — coverage below threshold")
                return nil
            }
            guard RefreshDecision.shouldRegenerateDigest(
                hasNewArticles: hasNew, isPresent: isPresent, lastDate: lastDate,
                currentCount: curr, lastCount: last,
                regenerateInterval: interval, deltaThreshold: delta
            ) else { return nil }
        case .forced:
            break
        }
        guard snapshot.summarizedCount >= 3 else { return nil }
        
        let content = try await ai.generateDigest(
            articleSummaries: snapshot.summarizedPairs,
            apiKey: apiKey, model: model
        )
        return Outcome(content: content, generatedAt: Date(), articleCount: snapshot.summarizedCount)
    }
}
```

### 阶段 F：RefreshService 重写为外观

```swift
@MainActor
final class RefreshService: ObservableObject {
    static let shared = RefreshService()
    
    // @Published 状态 (全部保留)
    @Published var isRefreshing = false
    @Published var isSummarizing = false
    @Published var isRegeneratingRecommend = false
    @Published var isRegeneratingDigest = false
    @Published var lastRefreshDate: Date?
    @Published var lastError: String?
    @Published var lastFetchErrorCount = 0
    @Published var dailyDigest: String?
    @Published var recommendedArticleIDs: [UUID] = []
    @Published var aiAvailability: AIAvailability = .unknown
    @Published var lastDigestDate: Date?
    @Published var lastRecommendDate: Date?
    
    // 注入
    private let rss: any RSSFetching
    private let ai: any AISummarizing
    private let prefs: any PreferencesStoring
    
    // 组件
    private let summaryPipeline: SummaryPipeline
    private let recommendEngine: RecommendEngine
    private let digestEngine: DigestEngine
    
    // 配置常量
    private let refreshInterval: TimeInterval = 3600
    private let staleThreshold: TimeInterval = 1800
    private let digestRegenerateInterval: TimeInterval = 3 * 3600
    private let summaryDeltaThreshold = 3
    private let maxConcurrentSummaries = 5
    private let coverageThreshold = 0.8
    
    private var modelContext: ModelContext?
    private var configured = false
    private var timer: Timer?
    private var digestArticleCount = 0
    private var recommendArticleCount = 0
    
    init(rss: any RSSFetching = RSSService.shared,
         ai: any AISummarizing = BailianService.shared,
         prefs: any PreferencesStoring = PreferencesService.shared) {
        self.rss = rss
        self.ai = ai
        self.prefs = prefs
        self.summaryPipeline = SummaryPipeline(ai: ai, maxConcurrent: 5)
        self.recommendEngine = RecommendEngine(ai: ai)
        self.digestEngine = DigestEngine(ai: ai)
    }
    
    // 入口 (configure / refresh / forceRegenerate*) 实现略
    // 关键变化：
    // - generatePendingSummaries 内部用 summaryPipeline.run(tasks:)
    // - generateDailyDigestIfNeeded 拆为 runRecommend(trigger:.auto) + runDigest(trigger:.auto)
    // - forceRegenerateRecommend → runRecommend(trigger:.forced)
    // - forceRegenerateDigest    → runDigest(trigger:.forced)
    // - runRecommend/runDigest 是私有 helper，统一拿 snapshot + commit outcome
}

// 关键的统一 commit helper
private extension RefreshService {
    func commit(_ outcome: RecommendEngine.Outcome) {
        recommendedArticleIDs = outcome.ids
        lastRecommendDate = outcome.generatedAt
        recommendArticleCount = outcome.articleCount
        prefs.saveRecommendArticleCount(outcome.articleCount)
        aiAvailability = .available
    }
    
    func commit(_ outcome: DigestEngine.Outcome) {
        dailyDigest = outcome.content
        lastDigestDate = outcome.generatedAt
        digestArticleCount = outcome.articleCount
        prefs.saveDigest(content: outcome.content, date: outcome.generatedAt)
        prefs.saveDigestArticleCount(outcome.articleCount)
    }
}
```

## 测试影响

### 现有测试调整
- `BailianServiceTests`：所有调用加 model 参数
- `MockAI`：方法签名加 model
- `InMemoryPrefs`：加 `getModel/saveModel` 实现（即使 RefreshService 不直接用 saveModel）
- `RefreshServiceTests`：行为应保持，无须改测试用例本身（只可能改 mock 调用记录格式）

### 新增测试
- `SummaryPipelineTests.swift`：
  - 空 tasks 返回空
  - 全成功
  - 部分失败（completionRate 计算）
  - 并发上限不超过 maxConcurrent
- `RecommendEngineTests.swift`：
  - `.auto` + 决策返 nil → 不调 AI
  - `.auto` + 决策返 true → 调 AI 返 outcome
  - `.forced` → 跳过决策直接调
  - articles < 3 → 返 nil
  - AI 抛错 → throw
- `DigestEngineTests.swift`：同上
- `ArticleSnapshotTests.swift`：
  - summarizedPairs / pickInputs 字段映射正确
  - summarizedCount

## 验收标准

- [ ] `RefreshService.swift` < 200 行
- [ ] 4 个 Engine/Pipeline 文件各 < 150 行
- [ ] 没有重复的 `try? await ai.generateDigest` 调用（force 与 auto 路径合一）
- [ ] `BailianService.shared` 仅出现在 `AINewsBarApp` / 测试 mock 注入点
- [ ] `PreferencesService.shared` 仅出现在 `AINewsBarApp` / 测试 mock 注入点
- [ ] 现有 RefreshServiceTests 全绿
- [ ] 新增 Engine/Pipeline 测试达 80% 覆盖
- [ ] 手动验证 5 个核心路径：启动刷新 / 手动刷新 / 强制重生成推荐 / 强制重生成日报 / API key 配置流

## 回滚

风险点：
1. Engine 边界划错导致行为漂移（如 force 路径漏掉某个 @Published 更新）
2. Commit 顺序变化引起 UI 闪烁

回滚策略：
- 阶段 A-E 完成后单独 commit，每阶段可独立 revert
- 阶段 F 是大刀，建议拆成 2-3 个 commit（先抽 runRecommend/runDigest helper，再 force 路径切换，再删旧 generate*IfNeeded）

---

# #4 全表 fetch 优化

## 决策摘要

| 决策点 | 选择 |
|--------|------|
| 视图层 `recommendedArticles` | 复用 `unreadArticles + readArticles` 内存过滤 |
| Service 层多次 fetchAll | 由 #1 ArticleSnapshot 解决 |
| `deduplicateArticles` 每次启动跑 | 降级为容灾路径（已在 #2 实现） |
| `refresh()` 的 `existingURLs` fetchAll | 保留现状（当日量小） |

## 文件清单

**仅修改 1 处** (#1/#2 完成后)：
- `Sources/AINewsBar/Views/MenuBar/RecommendSectionView.swift` 中的 `recommendedArticles` computed

## 实施步骤

在 `RecommendSectionView` 中（#2 抽出后）：

```swift
struct RecommendSectionView: View {
    @EnvironmentObject var refreshService: RefreshService
    let unreadArticles: [Article]    // 从父视图 MenuBarView 传入
    let readArticles: [Article]
    let onOpen: (Article) -> Void
    
    private var recommendedArticles: [Article] {
        let ids = refreshService.recommendedArticleIDs
        guard !ids.isEmpty else { return [] }
        let all = unreadArticles + readArticles
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }   // 保序 + O(n)
    }
    
    // body ...
}
```

注意：将 `unreadArticles + readArticles` 通过 init 参数传入，而非在子视图重新 `@Query`——避免双重订阅。

## 测试影响

- 视图层无单测，无影响
- 性能可在 Instruments 验证（fetch 调用次数应从"每次 body 重绘 1 次"降至 0）

## 验收标准

- [ ] `RecommendSectionView` 内不再有 `modelContext.fetch`
- [ ] 频繁触发 `@Published` 状态变化（如 `isSummarizing` toggle）时无 fetch 调用爆发

## 回滚

单文件单方法回退，无风险。

---

# 总收益与风险

## 收益

| 维度 | 改善 |
|------|------|
| 最大单文件 | 503 → <300 行 |
| `RefreshService` 主类 | 403 → ~160 行 |
| force-regenerate 重复代码 | -60 行 |
| 视图层每帧 fetchAll | 消除 |
| Singleton `.shared` 散布点 | 12+ → 1-2 |
| 错误吞噬点 | 25 → 0（替换为 Log）|
| 协议 DI 完整性 | model 不再走 singleton 后门 |
| Engine 单测覆盖 | 0 → ≥80% |

## 风险

| 风险 | 缓解 |
|------|------|
| #1 重构引入行为漂移 | 阶段化提交 + 现有测试覆盖关键路径 |
| #1 force/auto 合一时漏掉 @Published 更新 | commit() helper 单独审查 |
| #2 EnvironmentObject 注入位置错 | 抽视图前先做 DI 改造 + 启动验证 |
| #2 RecommendItemView fileprivate 升格暴露面变化 | 仅一处使用方，编译保证 |
| #4 unread+read 合并丢顺序 | Dictionary + compactMap(ids) 显式保序 |

## 整体工时估算（单人）

| 项 | 预估 |
|----|------|
| #5 错误吞噬 | 30 分钟（机械替换 + 测试）|
| #2 视图拆分 | 2-3 小时（含 DI 改造）|
| #1 RefreshService 拆分 | 4-6 小时（含 5 个新文件 + 测试）|
| #4 残余优化 | 30 分钟（依赖 #1/#2）|
| **合计** | **7-10 小时** |

---

# 未深挖项（备忘）

以下在访谈中给出但未进决策，留待未来：

- **#6 BailianService 用 Codable** 替代 `as? [String: Any]`
- **#7 API Key 改 Keychain**（自用风险低）
- **#8 Log 改 os.Logger** 或持有 FileHandle
- **#9 视图层补单测**（SwiftUI 视图测试成本高）
- **#10 测试框架迁移 Swift Testing**（XCTest 仍可用）
- **#11 多源错误聚合显示**（当前只显示第一条）

如需后续推进，重启 `/grill-me` 即可。
