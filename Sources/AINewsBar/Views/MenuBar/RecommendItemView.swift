import SwiftUI

struct RecommendItemView: View {
    let index: Int
    let article: Article
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(article.isRead ? Typography.caption : Typography.captionEmphasized)
                .foregroundStyle(article.isRead ? AnyShapeStyle(TextColor.tertiary) : AnyShapeStyle(BrandColor.accent))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(article.feedTitle)
                        .foregroundStyle(TextColor.secondaryWeak)
                    Spacer()
                    Text(formatArticleRelative(article.publishedAt))
                        .foregroundStyle(TextColor.tertiary)
                }
                .font(Typography.caption)

                Text(article.title)
                    .font(article.isRead ? Typography.callout : Typography.calloutEmphasized)
                    .foregroundStyle(article.isRead ? TextColor.secondary : TextColor.primary)
                    .lineLimit(2)

                if let summary = article.aiSummary {
                    // summary 永久 2 行（删 hover 切换 lineLimit）。
                    // hover 改 lineLimit 会让 row 内在高度变化 → 父 VStack 高度变化 →
                    // popover NSWindow 重算 size → SwiftUI 6.x + MenuBarExtra(.window)
                    // 在 _postWindowNeedsUpdateConstraints 链路抛 NSException → SIGTRAP。
                    // fixedSize(vertical: true) 必需：嵌套 VStack 内的 Text 默认按 ideal
                    // size 渲染 1 行，需明确告诉 SwiftUI "宽度由父决定，高度按 ideal 多行算"。
                    Text(summary)
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.leading, 12)   // 3pt 色条 + 9pt 内容缩进
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .overlay(alignment: .leading) {
            // 色条用 overlay 而非 HStack child：
            // overlay 内 Rectangle 自动 fill row 完整 frame（含上下 padding 6pt）。
            // 旧实现 Rectangle 作为 HStack child + frame(maxHeight: .infinity)
            // 在 HStack(alignment: .center) 里被当作上限不强制撑满，
            // 加上 summary fixedSize 后 HStack layout 协商不再给它完整高度 →
            // row 上下 padding 区透明 → 视觉上 row 之间不连续。
            // overlay 不参与 HStack layout 协商，直接按 receiver frame 渲染 → 贯穿。
            Rectangle()
                .fill(article.isRead ? Color.clear : BrandColor.accent)
                .frame(width: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
