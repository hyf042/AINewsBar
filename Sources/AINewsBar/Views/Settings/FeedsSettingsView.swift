import SwiftUI
import SwiftData

struct FeedsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var refreshService: RefreshService
    @Query(sort: \Feed.addedAt) private var feeds: [Feed]
    @State private var selectedCategory: AINewsBar.Category = .ai
    @State private var checkResults: [UUID: CheckStatus] = [:]
    @State private var isCheckingAll = false
    /// 第十七轮 P3：检测运行 token。每次发起检测（单个 / 全部）递增并捕获，
    /// 切 cat 时也递增。in-flight task 回写前比对 —— 不是当前 run 就丢弃，
    /// 避免"检测全部过程中切 cat，旧分类结果回写污染新 tab"。
    @State private var checkRunID = 0
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
                // 第十六轮 P3：切 cat 清空 checkResults。summaryText 统计整个 checkResults，
                // 切 cat 不清会让汇总跨分类串显示（AI 检测完"11/11 个源正常"切到财报/新闻
                // 仍显示旧分类汇总）。检测结果本就属于某一 cat 的 feed，切走即应失效。
                checkResults = [:]
                // 第十七轮 P3：bump runID 让正在跑的 checkAll/checkFeed 的 in-flight 回写失效，
                // 否则旧分类 task 完成后仍写回 checkResults 重新污染新 tab。
                isCheckingAll = false
                checkRunID += 1
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
        // 第十七轮 P3：捕获 runID，await 返回后比对当前 runID（切 cat 会 bump）。
        checkRunID += 1
        let runID = checkRunID
        checkResults[feed.id] = .checking
        do {
            let articles = try await RSSService.shared.fetchRawArticles(feedURL: feed.url)
            guard runID == checkRunID else { return }
            checkResults[feed.id] = articles.isEmpty
                ? .failure("未返回任何文章")
                : .success(articles.count)
        } catch {
            guard runID == checkRunID else { return }
            checkResults[feed.id] = .failure(error.localizedDescription)
        }
    }

    private func deleteCustomFeeds(_ feeds: [Feed]) {
        do {
            try FeedSettingsStore.deleteCustomFeeds(feeds, in: modelContext)
            // 删除自定义源同时删该源所有文章（在 FeedSettingsStore 内）。badge 必须同步
            // —— 主列表靠 @Query 自动更新，但 menu bar badge 只靠 Notification。
            refreshService.postUnreadCount(context: modelContext)
            // 第八轮 P2：清涉及到的 cat 推荐/日报派生缓存（同 FeedRowView 处理）。
            // 删除可能跨多个 cat（虽然 UI 当前限当前 picker cat，仍按入参 feed 各自 cat 清）
            let affectedCats = Set(feeds.map { AINewsBar.Category.from(rawValue: $0.category) })
            for cat in affectedCats {
                refreshService.invalidatePerCatCache(for: cat)
            }
        } catch {
            modelContext.rollback()
            deleteErrorMessage = error.localizedDescription
            showDeleteErrorAlert = true
        }
    }

    /// v2: 检测范围限当前 picker 选中 cat 的 feeds（避免一次性检测 30+ 个源）
    private func checkAll() async {
        // 第十七轮 P3：捕获 runID。切 cat（onChange bump）或下一次检测会让本 run 失效，
        // group 内 in-flight 回写前比对，避免旧分类结果污染新 tab。
        checkRunID += 1
        let runID = checkRunID
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
                guard runID == checkRunID else { continue }
                checkResults[id] = status
            }
        }
        // 仅当仍是本 run 才复位 isCheckingAll（切 cat 已置 false / 新 run 已置 true，不覆盖）
        guard runID == checkRunID else { return }
        isCheckingAll = false
    }
}
