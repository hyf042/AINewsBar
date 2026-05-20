import Foundation

// 个人工具无需 Keychain 强安全保证，用 UserDefaults 存储 API Key 避免每次弹授权窗口
// 命名历史：此服务曾名为 KeychainService，因实际不使用 Keychain 已重命名为 PreferencesService
final class PreferencesService: PreferencesStoring {
    static let shared = PreferencesService()
    static let defaultModel = "qwen3.6-plus"

    private let defaults: UserDefaults
    private let apiKeyKey = "com.ainewsbar.claude-api-key"
    private let modelKey  = "com.ainewsbar.model"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func saveAPIKey(_ key: String) {
        defaults.set(key.isEmpty ? nil : key, forKey: apiKeyKey)
    }

    func getAPIKey() -> String? {
        let value = defaults.string(forKey: apiKeyKey)
        return value?.isEmpty == false ? value : nil
    }

    func deleteAPIKey() {
        defaults.removeObject(forKey: apiKeyKey)
    }

    func saveModel(_ model: String) {
        defaults.set(model.isEmpty ? nil : model, forKey: modelKey)
    }

    func getModel() -> String {
        defaults.string(forKey: modelKey) ?? Self.defaultModel
    }

    // MARK: - Digest persistence

    private let digestContentKey = "com.ainewsbar.digest.content"
    private let digestDateKey    = "com.ainewsbar.digest.date"

    func saveDigest(content: String, date: Date) {
        defaults.set(content, forKey: digestContentKey)
        defaults.set(date, forKey: digestDateKey)
    }

    func loadDigest() -> (content: String, date: Date)? {
        guard let content = defaults.string(forKey: digestContentKey),
              let date = defaults.object(forKey: digestDateKey) as? Date else { return nil }
        return (content, date)
    }

    func clearDigest() {
        defaults.removeObject(forKey: digestContentKey)
        defaults.removeObject(forKey: digestDateKey)
        defaults.removeObject(forKey: digestArticleCountKey)
        defaults.removeObject(forKey: recommendArticleCountKey)
    }

    // MARK: - Article count at last generation (Plan A: detect significant new summaries)

    private let digestArticleCountKey    = "com.ainewsbar.digest.articleCount"
    private let recommendArticleCountKey = "com.ainewsbar.recommend.articleCount"

    func saveDigestArticleCount(_ count: Int) {
        defaults.set(count, forKey: digestArticleCountKey)
    }

    func loadDigestArticleCount() -> Int {
        defaults.integer(forKey: digestArticleCountKey)
    }

    func saveRecommendArticleCount(_ count: Int) {
        defaults.set(count, forKey: recommendArticleCountKey)
    }

    func loadRecommendArticleCount() -> Int {
        defaults.integer(forKey: recommendArticleCountKey)
    }
}
