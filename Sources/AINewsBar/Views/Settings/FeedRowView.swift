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
            Toggle("", isOn: $feed.skipFilter)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: feed.skipFilter) { oldValue, newValue in
                    saveSkipFilterChange(newValue: newValue, revertingTo: oldValue)
                }
        }
        .help("跳过 AI 筛选（纯净源用，省 token；如 Apple Newsroom 100% 都是公司动态可开启）")
    }

    private func saveSkipFilterChange(newValue: Bool, revertingTo oldValue: Bool) {
        do {
            let updated = try FeedSettingsStore.persistSkipFilterChange(
                feed: feed, newValue: newValue, in: modelContext
            )
            // 第九轮 P2：旧 pending 被 flip 成 accepted=true 后，badge 计数变化、
            // 推荐/日报旧结果可能漏掉这批新可见文章 — postUnreadCount + 清派生缓存。
            if newValue && updated > 0 {
                refreshService.postUnreadCount(context: modelContext)
                let cat = AINewsBar.Category.from(rawValue: feed.category)
                refreshService.invalidatePerCatCache(for: cat)
            }
        } catch {
            modelContext.rollback()
            feed.skipFilter = oldValue
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
    @State private var isRevertingEnabledChange = false
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
            Toggle("", isOn: $feed.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: feed.isEnabled) { oldValue, enabled in
                    if isRevertingEnabledChange {
                        isRevertingEnabledChange = false
                        return
                    }
                    handleToggle(enabled: enabled, revertingTo: oldValue)
                }
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
            Toggle("", isOn: $feed.skipFilter)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: feed.skipFilter) { oldValue, newValue in
                    saveSkipFilterChange(newValue: newValue, revertingTo: oldValue)
                }
        }
        .help("跳过 AI 筛选（纯净源用，省 token；如 Apple Newsroom 100% 都是公司动态可开启）")
    }

    private func saveSkipFilterChange(newValue: Bool, revertingTo oldValue: Bool) {
        do {
            let updated = try FeedSettingsStore.persistSkipFilterChange(
                feed: feed, newValue: newValue, in: modelContext
            )
            // 第九轮 P2：同 FeedRowView，旧 pending → accepted=true 后 badge / 派生缓存需同步
            if newValue && updated > 0 {
                refreshService.postUnreadCount(context: modelContext)
                let cat = AINewsBar.Category.from(rawValue: feed.category)
                refreshService.invalidatePerCatCache(for: cat)
            }
        } catch {
            modelContext.rollback()
            feed.skipFilter = oldValue
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }

    private func handleToggle(enabled: Bool, revertingTo oldValue: Bool) {
        do {
            try FeedSettingsStore.persistBuiltInEnabledChange(feed: feed, enabled: enabled, in: modelContext)
            // 禁用源会删除该源所有文章，启用则下面会触发 refresh 抓回。
            // 两种路径都改变了 "isRead==false && accepted==true" 集合，必须同步
            // menu bar badge —— 主列表 @Query 会自动更新，但 badge 只靠
            // Notification (AppDelegate 监听)。不主动 post 就 stale。
            refreshService.postUnreadCount(context: modelContext)
            // 第八轮 P2：清该 cat 推荐/日报派生缓存。digest 文本可能含已删源内容；
            // 推荐 IDs 可能指向已删文章；且非空会让 auto refresh 不重生（陈旧永留）
            let cat = AINewsBar.Category.from(rawValue: feed.category)
            refreshService.invalidatePerCatCache(for: cat)
            if enabled {
                let service = refreshService
                Task { await service.refresh(cat) }
            }
        } catch {
            // P2-B: 确定性 guard 时序。
            // 1) 先 arm guard，再触发任何可能让 onChange 重入的操作（rollback 与
            //    feed.isEnabled = oldValue 都可能触发 SwiftData @Bindable 的变更通知）
            // 2) 同步路径里期望 onChange 触发恰好一次，guard handler 把它吃掉并 reset
            // 3) 兜底：用 Task 在下一个 RunLoop turn 强制 reset，避免"没触发 onChange
            //    → guard 永久卡 true → 吃掉用户下次真实 toggle"
            isRevertingEnabledChange = true
            modelContext.rollback()
            feed.isEnabled = oldValue
            Task { @MainActor in
                isRevertingEnabledChange = false
            }
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}
