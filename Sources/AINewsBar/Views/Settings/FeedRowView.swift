import SwiftUI
import SwiftData

// MARK: - FeedRowView（自定义源行）

struct FeedRowView: View {
    let feed: Feed
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
                    .foregroundStyle(TextColor.primary)
                Text(feed.url)
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if showSkipFilterToggle {
                FeedRowSkipFilterToggle(feed: feed)
            }
            CheckStatusIcon(status: checkStatus)
            FeedRowCheckButton(checkStatus: checkStatus, onCheck: onCheck)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - BuiltInFeedRowView（内置源行，多 isEnabled toggle）

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
                FeedRowSkipFilterToggle(feed: feed)
            }
            CheckStatusIcon(status: checkStatus)
            FeedRowCheckButton(checkStatus: checkStatus, onCheck: onCheck)
            // 内置源独有：启停 toggle，自定义 Binding 失败 rollback 自动回弹
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

    private func handleToggle(enabled: Bool) {
        feed.isEnabled = enabled
        do {
            try FeedSettingsStore.persistBuiltInEnabledChange(feed: feed, enabled: enabled, in: modelContext)
            refreshService.postUnreadCount(context: modelContext)
            let cat = AINewsBar.Category.from(rawValue: feed.category)
            refreshService.invalidatePerCatCache(for: cat)
            if enabled {
                let service = refreshService
                Task { await service.refresh(cat) }
            }
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveErrorAlert = true
        }
    }
}
