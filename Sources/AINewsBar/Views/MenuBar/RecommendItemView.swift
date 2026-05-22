import SwiftUI

struct RecommendItemView: View {
    let index: Int
    let article: Article
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // 未读色条：贴左缘 3pt，与 index 色调统一；已读透明保留宽度避免抖动
            Rectangle()
                .fill(article.isRead ? Color.clear : Color.orange)
                .frame(width: 3)

            HStack(alignment: .top, spacing: 8) {
                Text("\(index)")
                    .font(.system(size: 11, weight: article.isRead ? .regular : .bold))
                    .foregroundStyle(article.isRead ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(article.feedTitle)
                        Spacer()
                        Text(formatArticleRelative(article.publishedAt))
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    Text(article.title)
                        .font(.system(size: 12, weight: article.isRead ? .regular : .semibold))
                        .foregroundStyle(article.isRead ? .secondary : .primary)
                        .lineLimit(2)

                    if let summary = article.aiSummary {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(isHovered ? nil : 1)
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(.easeInOut(duration: 0.15), value: isHovered)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
