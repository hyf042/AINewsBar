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

    // MARK: - 全局 API Key / Model（不动）

    /// 第十三轮 P2 review：API Key / Model 在持久化边界**写入和读取**都 trim。
    ///
    /// 第十二轮只修了 APISettingsView UI 层 —— 但用户老版本里已经存了带换行/空白的 key
    /// 时升级后主流程仍会 HTTP 401（"Authorization: Bearer sk-...\n"），除非用户重新
    /// 进设置页保存触发 UI 路径的 trim。底层 service 读写都 trim 兜底治历史脏数据。
    /// caller (UI / RefreshService / BailianService) 不需感知。
    ///
    /// **Base64 编码**（C1 review）：UserDefaults 是 plist 文件，明文 API Key 可被
    /// `strings` 命令直接读出。Base64 不提供真实加密（任何人可解码），但能防止 casual
    /// 扫描拿到可用的 key。读取时兼容旧版明文存储，首次命中自动迁移到编码格式。

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            defaults.removeObject(forKey: apiKeyKey)
            return
        }
        let encoded = Data(trimmed.utf8).base64EncodedString()
        defaults.set(encoded, forKey: apiKeyKey)
    }

    func getAPIKey() -> String? {
        guard let stored = defaults.string(forKey: apiKeyKey) else { return nil }
        // 当前格式：Base64 编码
        if let data = Data(base64Encoded: stored),
           let key = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return key
        }
        // 旧版明文存储（迁移路径）：读到后自动升级为编码格式
        let legacy = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty else {
            defaults.removeObject(forKey: apiKeyKey)
            return nil
        }
        let encoded = Data(legacy.utf8).base64EncodedString()
        defaults.set(encoded, forKey: apiKeyKey)
        return legacy
    }

    func deleteAPIKey() {
        defaults.removeObject(forKey: apiKeyKey)
    }

    func saveModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmed.isEmpty ? nil : trimmed, forKey: modelKey)
    }

    func getModel() -> String {
        let value = defaults.string(forKey: modelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false ? value : nil) ?? Self.defaultModel
    }

    // MARK: - UI 状态（v2 新增全局 key）

    private let selectedTabKey = "com.ainewsbar.ui.selectedTab"
    private let settingsFeedsTabKey = "com.ainewsbar.ui.settingsFeedsTab"

    func loadSelectedTab() -> Category {
        Category.from(rawValue: defaults.string(forKey: selectedTabKey))
    }

    func saveSelectedTab(_ cat: Category) {
        defaults.set(cat.rawValue, forKey: selectedTabKey)
    }

    func loadSettingsFeedsTab() -> Category {
        Category.from(rawValue: defaults.string(forKey: settingsFeedsTabKey))
    }

    func saveSettingsFeedsTab(_ cat: Category) {
        defaults.set(cat.rawValue, forKey: settingsFeedsTabKey)
    }

    // MARK: - per-cat key 拼接 helper

    /// Key 模板：`com.ainewsbar.<base>.<cat>`
    private func key(_ base: String, _ cat: Category) -> String {
        "com.ainewsbar.\(base).\(cat.rawValue)"
    }

    // MARK: - Auto refresh 开关 (per-cat, v2.1 新增)

    /// 默认 true：未配置过的 cat 视为开启后台刷新。
    func loadAutoRefreshEnabled(for cat: Category) -> Bool {
        let k = key("autoRefreshEnabled", cat)
        // 用 object 检测是否曾 set 过；没 set 过返回 true（默认开启）
        if defaults.object(forKey: k) == nil { return true }
        return defaults.bool(forKey: k)
    }

    func saveAutoRefreshEnabled(_ enabled: Bool, for cat: Category) {
        defaults.set(enabled, forKey: key("autoRefreshEnabled", cat))
    }

    // MARK: - Digest persistence (per-cat)

    func saveDigest(content: String, date: Date, for cat: Category) {
        defaults.set(content, forKey: key("digest.content", cat))
        defaults.set(date, forKey: key("digest.date", cat))
    }

    func loadDigest(for cat: Category) -> (content: String, date: Date)? {
        guard let content = defaults.string(forKey: key("digest.content", cat)),
              let date = defaults.object(forKey: key("digest.date", cat)) as? Date else { return nil }
        return (content, date)
    }

    func clearDigest(for cat: Category) {
        defaults.removeObject(forKey: key("digest.content", cat))
        defaults.removeObject(forKey: key("digest.date", cat))
        defaults.removeObject(forKey: key("digest.articleCount", cat))
    }

    /// 仅清推荐相关状态。caller 显式决定是否调（跨日重置 vs 当日保留）。
    func clearRecommendState(for cat: Category) {
        defaults.removeObject(forKey: key("recommend.articleCount", cat))
    }

    // MARK: - Article count at last generation (Plan A: detect significant new summaries) (per-cat)

    func saveDigestArticleCount(_ count: Int, for cat: Category) {
        defaults.set(count, forKey: key("digest.articleCount", cat))
    }

    func loadDigestArticleCount(for cat: Category) -> Int {
        defaults.integer(forKey: key("digest.articleCount", cat))
    }

    func saveRecommendArticleCount(_ count: Int, for cat: Category) {
        defaults.set(count, forKey: key("recommend.articleCount", cat))
    }

    func loadRecommendArticleCount(for cat: Category) -> Int {
        defaults.integer(forKey: key("recommend.articleCount", cat))
    }
}
