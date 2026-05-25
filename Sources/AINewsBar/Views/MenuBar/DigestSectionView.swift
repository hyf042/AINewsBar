import SwiftUI

/// v2-multi-category: 按当前 selectedTab 显示对应 cat 的日报。
struct DigestSectionView: View {
    let category: AINewsBar.Category
    @EnvironmentObject private var refreshService: RefreshService
    /// 默认展开（摘要本就是为了"一眼看完"）；保留点击折叠让用户嫌长时可手动收
    @State private var isExpanded = true

    private var perCatState: CategoryState { refreshService.state(for: category) }

    private var title: String {
        switch category {
        case .ai:        return "今日 AI 资讯摘要"
        case .earnings:  return "今日财报摘要"
        case .news:      return "今日新闻摘要"
        }
    }

    var body: some View {
        Group {
            if let digest = perCatState.dailyDigest {
                expandedBody(digest: digest)
            } else {
                placeholderBody
            }
        }
    }

    private func expandedBody(digest: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(Typography.titleEmphasized)
                    .foregroundStyle(TextColor.secondary)
                Text(title)
                    .font(Typography.titleEmphasized)
                    .foregroundStyle(TextColor.secondary)
                if let date = perCatState.lastDigestDate {
                    Text(date, style: .time)
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.tertiary)
                }
                Spacer()
                if perCatState.isRegeneratingDigest {
                    ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                } else {
                    Button {
                        Task { await refreshService.forceRegenerateDigest(category) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(Typography.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TextColor.tertiary)
                    .disabled(perCatState.isRegeneratingDigest || refreshService.isSummarizing)
                    .help("重新生成摘要")
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
            }
            if isExpanded {
                Text(digest)
                    .font(Typography.callout)
                    .foregroundStyle(TextColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surfaceMuted)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private var placeholderBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.tertiary)
            Text(title)
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.tertiary)
            Spacer()
            if perCatState.isRegeneratingDigest || refreshService.isSummarizing {
                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                Text("生成中…")
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
            } else {
                Button {
                    Task { await refreshService.forceRegenerateDigest(category) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TextColor.tertiary)
                .disabled(perCatState.isRegeneratingDigest || refreshService.isSummarizing)
                .help("重新生成摘要")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(BrandColor.surfaceMuted)
    }
}
