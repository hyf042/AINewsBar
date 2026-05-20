import Foundation

// MARK: - 用于 RefreshService 依赖注入的协议抽象
// 默认实现见 RSSService / BailianService / PreferencesService；测试时注入 Mock

protocol RSSFetching: Sendable {
    func fetchRawArticles(feedURL: String) async throws -> [RawArticle]
}

protocol AISummarizing: Sendable {
    func generateSummary(title: String, content: String?, apiKey: String, model: String) async throws -> String
    /// 入参 items 应包含全部候选；返回选中的 id 列表（保序）
    func recommendArticles(_ items: [ArticleSnapshot.Item],
                            apiKey: String, model: String) async throws -> [UUID]
    /// 入参 items 应仅含已有摘要的条目（caller 负责过滤）；nil-summary 项实现侧防御性跳过
    func generateDigest(items: [ArticleSnapshot.Item],
                         apiKey: String, model: String) async throws -> String
}

// PreferencesStoring 不要求 Sendable，因为它持有 UserDefaults（非 Sendable）
// RefreshService @MainActor 调用，单线程访问足够
protocol PreferencesStoring: AnyObject {
    func getAPIKey() -> String?
    func getModel() -> String
    func loadDigest() -> (content: String, date: Date)?
    func clearDigest()
    func saveDigest(content: String, date: Date)
    func loadDigestArticleCount() -> Int
    func saveDigestArticleCount(_ count: Int)
    func loadRecommendArticleCount() -> Int
    func saveRecommendArticleCount(_ count: Int)
}
