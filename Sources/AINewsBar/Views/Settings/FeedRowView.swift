import SwiftUI
import SwiftData

struct FeedRowView: View {
    let feed: Feed
    let checkStatus: CheckStatus
    let onCheck: () async -> Void

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
            CheckStatusIcon(status: checkStatus)
            checkButton
        }
        .padding(.vertical, 2)
    }

    private var checkButton: some View {
        Button("检测") { Task { await onCheck() } }
            .buttonStyle(.plain)
            .font(Typography.caption)
            .foregroundStyle(BrandColor.accent)
            .disabled({ if case .checking = checkStatus { return true }; return false }())
    }
}

struct BuiltInFeedRowView: View {
    @Bindable var feed: Feed
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var refreshService: RefreshService
    let checkStatus: CheckStatus
    let onCheck: () async -> Void

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
        Button("检测") { Task { await onCheck() } }
            .buttonStyle(.plain)
            .font(Typography.caption)
            .foregroundStyle(BrandColor.accent)
            .disabled({ if case .checking = checkStatus { return true }; return false }())
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
            Task { await service.refresh() }
        }
    }
}
