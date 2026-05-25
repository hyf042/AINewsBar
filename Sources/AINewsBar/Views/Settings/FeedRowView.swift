import SwiftUI
import SwiftData

struct FeedRowView: View {
    @Bindable var feed: Feed
    @Environment(\.modelContext) private var modelContext
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
                .onChange(of: feed.skipFilter) { _, _ in
                    modelContext.safeSave()
                }
        }
        .help("跳过 AI 筛选（纯净源用，省 token；如 Apple Newsroom 100% 都是公司动态可开启）")
    }
}

struct BuiltInFeedRowView: View {
    @Bindable var feed: Feed
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var refreshService: RefreshService
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
                .onChange(of: feed.isEnabled) { _, enabled in handleToggle(enabled: enabled) }
        }
        .padding(.vertical, 2)
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
                .onChange(of: feed.skipFilter) { _, _ in
                    modelContext.safeSave()
                }
        }
        .help("跳过 AI 筛选（纯净源用，省 token；如 Apple Newsroom 100% 都是公司动态可开启）")
    }

    private func handleToggle(enabled: Bool) {
        let feedID = feed.id
        if !enabled {
            let articles = modelContext.safeFetch(
                FetchDescriptor<Article>(predicate: #Predicate { $0.feedID == feedID })
            )
            articles.forEach { modelContext.delete($0) }
        }
        modelContext.safeSave()
        if enabled {
            let service = refreshService
            let cat = AINewsBar.Category.from(rawValue: feed.category)
            Task { await service.refresh(cat) }
        }
    }
}
