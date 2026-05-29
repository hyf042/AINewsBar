import SwiftUI
import SwiftData

struct FeedRowView: View {
    @Bindable var feed: Feed
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var refreshService: RefreshService
    @State private var saveErrorMessage = ""
    @State private var showSaveErrorAlert = false
    let checkStatus: CheckStatus
    let onCheck: () async -> Void

    /// v2: 财报/新闻 cat 才显示 skipFilter toggle（AI cat 没 filter 不展示）
    private var showSkipFilterToggle: Bool {
        let cat = AINewsBar.Category.from(rawValue: feed.category)
        return CategoryConfig.for(cat).filterPrompt != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(Typography.body)
                    .foregroundStyle(TextColor.primary)
                Text(feed.url)
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if showSkipFilterToggle {
                skipFilterToggle
            }
            CheckStatusIcon(status: checkStatus)
            checkButton
        }
        .padding(.vertical, 2)
        .alert("保存失败", isPresented: $showSaveErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var checkButton: some View {
        Button { Task { await onCheck() } } label: {
            Text("检测")
                .font(Typography.caption)
                .foregroundStyle(BrandColor.accent)
        }
        .buttonStyle(.plain)
        .disabled({ if case .checking = checkStatus { return true }; return false }())
    }

    /// 跳过 AI 筛选 toggle。开启后该源新入库文章 accepted 直接 true，不跑 filter（省 token）。
    /// 用户应在 30 天用量观察后手动标"纯净源"（如 Apple Newsroom 这种 100% 通过率源）。
    private var skipFilterToggle: some View {
        HStack(spacing: 4) {
            Text("跳过筛选")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
            // 自定义 Binding 替代 $feed.skipFilter 双向绑定：set 里做可失败的持久化，
            // 成功才落库；失败 rollback（连带撤销 feed.skipFilter 的 pending 改动）后
            // SwiftUI 重渲染让 get 读回旧值，Toggle 自动回弹。无回写、无 onChange 重入，
            // 故不再需要 isReverting guard + Task 兜底那套舞蹈。
            Toggle("", isOn: Binding(
                get: { feed.skipFilter },
                set: { saveSkipFilterChange(newValue: $0) }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .help("跳过 AI 筛选（纯净源用，省 token；如 Apple Newsroom 100% 都是公司动态可开启）")
    }

    private func saveSkipFilterChange(newValue: Bool) {
        feed.skipFilter = newValue   // 进 context pending；persist 内部 save 一并落盘
        do {
            let updated = try FeedSettingsStore.persistSkipFilterChange(
                feed: feed, newValue: newValue, in: modelContext
            )
            // 行为收敛到 refreshService.handleSkipFilterPendingFlipped（postUnreadCount +
            // invalidatePerCatCache + fire-and-forget refresh），两个 FeedRow 共享。
            if newValue && updated > 0 {
                let cat = AINewsBar.Category.from(rawValue: feed.category)
                refreshService.handleSkipFilterPendingFlipped(for: cat, context: modelContext)
            }
        } catch {
            modelContext.rollback()   // 撤销 feed.skipFilter + 任何 article.accepted 改动 → Toggle 回弹
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}

struct BuiltInFeedRowView: View {
    @Bindable var feed: Feed
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var refreshService: RefreshService
    @State private var saveErrorMessage = ""
    @State private var showSaveErrorAlert = false
    let checkStatus: CheckStatus
    let onCheck: () async -> Void

    private var showSkipFilterToggle: Bool {
        let cat = AINewsBar.Category.from(rawValue: feed.category)
        return CategoryConfig.for(cat).filterPrompt != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.title)
                    .font(Typography.body)
                    .foregroundStyle(feed.isEnabled ? TextColor.primary : TextColor.secondary)
                Text(feed.url)
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if showSkipFilterToggle {
                skipFilterToggle
            }
            CheckStatusIcon(status: checkStatus)
            checkButton
            // 自定义 Binding（同 skipFilterToggle 思路）：成功才落 UI 状态，失败 rollback 回弹。
            Toggle("", isOn: Binding(
                get: { feed.isEnabled },
                set: { handleToggle(enabled: $0) }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
        .alert("保存失败", isPresented: $showSaveErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
    }

    private var checkButton: some View {
        Button { Task { await onCheck() } } label: {
            Text("检测")
                .font(Typography.caption)
                .foregroundStyle(BrandColor.accent)
        }
        .buttonStyle(.plain)
        .disabled({ if case .checking = checkStatus { return true }; return false }())
    }

    private var skipFilterToggle: some View {
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

    private func handleToggle(enabled: Bool) {
        feed.isEnabled = enabled   // 进 context pending；persist 内部 save 一并落盘
        do {
            try FeedSettingsStore.persistBuiltInEnabledChange(feed: feed, enabled: enabled, in: modelContext)
            // 禁用源会删该源所有文章，启用则下面触发 refresh 抓回。两种路径都改变了
            // "isRead==false && accepted==true" 集合，必须同步 menu bar badge（主列表 @Query
            // 自动更新，但 badge 只靠 Notification）。再清该 cat 推荐/日报派生缓存：digest 文本
            // 可能含已删源内容；推荐 IDs 可能指向已删文章；非空会让 auto refresh 不重生。
            refreshService.postUnreadCount(context: modelContext)
            let cat = AINewsBar.Category.from(rawValue: feed.category)
            refreshService.invalidatePerCatCache(for: cat)
            if enabled {
                let service = refreshService
                Task { await service.refresh(cat) }
            }
        } catch {
            modelContext.rollback()   // 撤销 feed.isEnabled + 已删 article → Toggle 回弹
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}
