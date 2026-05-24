import SwiftUI

struct RecommendItemView: View {
    let index: Int
    let article: Article
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(article.isRead ? Color.clear : BrandColor.accent)
                .frame(width: 3)

            HStack(alignment: .top, spacing: 8) {
                Text("\(index)")
                    .font(article.isRead ? Typography.caption : Typography.captionEmphasized)
                    .foregroundStyle(article.isRead ? AnyShapeStyle(TextColor.tertiary) : AnyShapeStyle(BrandColor.accent))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(article.feedTitle)
                        Spacer()
                        Text(formatArticleRelative(article.publishedAt))
                    }
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)

                    Text(article.title)
                        .font(article.isRead ? Typography.callout : Typography.calloutEmphasized)
                        .foregroundStyle(article.isRead ? TextColor.secondary : TextColor.primary)
                        .lineLimit(2)

                    if let summary = article.aiSummary {
                        Text(summary)
                            .font(Typography.caption)
                            .foregroundStyle(TextColor.secondary)
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
