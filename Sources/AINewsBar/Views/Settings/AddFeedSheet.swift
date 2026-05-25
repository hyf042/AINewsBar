import SwiftUI
import SwiftData

struct AddFeedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var refreshService: RefreshService
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
        // P3 第六轮 review #1：strict fetch 去重 —— 旧 `try? fetch ?? []` 会让
        // DB 查询失败被当成"没有重复"，false-empty 写路径。fetch 失败必须中止保存，
        // 别静默插入可能导致用户数据出问题。
        let normalized = Self.normalize(url)
        let existing: [Feed]
        do {
            existing = try modelContext.fetch(FetchDescriptor<Feed>())
        } catch {
            saveErrorMessage = "查询现有订阅源失败，请重试：\(error.localizedDescription)"
            showSaveErrorAlert = true
            return
        }
        if let dupe = existing.first(where: { Self.normalize($0.url) == normalized }) {
            saveErrorMessage = "已存在相同 URL 的订阅源（\(dupe.title)），请勿重复添加"
            showSaveErrorAlert = true
            return
        }

        // P3 第六轮 review #1：trim 后再存，避免空白被持久化。验证路径（validateAndAdd
        // 走 RSSService.fetch）也 trim 后送出会更彻底，但 RSSService 已加 scheme 校验
        // 上游兜底；这里只对存盘 URL 做最小 normalize（保留 case 与 query）。
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let feed = Feed(title: trimmedTitle, url: trimmedURL,
                        isBuiltIn: false, category: selectedCategory)
        modelContext.insert(feed)
        do {
            try modelContext.safeSaveOrThrow()
            // P3 第六轮 review #3：保存成功后触发该分类刷新。
            // 旧路径仅关闭 sheet；若该 tab 刚刷新过，lastRefreshDate 会挡住 lazy
            // refresh —— 用户加完源等不到新文章，体感像"加了没用"。
            // refresh(_:) 走 inflight 复用，与正在跑的刷新合并，不会双开 AI。
            let service = refreshService
            let cat = selectedCategory
            isPresented = false
            Task { await service.refresh(cat) }
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }

    /// URL 规范化（仅用于去重比对，不用于存盘）：去首尾空白 / 小写 / 去尾斜杠。
    /// 不去 protocol：http vs https 是真不同（前者明文）；不去 query：?format=rss 有意义。
    /// 故意保守 —— 误拒绝比误合并好（用户能改 URL 重试，合并坏数据无法回滚）。
    private static func normalize(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
