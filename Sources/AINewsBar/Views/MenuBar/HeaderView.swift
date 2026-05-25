import SwiftUI

/// v2-multi-category: 按当前 selectedTab 显示标题 + per-cat refresh。
struct HeaderView: View {
    let category: AINewsBar.Category
    let unreadCount: Int
    let totalCount: Int
    @EnvironmentObject private var refreshService: RefreshService

    private var perCatState: CategoryState { refreshService.state(for: category) }

    private var title: String {
        switch category {
        case .ai:        return "AI 资讯"
        case .earnings:  return "财报"
        case .news:      return "新闻"
        }
    }

    var body: some View {
        HStack {
            Text("\(title) [\(unreadCount)/\(totalCount)]")
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
            } else if perCatState.isRefreshing {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            }
            Button {
                Task { await refreshService.refresh(category) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(Typography.body)
            }
            .buttonStyle(.plain)
            .disabled(perCatState.isRefreshing || refreshService.isSummarizing)
            .help("刷新当前 tab")
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
