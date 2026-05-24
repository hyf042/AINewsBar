import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openSettings) private var openSettings
    @Query(filter: #Predicate<Article> { $0.isRead == false },
           sort: \Article.publishedAt, order: .reverse)
    private var unreadArticles: [Article]
    @Query(filter: #Predicate<Article> { $0.isRead == true },
           sort: \Article.publishedAt, order: .reverse)
    private var readArticles: [Article]
    @EnvironmentObject private var refreshService: RefreshService

    private var totalCount: Int { unreadArticles.count + readArticles.count }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(unreadCount: unreadArticles.count, totalCount: totalCount)
            Divider()
            if case .unavailable(let reason) = refreshService.aiAvailability {
                aiUnavailableBanner(reason: reason)
                Divider()
            }
            // 新布局：摘要+推荐变常态显示（骨架屏兜底），文章列表沉到底部折叠
            // 删除了原有 `if !unreadArticles.isEmpty || refreshService.dailyDigest != nil` guard
            DigestSectionView()
            Divider()
            RecommendSectionView(articles: unreadArticles + readArticles,
                                 onOpen: openArticle)
            Divider()
            ArticleListSection(unreadArticles: unreadArticles,
                               readArticles: readArticles,
                               onOpen: openArticle)
            Divider()
            FooterView()
        }
        .frame(width: 380)
        // startup 已在 AppDelegate.applicationDidFinishLaunching；view 出现时不再重复初始化
    }

    private func aiUnavailableBanner(reason: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandColor.accent)
                .font(Typography.caption)
            Text("AI 不可用：\(reason)")
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

    private func openArticle(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        NSWorkspace.shared.open(url)
        article.isRead = true
        modelContext.safeSave()
        refreshService.postUnreadCount(context: modelContext)
    }
}
