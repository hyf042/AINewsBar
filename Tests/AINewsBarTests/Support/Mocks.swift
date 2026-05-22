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

    // 默认 usage（zero）；需断言时测试侧覆盖
    var summaryUsage: UsageInfo = .zero
    var recommendUsage: UsageInfo = .zero
    var digestUsage: UsageInfo = .zero

    // 错误注入
    var summaryError: Error?
    var recommendError: Error?
    var digestError: Error?

    // 调用计数 —— SummaryPipeline 5 并发调 generateSummary，必须加锁保护
    // （summary/recommend/digest provider 和 usage 在 setUp 后只读，无需加锁）
    private let countLock = NSLock()
    private var _summaryCallCount = 0
    private var _recommendCallCount = 0
    private var _digestCallCount = 0

    var summaryCallCount: Int { countLock.withLock { _summaryCallCount } }
    var recommendCallCount: Int { countLock.withLock { _recommendCallCount } }
    var digestCallCount: Int { countLock.withLock { _digestCallCount } }

    func generateSummary(title: String, content: String?, apiKey: String, model: String)
        async throws -> (summary: String, usage: UsageInfo)
    {
        countLock.withLock { _summaryCallCount += 1 }
        if let e = summaryError { throw e }
        let text = summaryProvider?(title, content) ?? "mock-summary-of-\(title)"
        return (text, summaryUsage)
    }

    func recommendArticles(_ items: [ArticleSnapshot.Item], apiKey: String, model: String)
        async throws -> (ids: [UUID], usage: UsageInfo)
    {
        countLock.withLock { _recommendCallCount += 1 }
        if let e = recommendError { throw e }
        let ids: [UUID]
        if let p = recommendProvider { ids = p(items) }
        else { ids = Array(items.prefix(3).map(\.id)) }
        return (ids, recommendUsage)
    }

    func generateDigest(items: [ArticleSnapshot.Item], apiKey: String, model: String)
        async throws -> (content: String, usage: UsageInfo)
    {
        countLock.withLock { _digestCallCount += 1 }
        if let e = digestError { throw e }
        let text = digestProvider?(items) ?? "mock-digest-\(items.count)"
        return (text, digestUsage)
    }
}

final class InMemoryPrefs: PreferencesStoring {
    var apiKey: String? = "mock-api-key"
    var model: String = "mock-model"
    var digestContent: String?
    var digestDate: Date?
    var digestArticleCount = 0
    var recommendArticleCount = 0

    func getAPIKey() -> String? { apiKey }
    func getModel() -> String { model }

    func loadDigest() -> (content: String, date: Date)? {
        guard let c = digestContent, let d = digestDate else { return nil }
        return (c, d)
    }

    func clearDigest() {
        digestContent = nil
        digestDate = nil
        digestArticleCount = 0
    }

    func clearRecommendState() {
        recommendArticleCount = 0
    }

    func saveDigest(content: String, date: Date) {
        digestContent = content
        digestDate = date
    }

    func loadDigestArticleCount() -> Int { digestArticleCount }
    func saveDigestArticleCount(_ count: Int) { digestArticleCount = count }
    func loadRecommendArticleCount() -> Int { recommendArticleCount }
    func saveRecommendArticleCount(_ count: Int) { recommendArticleCount = count }
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
    }

    private(set) var entries: [Entry] = []
    private(set) var cleanupCalls: [Int] = []

    func record(scene: UsageScene, model: String, input: Int, output: Int, success: Bool) {
        entries.append(Entry(scene: scene, model: model,
                              input: input, output: output, success: success))
    }

    func cleanupOlderThan(days: Int) {
        cleanupCalls.append(days)
    }
}
