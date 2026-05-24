import SwiftUI

struct DigestSectionView: View {
    @EnvironmentObject private var refreshService: RefreshService
    // 默认展开（摘要本就是为了"一眼看完"）；保留点击折叠让用户嫌长时可手动收
    @State private var isExpanded = true

    var body: some View {
        Group {
            if let digest = refreshService.dailyDigest {
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
                Text("今日 AI 资讯摘要")
                    .font(Typography.titleEmphasized)
                    .foregroundStyle(TextColor.secondary)
                if let date = refreshService.lastDigestDate {
                    Text(date, style: .time)
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.tertiary)
                }
                Spacer()
                if refreshService.isRegeneratingDigest {
                    ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                } else {
                    Button {
                        Task { await refreshService.forceRegenerateDigest() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(Typography.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TextColor.tertiary)
                    .disabled(refreshService.isRegeneratingDigest || refreshService.isSummarizing)
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
            Text("今日 AI 资讯摘要")
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.tertiary)
            Spacer()
            if refreshService.isRegeneratingDigest || refreshService.isSummarizing {
                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                Text("生成中…")
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
            } else {
                Button {
                    Task { await refreshService.forceRegenerateDigest() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TextColor.tertiary)
                .disabled(refreshService.isRegeneratingDigest || refreshService.isSummarizing)
                .help("重新生成摘要")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(BrandColor.surfaceMuted)
    }
}
