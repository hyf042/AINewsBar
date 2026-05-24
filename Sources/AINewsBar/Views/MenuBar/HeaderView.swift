import SwiftUI

struct HeaderView: View {
    let unreadCount: Int
    let totalCount: Int
    @EnvironmentObject private var refreshService: RefreshService

    var body: some View {
        HStack {
            Text("AI 资讯 [\(unreadCount)/\(totalCount)]")
                .font(Typography.headline)
                .foregroundStyle(TextColor.primary)
            Spacer()
            if refreshService.isSummarizing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                    Text("AI 摘要中")
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.tertiary)
                }
            } else if refreshService.isRefreshing {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
            Button {
                Task { await refreshService.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(Typography.body)
            }
            .buttonStyle(.plain)
            .disabled(refreshService.isRefreshing || refreshService.isSummarizing)
            .help("刷新")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
