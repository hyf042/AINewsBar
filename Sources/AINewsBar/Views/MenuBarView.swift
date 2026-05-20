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

    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 52
        let separatorHeight: CGFloat = readArticles.isEmpty ? 0 : 28
        return min(max(CGFloat(totalCount) * rowHeight + separatorHeight, 120), 460)
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(unreadCount: unreadArticles.count, totalCount: totalCount)
            Divider()
            if case .unavailable(let reason) = refreshService.aiAvailability {
                aiUnavailableBanner(reason: reason)
                Divider()
            }
            articleList
            if !unreadArticles.isEmpty || refreshService.dailyDigest != nil {
                Divider()
                RecommendSectionView(articles: unreadArticles + readArticles,
                                     onOpen: openArticle)
                Divider()
                DigestSectionView()
            }
            Divider()
            FooterView()
        }
        .frame(width: 380)
        .task {
            refreshService.configure(with: modelContext)
            BuiltInFeeds.syncInto(context: modelContext)
            refreshService.postUnreadCount(context: modelContext)
            refreshService.launchBackgroundRefreshIfNeeded()
        }
    }

    private var articleList: some View {
        Group {
            if refreshService.isRefreshing && totalCount == 0 {
                loadingState
            } else if let error = refreshService.lastError, totalCount == 0 {
                errorState(error)
            } else if totalCount == 0 {
                emptyState
            } else {
                List {
                    ForEach(unreadArticles) { article in
                        ArticleRowView(article: article) {
                            openArticle(article)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.visible)
                    }
                    if !readArticles.isEmpty {
                        HStack {
                            Text("已读 (\(readArticles.count))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(nsColor: .separatorColor).opacity(0.12))

                        ForEach(readArticles) { article in
                            ArticleRowView(article: article) {
                                openArticle(article)
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.visible)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: listHeight)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("正在获取资讯…")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("获取失败")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无文章，点击刷新获取")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func aiUnavailableBanner(reason: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
            Text("AI 不可用：\(reason)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("去设置") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.08))
    }

    private func openArticle(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        NSWorkspace.shared.open(url)
        article.isRead = true
        modelContext.safeSave()
        refreshService.postUnreadCount(context: modelContext)
    }
}

