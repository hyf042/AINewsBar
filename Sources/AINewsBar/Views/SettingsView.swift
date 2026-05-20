import SwiftUI
import SwiftData
import ServiceManagement

// MARK: - Check Status

enum CheckStatus {
    case idle
    case checking
    case success(Int)
    case failure(String)
}

struct SettingsView: View {
    var body: some View {
        TabView {
            FeedsSettingsView()
                .tabItem { Label("订阅源", systemImage: "list.bullet") }
            APISettingsView()
                .tabItem { Label("API", systemImage: "key") }
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 440)
    }
}

// MARK: - Feeds

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
                        try? modelContext.save()
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

// MARK: - Feed Rows

struct FeedRowView: View {
    let feed: Feed
    let checkStatus: CheckStatus
    let onCheck: () async -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title).font(.system(size: 13))
                Text(feed.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            CheckStatusIcon(status: checkStatus)
            checkButton
        }
        .padding(.vertical, 2)
    }

    private var checkButton: some View {
        Button("检测") { Task { await onCheck() } }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .disabled({ if case .checking = checkStatus { return true }; return false }())
    }
}

struct BuiltInFeedRowView: View {
    @Bindable var feed: Feed
    @Environment(\.modelContext) private var modelContext
    let checkStatus: CheckStatus
    let onCheck: () async -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(.system(size: 13))
                    .foregroundStyle(feed.isEnabled ? .primary : .secondary)
                Text(feed.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            CheckStatusIcon(status: checkStatus)
            checkButton
            Toggle("", isOn: $feed.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: feed.isEnabled) { _, enabled in handleToggle(enabled: enabled) }
        }
        .padding(.vertical, 2)
    }

    private var checkButton: some View {
        Button("检测") { Task { await onCheck() } }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .disabled({ if case .checking = checkStatus { return true }; return false }())
    }

    private func handleToggle(enabled: Bool) {
        let feedID = feed.id
        if !enabled {
            let articles = (try? modelContext.fetch(
                FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
            )) ?? []
            articles.forEach { modelContext.delete($0) }
        }
        try? modelContext.save()
        if enabled { Task { await RefreshService.shared.refresh() } }
    }
}

// MARK: - Check Status Icon

struct CheckStatusIcon: View {
    let status: CheckStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .success(let count):
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 13))
                .help("可用，共 \(count) 篇文章")
        case .failure(let msg):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 13))
                .help(msg)
        }
    }
}

// MARK: - Add Feed Sheet

struct AddFeedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    @State private var url = ""
    @State private var title = ""
    @State private var validationStatus: CheckStatus = .idle
    @State private var showForceAddAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加 RSS 订阅源").font(.headline)

            LabeledContent("标题") {
                TextField("例：My AI Blog", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("RSS URL") {
                TextField("https://example.com/feed.xml", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: url) { _, _ in validationStatus = .idle }
            }

            validationStatusRow

            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                Button("添加") { Task { await validateAndAdd() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(url.isEmpty || title.isEmpty || isValidating)
            }
        }
        .padding(20)
        .frame(width: 360)
        .alert("RSS 源无法获取内容", isPresented: $showForceAddAlert) {
            Button("取消", role: .cancel) {}
            Button("仍要添加") { addFeed() }
        } message: {
            Text("未能从该 URL 获取到文章，可能是地址错误或暂时不可用。是否仍要添加？")
        }
    }

    @ViewBuilder
    private var validationStatusRow: some View {
        switch validationStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                Text("正在检测…").font(.caption).foregroundStyle(.secondary)
            }
        case .success(let count):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                Text("检测通过，共 \(count) 篇文章").font(.caption).foregroundStyle(.secondary)
            }
        case .failure(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var isValidating: Bool {
        if case .checking = validationStatus { return true }
        return false
    }

    private func validateAndAdd() async {
        validationStatus = .checking
        do {
            let articles = try await RSSService.shared.fetchRawArticles(feedURL: url)
            if articles.isEmpty {
                validationStatus = .failure("URL 可达但未返回任何文章")
                showForceAddAlert = true
            } else {
                validationStatus = .success(articles.count)
                addFeed()
            }
        } catch {
            validationStatus = .failure(error.localizedDescription)
            showForceAddAlert = true
        }
    }

    private func addFeed() {
        let feed = Feed(title: title, url: url, isBuiltIn: false)
        modelContext.insert(feed)
        try? modelContext.save()
        isPresented = false
    }
}

// MARK: - API

struct APISettingsView: View {
    @State private var apiKey = ""
    @State private var isRevealed = false
    @State private var selectedModel = PreferencesService.defaultModel
    @State private var useCustomModel = false
    @State private var customModel = ""
    @State private var checkStatus: CheckStatus = .idle
    @ObservedObject private var refreshService = RefreshService.shared

    private static let modelGroups: [(brand: String, models: [String])] = [
        ("千问", ["qwen3.6-plus", "qwen3.5-plus", "qwen3-max-2026-01-23", "qwen3-coder-next", "qwen3-coder-plus"]),
        ("智谱", ["glm-5", "glm-4.7"]),
        ("Kimi", ["kimi-k2.5"]),
        ("MiniMax", ["MiniMax-M2.5"])
    ]

    private var effectiveModel: String {
        useCustomModel ? customModel : selectedModel
    }

    private var isChecking: Bool {
        if case .checking = checkStatus { return true }
        return false
    }

    var body: some View {
        Form {
            Section("阿里云百炼 API Key") {
                HStack {
                    if isRevealed {
                        TextField("sk-...", text: $apiKey)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                    }
                    Button(isRevealed ? "隐藏" : "显示") { isRevealed.toggle() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
                Text("前往 bailian.console.aliyun.com 获取")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("模型") {
                if !useCustomModel {
                    Picker("选择模型", selection: $selectedModel) {
                        ForEach(Self.modelGroups, id: \.brand) { group in
                            Section(group.brand) {
                                ForEach(group.models, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                } else {
                    LabeledContent("自定义模型") {
                        TextField("输入模型名称", text: $customModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                Toggle("使用自定义模型", isOn: $useCustomModel)
                    .onChange(of: useCustomModel) { _, _ in checkStatus = .idle }
            }

            Section {
                checkStatusRow
                HStack {
                    Button("检测可用性") { Task { await checkConnection() } }
                        .disabled(apiKey.isEmpty || effectiveModel.isEmpty || isChecking)
                    Spacer()
                    Button("保存") { Task { await saveAndCheck() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSettings() }
    }

    @ViewBuilder
    private var checkStatusRow: some View {
        switch checkStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                Text("检测中…").font(.caption).foregroundStyle(.secondary)
            }
        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                Text("API Key 和模型均可用").font(.caption).foregroundStyle(.secondary)
            }
        case .failure(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
                Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func loadSettings() {
        apiKey = PreferencesService.shared.getAPIKey() ?? ""
        let saved = PreferencesService.shared.getModel()
        let allModels = Self.modelGroups.flatMap(\.models)
        if allModels.contains(saved) {
            selectedModel = saved
            useCustomModel = false
        } else {
            customModel = saved
            useCustomModel = true
        }
    }

    @MainActor
    private func saveAndCheck() async {
        PreferencesService.shared.saveAPIKey(apiKey)
        PreferencesService.shared.saveModel(effectiveModel)
        await checkConnection()
    }

    @MainActor
    private func checkConnection() async {
        guard !apiKey.isEmpty, !effectiveModel.isEmpty else { return }
        checkStatus = .checking
        do {
            try await BailianService.shared.testConnection(apiKey: apiKey, model: effectiveModel)
            checkStatus = .success(1)
            RefreshService.shared.aiAvailability = .available
        } catch {
            checkStatus = .failure(error.localizedDescription)
            RefreshService.shared.aiAvailability = .unavailable(error.localizedDescription)
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        toggleLaunchAtLogin(enabled)
                    }
            }
        }
        .formStyle(.grouped)
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
