import SwiftUI
import SwiftData

// MARK: - 共享 FeedRow 子组件（消除 FeedRowView / BuiltInFeedRowView 的复制粘贴）

/// "检测"按钮：异步触发 RSS 校验，检测中禁用。
struct FeedRowCheckButton: View {
    let checkStatus: CheckStatus
    let onCheck: () async -> Void

    var body: some View {
        Button { Task { await onCheck() } } label: {
            Text("检测")
                .font(Typography.caption)
                .foregroundStyle(BrandColor.accent)
        }
        .buttonStyle(.plain)
        .disabled({ if case .checking = checkStatus { return true }; return false }())
    }
}

/// "跳过 AI 筛选" toggle：开启后该源新入库文章 accepted 直接 true，不跑 filter（省 token）。
/// 用自定义 Binding 直接做持久化，失败 rollback 自动回弹 Toggle。
struct FeedRowSkipFilterToggle: View {
    @Bindable var feed: Feed
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var refreshService: RefreshService
    @State private var saveErrorMessage = ""
    @State private var showSaveErrorAlert = false

    /// 仅当该 feed 的 cat 配了 filterPrompt 时才显示（AI cat 没有 filter）
    init(feed: Feed) {
        self.feed = feed
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("跳过筛选")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
            Toggle("", isOn: Binding(
                get: { feed.skipFilter },
                set: { saveSkipFilterChange(newValue: $0) }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .help("跳过 AI 筛选（纯净源用，省 token；如 Apple Newsroom 100% 都是公司动态可开启）")
        .alert("保存失败", isPresented: $showSaveErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private func saveSkipFilterChange(newValue: Bool) {
        feed.skipFilter = newValue
        do {
            let updated = try FeedSettingsStore.persistSkipFilterChange(
                feed: feed, newValue: newValue, in: modelContext
            )
            if newValue && updated > 0 {
                let cat = AINewsBar.Category.from(rawValue: feed.category)
                refreshService.handleSkipFilterPendingFlipped(for: cat, context: modelContext)
            }
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}
