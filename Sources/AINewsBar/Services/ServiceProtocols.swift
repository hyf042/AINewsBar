import Foundation

// MARK: - 用于 RefreshService 依赖注入的协议抽象
// 默认实现见 RSSService / BailianService / PreferencesService；测试时注入 Mock

protocol RSSFetching: Sendable {
    func fetchRawArticles(feedURL: String) async throws -> [RawArticle]
}

// MARK: - AISummarizing（v2-multi-category 双轨）
//
// Phase 3 引入 per-cat 签名 + classifyArticle（Filter Stage）。
// 旧签名走 protocol extension 自动 delegate 到 .ai；Phase 4 RefreshService 改造后删旧签名。
protocol AISummarizing: Sendable {
    // MARK: per-cat 新签名（Phase 3 引入，Phase 4 后成为正式 API）

    /// 返回摘要 + 本次调用的 token 用量。prompt 文案根据 cat 选择。
    func generateSummary(
        title: String, content: String?,
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (summary: String, usage: UsageInfo)

    /// 入参 items 应包含全部候选；返回选中的 id 列表（保序）+ token 用量。
    func recommendArticles(
        _ items: [ArticleSnapshot.Item],
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (ids: [UUID], usage: UsageInfo)

    /// 入参 items 应仅含已有摘要的条目（caller 负责过滤）；nil-summary 项实现侧防御性跳过。
    func generateDigest(
        items: [ArticleSnapshot.Item],
        category: AINewsBar.Category, apiKey: String, model: String
    ) async throws -> (content: String, usage: UsageInfo)

    // MARK: 新增 (Filter Stage)

    /// AI Filter：判断文章是否属于指定 cat（如财报）。仅返回 Bool（accepted/rejected）+ token 用量。
    /// caller (FilterPipeline) 负责解析失败的 retry / filterFailCount++ 逻辑。
    func classifyArticle(
        title: String, description: String, prompt: String,
        apiKey: String, model: String
    ) async throws -> (accepted: Bool, usage: UsageInfo)
}

// 旧签名默认实现：转发到新签名 + .ai（Phase 4 RefreshService 改造后可删）
extension AISummarizing {
    func generateSummary(title: String, content: String?, apiKey: String, model: String)
        async throws -> (summary: String, usage: UsageInfo)
    {
        try await generateSummary(title: title, content: content,
                                  category: .ai, apiKey: apiKey, model: model)
    }

    func recommendArticles(_ items: [ArticleSnapshot.Item], apiKey: String, model: String)
        async throws -> (ids: [UUID], usage: UsageInfo)
    {
        try await recommendArticles(items, category: .ai, apiKey: apiKey, model: model)
    }

    func generateDigest(items: [ArticleSnapshot.Item], apiKey: String, model: String)
        async throws -> (content: String, usage: UsageInfo)
    {
        try await generateDigest(items: items, category: .ai, apiKey: apiKey, model: model)
    }
}

// MARK: - PreferencesStoring（v2-multi-category 双轨）
//
// Phase 2 引入 per-cat 签名；旧签名保留作为"对 .ai 的 shortcut"避免 Phase 2 内大改 RefreshService。
// Phase 4 RefreshService 改造时迁移到新签名；届时旧签名可删（spec §5 Phase 4 验收项）。
//
// PreferencesStoring 不要求 Sendable，因为它持有 UserDefaults（非 Sendable）
// RefreshService @MainActor 调用，单线程访问足够
protocol PreferencesStoring: AnyObject {
    // MARK: 全局（无 cat 维度）

    func getAPIKey() -> String?
    func getModel() -> String

    /// UI 状态：主 popover 当前选中 tab（默认 .ai，启动时恢复）
    func loadSelectedTab() -> Category
    func saveSelectedTab(_ cat: Category)

    /// UI 状态：Settings 订阅源 Tab 当前选中 cat（默认 .ai，启动时恢复）
    func loadSettingsFeedsTab() -> Category
    func saveSettingsFeedsTab(_ cat: Category)

    // MARK: per-cat 后台刷新开关 (v2.1 新增)
    //
    // 默认 true (开启)。用户可在通用 Tab 关掉某 cat 的后台 timer 刷新省 token。
    // force refresh / lazy first-tab-switch / 手动 refresh 不受此开关影响。
    func loadAutoRefreshEnabled(for cat: Category) -> Bool
    func saveAutoRefreshEnabled(_ enabled: Bool, for cat: Category)

    // MARK: per-cat 新签名（Phase 2 引入，Phase 4 后成为正式 API）

    func loadDigest(for cat: Category) -> (content: String, date: Date)?
    func saveDigest(content: String, date: Date, for cat: Category)
    func clearDigest(for cat: Category)
    func clearRecommendState(for cat: Category)
    func loadDigestArticleCount(for cat: Category) -> Int
    func saveDigestArticleCount(_ count: Int, for cat: Category)
    func loadRecommendArticleCount(for cat: Category) -> Int
    func saveRecommendArticleCount(_ count: Int, for cat: Category)

    // MARK: 旧签名（Phase 4 RefreshService 改造后删除）

    func loadDigest() -> (content: String, date: Date)?
    func saveDigest(content: String, date: Date)
    func clearDigest()
    func clearRecommendState()
    func loadDigestArticleCount() -> Int
    func saveDigestArticleCount(_ count: Int)
    func loadRecommendArticleCount() -> Int
    func saveRecommendArticleCount(_ count: Int)
}

// 旧签名默认实现：转发到新签名 + .ai
// 这样 PreferencesService / InMemoryPrefs 仅需实现新签名即可（旧调用方编译保持兼容）
extension PreferencesStoring {
    func loadDigest() -> (content: String, date: Date)? { loadDigest(for: .ai) }
    func saveDigest(content: String, date: Date) { saveDigest(content: content, date: date, for: .ai) }
    func clearDigest() { clearDigest(for: .ai) }
    func clearRecommendState() { clearRecommendState(for: .ai) }
    func loadDigestArticleCount() -> Int { loadDigestArticleCount(for: .ai) }
    func saveDigestArticleCount(_ count: Int) { saveDigestArticleCount(count, for: .ai) }
    func loadRecommendArticleCount() -> Int { loadRecommendArticleCount(for: .ai) }
    func saveRecommendArticleCount(_ count: Int) { saveRecommendArticleCount(count, for: .ai) }
}
