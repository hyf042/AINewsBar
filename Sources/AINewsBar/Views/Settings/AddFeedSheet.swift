import SwiftUI
import SwiftData

struct AddFeedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    @State private var url = ""
    @State private var title = ""
    @State private var validationStatus: CheckStatus = .idle
    @State private var showForceAddAlert = false

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
        let feed = Feed(title: title, url: url, isBuiltIn: false)
        modelContext.insert(feed)
        modelContext.safeSave()
        isPresented = false
    }
}
