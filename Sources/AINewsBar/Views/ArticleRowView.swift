import SwiftUI

struct ArticleRowView: View {
    let article: Article
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 未读 dot —— 4pt 实心圆点 + brand orange + 顶部对齐首行
            // 已读项透明保留宽度避免抖动
            Circle()
                .fill(article.isRead ? Color.clear : BrandColor.accent)
                .frame(width: 4, height: 4)
                .padding(.top, 5)  // 与首行 baseline 对齐（经验值）

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(article.feedTitle)
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.tertiary)
                    Spacer()
                    Text(formatArticleRelative(article.publishedAt))
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.tertiary)
                }

                // ⚠️ 标题字号保留 fixed Font.system(size: 13)（ArticleRow 例外，spec v3 修订 0.1-1）
                Text(article.title)
                    .font(.system(size: 13, weight: article.isRead ? .regular : .semibold))
                    .foregroundStyle(article.isRead ? TextColor.secondary : TextColor.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let summary = article.aiSummary {
                    Text(summary)
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.secondary)
                        .lineLimit(isHovered ? nil : 1)
                        .multilineTextAlignment(.leading)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
