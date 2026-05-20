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
    @ObservedObject private var refreshService = RefreshService.shared

    private var totalCount: Int { unreadArticles.count + readArticles.count }
    @State private var isDigestExpanded = false
    @State private var isDigestHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if case .unavailable(let reason) = refreshService.aiAvailability {
                aiUnavailableBanner(reason: reason)
                Divider()
            }
            articleList
            if !unreadArticles.isEmpty || refreshService.dailyDigest != nil {
                Divider()
                recommendSection
                Divider()
                digestSection
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .task {
            refreshService.configure(with: modelContext)
            syncBuiltInFeeds()
            refreshService.postUnreadCount(context: modelContext)
            refreshService.launchBackgroundRefreshIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            Text("AI 资讯 [\(unreadArticles.count)/\(totalCount)]")
                .font(.headline)
            Spacer()
            if refreshService.isSummarizing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                    Text("AI 摘要中")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if refreshService.isRefreshing {
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
            .disabled(refreshService.isRefreshing || refreshService.isSummarizing)
            .help("刷新")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var digestSection: some View {
        Group {
            if let digest = refreshService.dailyDigest {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("今日 AI 资讯摘要")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let date = refreshService.lastDigestDate {
                            Text(date, style: .time)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: (isDigestExpanded || isDigestHovered) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Text(digest)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit((isDigestExpanded || isDigestHovered) ? nil : 5)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.2), value: isDigestExpanded || isDigestHovered)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)
                .contentShape(Rectangle())
                .onTapGesture { isDigestExpanded.toggle() }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDigestHovered = hovering
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Text("今日 AI 资讯摘要")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if refreshService.isSummarizing {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                        Text("生成中…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("待生成")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.quaternary)
            }
        }
    }

    private var recommendSection: some View {
        let picks = recommendedArticles
        let loading = picks.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(loading ? Color.secondary : Color.orange)
                Text("AI 今日推荐")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                if let date = refreshService.lastRecommendDate {
                    Text(date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if loading {
                    if refreshService.isSummarizing {
                        ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                        Text("生成中…").font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        Text("待生成").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if loading {
                ForEach([1, 2, 3], id: \.self) { i in
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 14)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                                .frame(height: 11)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        if i < 3 { Divider().padding(.leading, 34) }
                    }
                }
            } else {
                ForEach(Array(picks.enumerated()), id: \.element.id) { index, article in
                    VStack(spacing: 0) {
                        RecommendItemView(index: index + 1, article: article) {
                            openArticle(article)
                        }
                        if index < picks.count - 1 { Divider().padding(.leading, 34) }
                    }
                }
            }
        }
        .padding(.bottom, 4)
        .background(.quaternary)
    }

    private var recommendedArticles: [Article] {
        let ids = Set(refreshService.recommendedArticleIDs)
        guard !ids.isEmpty else { return [] }
        return (try? modelContext.fetch(FetchDescriptor<Article>()))?.filter { ids.contains($0.id) } ?? []
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
                .frame(height: 400)
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

    private var footer: some View {
        HStack {
            if let date = refreshService.lastRefreshDate {
                VStack(alignment: .leading, spacing: 1) {
                    Text("最后更新")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(date, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("未刷新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Text("设置")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("退出")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func syncBuiltInFeeds() {
        let expectedURLs = Set(BuiltInFeeds.all.map(\.url))
        let existing = (try? modelContext.fetch(
            FetchDescriptor<Feed>(predicate: #Predicate { $0.isBuiltIn == true })
        )) ?? []

        // 删除已失效的内置源及其文章
        let toRemove = existing.filter { !expectedURLs.contains($0.url) }
        for feed in toRemove {
            let feedID = feed.id
            let orphans = (try? modelContext.fetch(
                FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
            )) ?? []
            orphans.forEach { modelContext.delete($0) }
            modelContext.delete(feed)
        }

        // 添加缺失的新源
        let existingURLs = Set(existing.map(\.url))
        BuiltInFeeds.all
            .filter { !existingURLs.contains($0.url) }
            .map { Feed(title: $0.title, url: $0.url, isBuiltIn: true) }
            .forEach { modelContext.insert($0) }

        deduplicateArticles()
        try? modelContext.save()
    }

    private func deduplicateArticles() {
        let all = (try? modelContext.fetch(
            FetchDescriptor<Article>(sortBy: [SortDescriptor(\.publishedAt, order: .reverse)])
        )) ?? []
        var seen = Set<String>()
        for article in all {
            if seen.contains(article.url) {
                modelContext.delete(article)
            } else {
                seen.insert(article.url)
            }
        }
    }

    private func openArticle(_ article: Article) {
        guard let url = URL(string: article.url) else { return }
        NSWorkspace.shared.open(url)
        article.isRead = true
        try? modelContext.save()
        refreshService.postUnreadCount(context: modelContext)
    }
}

private struct RecommendItemView: View {
    let index: Int
    let article: Article
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                if let summary = article.aiSummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(isHovered ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
                Text(article.feedTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
