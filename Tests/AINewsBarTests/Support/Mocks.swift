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

    // 错误注入
    var summaryError: Error?
    var recommendError: Error?
    var digestError: Error?

    // 调用计数
    var summaryCallCount = 0
    var recommendCallCount = 0
    var digestCallCount = 0

    func generateSummary(title: String, content: String?, apiKey: String, model: String) async throws -> String {
        summaryCallCount += 1
        if let e = summaryError { throw e }
        return summaryProvider?(title, content) ?? "mock-summary-of-\(title)"
    }

    func recommendArticles(_ items: [ArticleSnapshot.Item], apiKey: String, model: String) async throws -> [UUID] {
        recommendCallCount += 1
        if let e = recommendError { throw e }
        if let p = recommendProvider { return p(items) }
        return Array(items.prefix(3).map(\.id))
    }

    func generateDigest(items: [ArticleSnapshot.Item], apiKey: String, model: String) async throws -> String {
        digestCallCount += 1
        if let e = digestError { throw e }
        return digestProvider?(items) ?? "mock-digest-\(items.count)"
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
