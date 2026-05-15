import SwiftUI
import SwiftData
import ServiceManagement

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
        .frame(width: 480, height: 360)
    }
}

// MARK: - Feeds

struct FeedsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Feed.addedAt) private var feeds: [Feed]
    @State private var newURL = ""
    @State private var newTitle = ""
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section("内置订阅源") {
                    ForEach(feeds.filter(\.isBuiltIn)) { feed in
                        FeedRowView(feed: feed)
                    }
                }
                Section("自定义订阅源") {
                    ForEach(feeds.filter { !$0.isBuiltIn }) { feed in
                        FeedRowView(feed: feed)
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
                Spacer()
                Button("添加 RSS 源") { showAddSheet = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .sheet(isPresented: $showAddSheet) {
            AddFeedSheet(isPresented: $showAddSheet)
        }
    }
}

struct FeedRowView: View {
    let feed: Feed

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(feed.title)
                .font(.system(size: 13))
            Text(feed.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct AddFeedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    @State private var url = ""
    @State private var title = ""

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
            }

            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                Button("添加") { addFeed() }
                    .buttonStyle(.borderedProminent)
                    .disabled(url.isEmpty || title.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
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
    @State private var apiKey: String = ""
    @State private var isRevealed = false

    var body: some View {
        Form {
            Section("OpenAI API Key") {
                HStack {
                    if isRevealed {
                        TextField("sk-...", text: $apiKey)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                    }
                    Button(isRevealed ? "隐藏" : "显示") {
                        isRevealed.toggle()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.accentColor)
                }

                Text("用于生成文章 AI 摘要，Key 安全存储在 Keychain 中")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("保存") {
                    KeychainService.shared.saveOpenAIKey(apiKey)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = KeychainService.shared.getOpenAIKey() ?? ""
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
