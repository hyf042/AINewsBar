import SwiftUI
import SwiftData

struct AddFeedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    /// v2: 默认 cat 来自父 view 当前选中的 Picker；用户可下拉改
    let defaultCategory: AINewsBar.Category
    @State private var url = ""
    @State private var title = ""
    @State private var selectedCategory: AINewsBar.Category
    @State private var validationStatus: CheckStatus = .idle
    @State private var showForceAddAlert = false
    @State private var saveErrorMessage = ""
    @State private var showSaveErrorAlert = false

    init(isPresented: Binding<Bool>, defaultCategory: AINewsBar.Category = .ai) {
        self._isPresented = isPresented
        self.defaultCategory = defaultCategory
        self._selectedCategory = State(initialValue: defaultCategory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加 RSS 订阅源")
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.primary)

            LabeledContent("标题") {
                TextField("例：My AI Blog", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("RSS URL") {
                TextField("https://example.com/feed.xml", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: url) { _, _ in validationStatus = .idle }
            }
            LabeledContent("分类") {
                Picker("", selection: $selectedCategory) {
                    ForEach(AINewsBar.Category.allCases, id: \.self) { cat in
                        Text(cat.displayName).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
        .alert("保存失败", isPresented: $showSaveErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
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
                Text("正在检测…").font(Typography.caption).foregroundStyle(TextColor.secondary)
            }
        case .success(let count):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(Typography.caption)
                Text("检测通过，共 \(count) 篇文章").font(Typography.caption).foregroundStyle(TextColor.secondary)
            }
        case .failure(let msg):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BrandColor.accent).font(Typography.caption)
                Text(msg).font(Typography.caption).foregroundStyle(TextColor.secondary).lineLimit(2)
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
        // P3 review：按 normalized URL 去重。重复 feed 会重复抓 RSS、设置页重复显示、
        // 失败统计重复噪声；按 article URL 去重的下游路径救不了上游重复 fetch。
        // 不做"订阅合并"复杂方案 —— 拒绝即可，用户改 URL 或先删旧的。
        let normalized = Self.normalize(url)
        let existing = (try? modelContext.fetch(FetchDescriptor<Feed>())) ?? []
        if let dupe = existing.first(where: { Self.normalize($0.url) == normalized }) {
            saveErrorMessage = "已存在相同 URL 的订阅源（\(dupe.title)），请勿重复添加"
            showSaveErrorAlert = true
            return
        }

        let feed = Feed(title: title, url: url,
                        isBuiltIn: false, category: selectedCategory)
        modelContext.insert(feed)
        do {
            try modelContext.safeSaveOrThrow()
            isPresented = false
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }

    /// URL 规范化：去首尾空白 / 小写 / 去尾斜杠。
    /// 不去 protocol：http vs https 是真不同（前者明文）；不去 query：?format=rss 有意义。
    /// 故意保守 —— 误拒绝比误合并好（用户能改 URL 重试，合并坏数据无法回滚）。
    private static func normalize(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
