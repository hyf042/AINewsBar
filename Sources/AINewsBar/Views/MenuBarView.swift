import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Article.publishedAt, order: .reverse) private var articles: [Article]
    @ObservedObject private var refreshService = RefreshService.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            articleList
            Divider()
            footer
        }
        .frame(width: 380)
        .task {
            refreshService.configure(with: modelContext)
            seedBuiltInFeedsIfNeeded()
            await refreshService.refreshIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            Text("AI 资讯")
                .font(.headline)
            Spacer()
            if refreshService.isRefreshing {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
            Button {
                Task { await refreshService.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(refreshService.isRefreshing)
            .help("刷新")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var articleList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if articles.isEmpty {
                    emptyState
                } else {
                    ForEach(articles) { article in
                        ArticleRowView(article: article) {
                            openArticle(article)
                        }
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .frame(maxHeight: 480)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无文章")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var footer: some View {
        HStack {
            if let date = refreshService.lastRefreshDate {
                Text("更新于 \(date, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink {
                Text("设置")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func seedBuiltInFeedsIfNeeded() {
        let existing = (try? modelContext.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.isBuiltIn }))) ?? []
        guard existing.isEmpty else { return }
        BuiltInFeeds.makeFeeds().forEach { modelContext.insert($0) }
        try? modelContext.save()
    }

    private func openArticle(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        NSWorkspace.shared.open(url)
        article.isRead = true
        try? modelContext.save()
        NotificationCenter.default.post(name: .unreadCountChanged, object: nil)
    }
}
