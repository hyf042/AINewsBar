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
    /// 第十七轮 P2：强制添加路径的待保存草稿。validateAndAdd 点击瞬间捕获，
    /// alert "仍要添加" 只保存这一份，不重读可能已被用户改动的当前 UI 状态。
    @State private var pendingDraft: FeedDraft?

    /// 点击"添加"瞬间捕获的不可变草稿（已 trim）。校验、去重、存盘全程只用它，
    /// 避免"校验通过 A，RSS 请求期间用户改成 B，实际保存 B"的非原子边界。
    private struct FeedDraft {
        let url: String
        let title: String
        let category: AINewsBar.Category
    }

    /// 第九轮 P3：统一 trim 值。空值判断、validate fetch、去重比对、存盘都用同一份。
    /// 旧路径 line 56 用原始值判空，line 105 用原始值 fetch，line 141 才 trim →
    /// "   " 标题能通过 disabled gate 进入校验；带前后空白的 URL 可能校验失败但 trim 后
    /// 不同的 URL 又写入；"校验失败但仍要添加"的强制路径里更容易触发不一致。
    private var trimmedURL: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

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
                    .disabled(trimmedURL.isEmpty || trimmedTitle.isEmpty || isValidating)
            }
        }
        .padding(20)
        .frame(width: 360)
        .alert("RSS 源无法获取内容", isPresented: $showForceAddAlert) {
            Button("取消", role: .cancel) { pendingDraft = nil }
            Button("仍要添加") { if let draft = pendingDraft { addFeed(draft) } }
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
        // 第十七轮 P2：点击瞬间捕获 draft（已 trim），整个异步流程只认这份。
        // 用户在 RSS 请求期间改 URL/标题/分类不再影响校验与保存的一致性。
        let draft = FeedDraft(url: trimmedURL, title: trimmedTitle, category: selectedCategory)
        validationStatus = .checking
        do {
            // 用 draft.url 校验：与最终存盘 URL 完全一致，避免"校验通过 X 但存了 trim(X)"
            // 或反向"校验失败 X 但用户强制添加后存了 trim(X)"两类不一致
            let articles = try await RSSService.shared.fetchRawArticles(feedURL: draft.url)
            if articles.isEmpty {
                validationStatus = .failure("URL 可达但未返回任何文章")
                pendingDraft = draft
                showForceAddAlert = true
            } else {
                validationStatus = .success(articles.count)
                addFeed(draft)
            }
        } catch {
            validationStatus = .failure(error.localizedDescription)
            pendingDraft = draft
            showForceAddAlert = true
        }
    }

    private func addFeed(_ draft: FeedDraft) {
        // P3 第六轮 review #1：strict fetch 去重 —— 旧 `try? fetch ?? []` 会让
        // DB 查询失败被当成"没有重复"，false-empty 写路径。fetch 失败必须中止保存，
        // 别静默插入可能导致用户数据出问题。
        // 第九轮 P3：用 draft.url 比对，与 validateAndAdd / 存盘路径一致
        // 第十三轮 P3：用统一 URLNormalizer（保守归一化，保留 query/path 大小写）
        let normalized = URLNormalizer.normalize(draft.url)
        let existing: [Feed]
        do {
            existing = try modelContext.fetch(FetchDescriptor<Feed>())
        } catch {
            saveErrorMessage = "查询现有订阅源失败，请重试：\(error.localizedDescription)"
            showSaveErrorAlert = true
            return
        }
        if let dupe = existing.first(where: { URLNormalizer.normalize($0.url) == normalized }) {
            saveErrorMessage = "已存在相同 URL 的订阅源（\(dupe.title)），请勿重复添加"
            showSaveErrorAlert = true
            return
        }

        let feed = Feed(title: draft.title, url: draft.url,
                        isBuiltIn: false, category: draft.category)
        modelContext.insert(feed)
        do {
            try modelContext.safeSaveOrThrow()
            // P3 第六轮 review #3：保存成功后触发该分类刷新。
            // 旧路径仅关闭 sheet；若该 tab 刚刷新过，lastRefreshDate 会挡住 lazy
            // refresh —— 用户加完源等不到新文章，体感像"加了没用"。
            // refresh(_:) 走 inflight 复用，与正在跑的刷新合并，不会双开 AI。
            let service = refreshService
            let cat = draft.category
            pendingDraft = nil
            isPresented = false
            Task { await service.refresh(cat) }
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }

}
