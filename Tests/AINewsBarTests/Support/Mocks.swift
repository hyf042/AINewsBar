import Foundation
@testable import AINewsBar

// MARK: - 测试用 Mock

final class MockRSS: RSSFetching, @unchecked Sendable {
    // 按 feedURL 路由结果
    var results: [String: Result<[RawArticle], Error>] = [:]
    var fetchCount = 0

    func setSuccess(_ feedURL: String, _ articles: [RawArticle]) {
        results[feedURL] = .success(articles)
    }

    func setFailure(_ feedURL: String, _ error: Error) {
        results[feedURL] = .failure(error)
    }

    func fetchRawArticles(feedURL: String) async throws -> [RawArticle] {
        fetchCount += 1
        guard let r = results[feedURL] else { return [] }
        switch r {
        case .success(let a): return a
        case .failure(let e): throw e
        }
    }
}

final class MockAI: AISummarizing, @unchecked Sendable {
    var summaryProvider: (@Sendable (String, String?) -> String)?
    var recommendProvider: (@Sendable ([ArticleSnapshot.Item]) -> [UUID])?
    var digestProvider: (@Sendable ([ArticleSnapshot.Item]) -> String)?
    // v2 新增：Filter provider（接收 title + description，返回 accepted bool）
    var classifyProvider: (@Sendable (String, String) -> Bool)?

    // 默认 usage（zero）；需断言时测试侧覆盖
    var summaryUsage: UsageInfo = .zero
    var recommendUsage: UsageInfo = .zero
    var digestUsage: UsageInfo = .zero
    var classifyUsage: UsageInfo = .zero

    // 错误注入
    var summaryError: Error?
    var recommendError: Error?
    var digestError: Error?
    var classifyError: Error?

    // 调用计数 —— SummaryPipeline / FilterPipeline 5 并发调，必须加锁保护
    // （provider 和 usage 在 setUp 后只读，无需加锁）
    private let countLock = NSLock()
    private var _summaryCallCount = 0
    private var _recommendCallCount = 0
    private var _digestCallCount = 0
    private var _classifyCallCount = 0
    // v2 cat 透传断言用：捕获每次调用的 cat
    private var _capturedSummaryCats: [AINewsBar.Category] = []
    private var _capturedRecommendCats: [AINewsBar.Category] = []
    private var _capturedDigestCats: [AINewsBar.Category] = []

    var summaryCallCount: Int { countLock.withLock { _summaryCallCount } }
    var recommendCallCount: Int { countLock.withLock { _recommendCallCount } }
    var digestCallCount: Int { countLock.withLock { _digestCallCount } }
    var classifyCallCount: Int { countLock.withLock { _classifyCallCount } }
    var capturedSummaryCats: [AINewsBar.Category] { countLock.withLock { _capturedSummaryCats } }
    var capturedRecommendCats: [AINewsBar.Category] { countLock.withLock { _capturedRecommendCats } }
    var capturedDigestCats: [AINewsBar.Category] { countLock.withLock { _capturedDigestCats } }

    func generateSummary(
        title: String, content: String?,
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (summary: String, usage: UsageInfo) {
        countLock.withLock {
            _summaryCallCount += 1
            _capturedSummaryCats.append(category)
        }
        if let e = summaryError { throw e }
        let text = summaryProvider?(title, content) ?? "mock-summary-of-\(title)"
        return (text, summaryUsage)
    }

    func recommendArticles(
        _ items: [ArticleSnapshot.Item],
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (ids: [UUID], usage: UsageInfo) {
        countLock.withLock {
            _recommendCallCount += 1
            _capturedRecommendCats.append(category)
        }
        if let e = recommendError { throw e }
        let ids: [UUID]
        if let p = recommendProvider { ids = p(items) }
        else { ids = Array(items.prefix(5).map(\.id)) }
        return (ids, recommendUsage)
    }

    func generateDigest(
        items: [ArticleSnapshot.Item],
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (content: String, usage: UsageInfo) {
        countLock.withLock {
            _digestCallCount += 1
            _capturedDigestCats.append(category)
        }
        if let e = digestError { throw e }
        let text = digestProvider?(items) ?? "mock-digest-\(items.count)"
        return (text, digestUsage)
    }

    func classifyArticle(
        title: String, description: String, prompt: String,
        apiKey: String, model: String
    ) async throws -> (accepted: Bool, usage: UsageInfo) {
        countLock.withLock { _classifyCallCount += 1 }
        if let e = classifyError { throw e }
        let accepted = classifyProvider?(title, description) ?? true
        return (accepted, classifyUsage)
    }
}

/// v2-multi-category: per-cat 字典存储。旧测试 fixture 通过 backward-compat
/// helper 直接读 `prefs.digestContent` 等访问 .ai cat 状态（保持兼容）。
final class InMemoryPrefs: PreferencesStoring {
    var apiKey: String? = "mock-api-key"
    var model: String = "mock-model"

    // per-cat storage
    private var digestContents: [AINewsBar.Category: String] = [:]
    private var digestDates: [AINewsBar.Category: Date] = [:]
    private var digestArticleCounts: [AINewsBar.Category: Int] = [:]
    private var recommendArticleCounts: [AINewsBar.Category: Int] = [:]
    private var autoRefreshEnabled: [AINewsBar.Category: Bool] = [:]   // 未 set 视为 true
    private var _selectedTab: AINewsBar.Category = .ai
    private var _settingsFeedsTab: AINewsBar.Category = .ai

    // MARK: - Backward-compat helpers（.ai 快捷访问，旧测试 fixture 用）

    var digestContent: String? {
        get { digestContents[.ai] }
        set { digestContents[.ai] = newValue }
    }
    var digestDate: Date? {
        get { digestDates[.ai] }
        set { digestDates[.ai] = newValue }
    }
    var digestArticleCount: Int {
        get { digestArticleCounts[.ai] ?? 0 }
        set { digestArticleCounts[.ai] = newValue }
    }
    var recommendArticleCount: Int {
        get { recommendArticleCounts[.ai] ?? 0 }
        set { recommendArticleCounts[.ai] = newValue }
    }

    // MARK: - 全局

    func getAPIKey() -> String? { apiKey }
    func getModel() -> String { model }

    func loadSelectedTab() -> AINewsBar.Category { _selectedTab }
    func saveSelectedTab(_ cat: AINewsBar.Category) { _selectedTab = cat }
    func loadSettingsFeedsTab() -> AINewsBar.Category { _settingsFeedsTab }
    func saveSettingsFeedsTab(_ cat: AINewsBar.Category) { _settingsFeedsTab = cat }

    // MARK: - per-cat 后台刷新开关 (v2.1)

    func loadAutoRefreshEnabled(for cat: AINewsBar.Category) -> Bool {
        autoRefreshEnabled[cat] ?? true  // 未 set 默认 true
    }
    func saveAutoRefreshEnabled(_ enabled: Bool, for cat: AINewsBar.Category) {
        autoRefreshEnabled[cat] = enabled
    }

    // MARK: - per-cat 新签名（旧签名由 protocol extension 自动 delegate 到 .ai）

    func loadDigest(for cat: AINewsBar.Category) -> (content: String, date: Date)? {
        guard let c = digestContents[cat], let d = digestDates[cat] else { return nil }
        return (c, d)
    }
    func saveDigest(content: String, date: Date, for cat: AINewsBar.Category) {
        digestContents[cat] = content
        digestDates[cat] = date
    }
    func clearDigest(for cat: AINewsBar.Category) {
        digestContents[cat] = nil
        digestDates[cat] = nil
        digestArticleCounts[cat] = 0
    }
    func clearRecommendState(for cat: AINewsBar.Category) {
        recommendArticleCounts[cat] = 0
    }
    func loadDigestArticleCount(for cat: AINewsBar.Category) -> Int { digestArticleCounts[cat] ?? 0 }
    func saveDigestArticleCount(_ count: Int, for cat: AINewsBar.Category) { digestArticleCounts[cat] = count }
    func loadRecommendArticleCount(for cat: AINewsBar.Category) -> Int { recommendArticleCounts[cat] ?? 0 }
    func saveRecommendArticleCount(_ count: Int, for cat: AINewsBar.Category) { recommendArticleCounts[cat] = count }
}

/// 测试用 UsageRecording —— 把每次 record 调用作为 RecordedEntry 累积，便于断言。
@MainActor
final class InMemoryUsageRecorder: UsageRecording {
    struct Entry: Equatable {
        let scene: UsageScene
        let model: String
        let input: Int
        let output: Int
        let success: Bool
        let category: AINewsBar.Category

        /// 兼容旧测试 case（Phase 4 前 cat 默认 .ai）
        init(scene: UsageScene, model: String, input: Int, output: Int,
             success: Bool, category: AINewsBar.Category = .ai) {
            self.scene = scene
            self.model = model
            self.input = input
            self.output = output
            self.success = success
            self.category = category
        }
    }

    private(set) var entries: [Entry] = []
    private(set) var cleanupCalls: [Int] = []

    func record(
        scene: UsageScene, category: AINewsBar.Category,
        model: String, input: Int, output: Int, success: Bool
    ) {
        entries.append(Entry(scene: scene, model: model,
                              input: input, output: output,
                              success: success, category: category))
    }

    func cleanupOlderThan(days: Int) {
        cleanupCalls.append(days)
    }
}
