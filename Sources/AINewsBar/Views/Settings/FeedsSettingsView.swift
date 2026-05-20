import SwiftUI
import SwiftData

struct FeedsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.addedAt) private var feeds: [Feed]
    @State private var checkResults: [UUID: CheckStatus] = [:]
    @State private var isCheckingAll = false
    @State private var showAddSheet = false

    private var summaryText: String? {
        guard !checkResults.isEmpty else { return nil }
        if isCheckingAll { return "检测中…" }
        let completed = checkResults.values.filter {
            switch $0 {
            case .idle, .checking: return false
            default: return true
            }
        }
        guard !completed.isEmpty else { return nil }
        let ok = completed.filter { if case .success = $0 { return true }; return false }.count
        return "\(ok)/\(completed.count) 个源正常"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section("内置订阅源") {
                    ForEach(feeds.filter(\.isBuiltIn)) { feed in
                        BuiltInFeedRowView(
                            feed: feed,
                            checkStatus: checkResults[feed.id] ?? .idle,
                            onCheck: { await checkFeed(feed) }
                        )
                    }
                }
                Section("自定义订阅源") {
                    ForEach(feeds.filter { !$0.isBuiltIn }) { feed in
                        FeedRowView(
                            feed: feed,
                            checkStatus: checkResults[feed.id] ?? .idle,
                            onCheck: { await checkFeed(feed) }
                        )
                    }
                    .onDelete { indexSet in
                        let custom = feeds.filter { !$0.isBuiltIn }
                        indexSet.map { custom[$0] }.forEach { modelContext.delete($0) }
                        modelContext.safeSave()
                    }
                }
            }

            Divider()

            HStack {
                if let summary = summaryText {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("检测全部") {
                    Task { await checkAll() }
                }
                .disabled(isCheckingAll)
                Button("添加 RSS 源") { showAddSheet = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .sheet(isPresented: $showAddSheet) {
            AddFeedSheet(isPresented: $showAddSheet)
        }
    }

    private func checkFeed(_ feed: Feed) async {
        checkResults[feed.id] = .checking
        do {
            let articles = try await RSSService.shared.fetchRawArticles(feedURL: feed.url)
            checkResults[feed.id] = articles.isEmpty
                ? .failure("未返回任何文章")
                : .success(articles.count)
        } catch {
            checkResults[feed.id] = .failure(error.localizedDescription)
        }
    }

    private func checkAll() async {
        isCheckingAll = true
        for feed in feeds { checkResults[feed.id] = .checking }
        await withTaskGroup(of: (UUID, CheckStatus).self) { group in
            for feed in feeds {
                let feedURL = feed.url
                let feedID = feed.id
                group.addTask {
                    do {
                        let articles = try await RSSService.shared.fetchRawArticles(feedURL: feedURL)
                        return articles.isEmpty
                            ? (feedID, .failure("未返回任何文章"))
                            : (feedID, .success(articles.count))
                    } catch {
                        return (feedID, .failure(error.localizedDescription))
                    }
                }
            }
            for await (id, status) in group {
                checkResults[id] = status
            }
        }
        isCheckingAll = false
    }
}
