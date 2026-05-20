import SwiftUI

struct ArticleRowView: View {
    let article: Article
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(article.feedTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(article.publishedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(article.title)
                .font(.system(size: 13, weight: article.isRead ? .regular : .semibold))
                .foregroundStyle(article.isRead ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let summary = article.aiSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isHovered ? nil : 1)
                    .multilineTextAlignment(.leading)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(article.isRead ? Color.clear : Color.accentColor.opacity(0.05))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
