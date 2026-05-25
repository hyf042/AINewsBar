import SwiftUI
import SwiftData

struct FeedsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.addedAt) private var feeds: [Feed]
    @State private var selectedCategory: AINewsBar.Category = .ai
    @State private var checkResults: [UUID: CheckStatus] = [:]
    @State private var isCheckingAll = false
    @State private var showAddSheet = false
    @State private var deleteErrorMessage = ""
    @State private var showDeleteErrorAlert = false

    /// 当前 picker 选中 cat 的 feeds
    private var filteredFeeds: [Feed] {
        feeds.filter { AINewsBar.Category.from(rawValue: $0.category) == selectedCategory }
    }

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
            // v2: 顶部 Picker 切 cat
            Picker("", selection: $selectedCategory) {
                ForEach(AINewsBar.Category.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .onAppear {
                selectedCategory = PreferencesService.shared.loadSettingsFeedsTab()
            }
            .onChange(of: selectedCategory) { _, newValue in
                PreferencesService.shared.saveSettingsFeedsTab(newValue)
            }

            Divider()

            List {
                Section("内置订阅源") {
                    ForEach(filteredFeeds.filter(\.isBuiltIn)) { feed in
                        BuiltInFeedRowView(
                            feed: feed,
                            checkStatus: checkResults[feed.id] ?? .idle,
                            onCheck: { await checkFeed(feed) }
                        )
                    }
                }
                Section("自定义订阅源") {
                    ForEach(filteredFeeds.filter { !$0.isBuiltIn }) { feed in
                        FeedRowView(
                            feed: feed,
                            checkStatus: checkResults[feed.id] ?? .idle,
                            onCheck: { await checkFeed(feed) }
                        )
                    }
                    .onDelete { indexSet in
                        let custom = filteredFeeds.filter { !$0.isBuiltIn }
                        deleteCustomFeeds(indexSet.map { custom[$0] })
                    }
                }
            }

            Divider()

            HStack {
                if let summary = summaryText {
                    Text(summary)
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.secondary)
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
            // v2: AddFeedSheet default cat = 当前 picker 选中
            AddFeedSheet(isPresented: $showAddSheet, defaultCategory: selectedCategory)
        }
        .alert("删除失败", isPresented: $showDeleteErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
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

    private func deleteCustomFeeds(_ feeds: [Feed]) {
        do {
            try FeedSettingsStore.deleteCustomFeeds(feeds, in: modelContext)
        } catch {
            modelContext.rollback()
            deleteErrorMessage = error.localizedDescription
            showDeleteErrorAlert = true
        }
    }

    /// v2: 检测范围限当前 picker 选中 cat 的 feeds（避免一次性检测 30+ 个源）
    private func checkAll() async {
        isCheckingAll = true
        let toCheck = filteredFeeds
        for feed in toCheck { checkResults[feed.id] = .checking }
        await withTaskGroup(of: (UUID, CheckStatus).self) { group in
            for feed in toCheck {
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
