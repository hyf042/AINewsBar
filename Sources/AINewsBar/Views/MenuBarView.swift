import SwiftUI
import SwiftData

/// v2-multi-category 顶层：CategoryTabBar 切 tab + per-cat 子视图。
/// 6 个 @Query (每 cat × unread/read) 静态写法 (@Query 不支持运行时动态 predicate，
/// 谓词在 init 时捕获 — spec §6 踩坑 #6)。3 套数据按 selectedTab 派发给子视图。
struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var refreshService: RefreshService

    /// 当前选中 tab。启动从 prefs 恢复；切换时 onChange 持久化。
    @State private var selectedTab: AINewsBar.Category = .ai

    // MARK: - per-cat @Query (3 cat × 1 个；用单条件避免 type-check 超时)
    //
    // @Query 谓词 3 条件 (isRead && category && accepted) 用 && 链编译器 type-check 超时，
    // 故拆分：@Query 只过滤 category，accepted/isRead 在 view 层 filter。
    // 内存 filter 数据量小（每 cat 几十-上百文章），性能开销可忽略。

    @Query(filter: #Predicate<Article> { $0.category == "ai" },
           sort: \Article.publishedAt, order: .reverse)
    private var aiArticles: [Article]

    @Query(filter: #Predicate<Article> { $0.category == "earnings" },
           sort: \Article.publishedAt, order: .reverse)
    private var earningsArticles: [Article]

    @Query(filter: #Predicate<Article> { $0.category == "news" },
           sort: \Article.publishedAt, order: .reverse)
    private var newsArticles: [Article]

    // MARK: - Computed (view 层 filter accepted/isRead)

    private var currentArticles: [Article] {
        switch selectedTab {
        case .ai:        return aiArticles
        case .earnings:  return earningsArticles
        case .news:      return newsArticles
        }
    }

    /// 仅 accepted=true 的文章进 UI（filter rejected 不显示）
    private var currentUnread: [Article] {
        currentArticles.filter { !$0.isRead && $0.accepted == true }
    }

    private var currentRead: [Article] {
        currentArticles.filter { $0.isRead && $0.accepted == true }
    }

    private var totalCount: Int { currentUnread.count + currentRead.count }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(category: selectedTab,
                       unreadCount: currentUnread.count,
                       totalCount: totalCount)
            Divider()
            CategoryTabBar(selectedTab: $selectedTab)
            Divider()
            bannerContent
            DigestSectionView(category: selectedTab,
                              articles: currentUnread + currentRead)
                .id(selectedTab)  // cat 切换时重建，重置 @State isExpanded
            Divider()
            RecommendSectionView(category: selectedTab,
                                 articles: currentUnread + currentRead,
                                 onOpen: openArticle)
            Divider()
            ArticleListSection(category: selectedTab,
                               unreadArticles: currentUnread,
                               readArticles: currentRead,
                               onOpen: openArticle)
                .id(selectedTab)  // cat 切换时重建，重置 @State isExpanded（默认折叠）
            Divider()
            FooterView(category: selectedTab)
        }
        .frame(width: 380)
        .onAppear {
            // 启动恢复上次选中 tab；同时尝试触发该 cat lazy refresh（财报/新闻首次切入）
            selectedTab = PreferencesService.shared.loadSelectedTab()
        }
        .onChange(of: selectedTab) { _, newValue in
            PreferencesService.shared.saveSelectedTab(newValue)
            // 切到从未刷新过的 cat 时 lazy load (首启 AI-only + 用户首次切 tab 路径)
            if refreshService.state(for: newValue).lastRefreshDate == nil {
                Task { await refreshService.refreshIfNeeded(newValue) }
            }
        }
    }

    // MARK: - Banner (startup vs global vs per-cat 区分)

    /// Banner 优先级：startupError > globalAIError > per-cat aiAvailability
    /// startupError 不会被任何 AI 成功路径清除，独立显示让根因不被掩盖。
    @ViewBuilder
    private var bannerContent: some View {
        if let startup = refreshService.startupError {
            startupBanner(message: startup)
            Divider()
        } else if let global = refreshService.globalAIError {
            globalBanner(error: global)
            Divider()
        } else if case .unavailable(let reason) = refreshService.state(for: selectedTab).aiAvailability {
            perCatBanner(reason: reason)
            Divider()
        }
    }

    /// 启动错误 banner（非 AI 故障；sticky 到重启）
    private func startupBanner(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColor.accent)
                .font(Typography.caption)
            Text("启动错误：\(message)")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(BrandColor.accentSoft)
    }

    /// 全局错误 banner（API Key 错 / 网络 / 配额 — 影响所有 cat，sticky 一条）
    private func globalBanner(error: GlobalAIError) -> some View {
        let message: String
        switch error {
        case .invalidAPIKey:       message = "API Key 无效或未配置"
        case .forbidden:           message = "API Key 有效，但当前模型未授权（请检查模型开通状态）"
        case .networkUnreachable:  message = "网络不可达"
        case .quotaExceeded:       message = "API 配额超限"
        case .other(let msg):      message = msg
        }
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColor.accent)
                .font(Typography.caption)
            Text("AI 不可用：\(message)")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
                .lineLimit(1)
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Text("去设置")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColor.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(BrandColor.accentSoft)
    }

    /// per-cat 业务错误 banner（仅当前 cat 内显示）
    private func perCatBanner(reason: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColor.accent)
                .font(Typography.caption)
            Text("[\(selectedTab.displayName)] AI 不可用：\(reason)")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
                .lineLimit(1)
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Text("去设置")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColor.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(BrandColor.accentSoft)
    }

    // MARK: - Actions

    private func openArticle(_ article: Article) {
        // P2 第六轮 review：文章 URL 源自外部 RSS，NSWorkspace.open 不能开 file://、
        // javascript:、shell: 等任意 scheme。这是个简单的攻击面收紧。
        guard let url = URL(string: article.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            Log.write("[Open] refusing non-http(s) URL: \(article.url)")
            return
        }
        guard NSWorkspace.shared.open(url) else {
            Log.write("[Open] failed to open article URL: \(article.url)")
            return
        }
        guard !article.isRead else { return }
        let wasRead = article.isRead
        article.isRead = true
        do {
            try modelContext.safeSaveOrThrow()
        } catch {
            modelContext.rollback()
            article.isRead = wasRead
            Log.write("[Open] failed to persist read state for article \(article.id): \(error)")
            return
        }
        refreshService.postUnreadCount(context: modelContext)
    }
}
