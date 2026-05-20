import SwiftUI

struct RecommendItemView: View {
    let index: Int
    let article: Article
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                if let summary = article.aiSummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(isHovered ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
                Text(article.feedTitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
