import SwiftUI

struct DigestSectionView: View {
    @EnvironmentObject private var refreshService: RefreshService
    @State private var isExpanded = false
    @State private var isHovered = false

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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("今日 AI 资讯摘要")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                if let date = refreshService.lastDigestDate {
                    Text(date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if refreshService.isRegeneratingDigest {
                    ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                } else {
                    Button {
                        Task { await refreshService.forceRegenerateDigest() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .disabled(refreshService.isRegeneratingDigest || refreshService.isSummarizing)
                    .help("重新生成摘要")
                }
                Image(systemName: (isExpanded || isHovered) ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Text(digest)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit((isExpanded || isHovered) ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: isExpanded || isHovered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var placeholderBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Text("今日 AI 资讯摘要")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
            Spacer()
            if refreshService.isRegeneratingDigest || refreshService.isSummarizing {
                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                Text("生成中…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    Task { await refreshService.forceRegenerateDigest() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .disabled(refreshService.isRegeneratingDigest || refreshService.isSummarizing)
                .help("重新生成摘要")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.quaternary)
    }
}
