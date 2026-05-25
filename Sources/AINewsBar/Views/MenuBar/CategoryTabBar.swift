import SwiftUI
import SwiftData

/// v2-multi-category: 顶部 segmented 切 tab + per-tab 未读 badge。
///
/// 不用系统 Picker(.segmented)：macOS 实现按内容宽度，3 个 tab 无法等分撑满。
/// 自定义 HStack 3 个 Button 等宽撑满 popover 宽度。
///
/// 每 tab 独立 @Query count 未读数 (3 个 @Query 静态谓词)。
struct CategoryTabBar: View {
    @Binding var selectedTab: AINewsBar.Category

    @Query(filter: #Predicate<Article> { $0.category == "ai" })
    private var aiArticles: [Article]
    @Query(filter: #Predicate<Article> { $0.category == "earnings" })
    private var earningsArticles: [Article]
    @Query(filter: #Predicate<Article> { $0.category == "news" })
    private var newsArticles: [Article]

    private func unreadCount(for cat: AINewsBar.Category) -> Int {
        let source: [Article]
        switch cat {
        case .ai:        source = aiArticles
        case .earnings:  source = earningsArticles
        case .news:      source = newsArticles
        }
        return source.filter { !$0.isRead && $0.accepted == true }.count
    }

    private func label(for cat: AINewsBar.Category) -> String {
        let count = unreadCount(for: cat)
        return count > 0 ? "\(cat.displayName) (\(count))" : cat.displayName
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AINewsBar.Category.allCases, id: \.self) { cat in
                tabButton(for: cat)
            }
        }
        .padding(4)
        .background(BrandColor.surfaceMuted)
    }

    private func tabButton(for cat: AINewsBar.Category) -> some View {
        let isSelected = (cat == selectedTab)
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { selectedTab = cat }
        } label: {
            Text(label(for: cat))
                .font(Typography.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? AnyShapeStyle(TextColor.primary) : AnyShapeStyle(TextColor.secondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        // unemphasizedSelectedContentBackgroundColor: macOS native segmented
                        // selected 色 — 亮模式接近白，暗模式中灰 (≈#3A3A3C)，与 surfaceMuted
                        // 父背景对比强；vs controlBackgroundColor 暗模式与 surfaceMuted 太接近
                        .fill(isSelected ? AnyShapeStyle(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                                         : AnyShapeStyle(Color.clear))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.primary.opacity(0.15) : Color.clear,
                                        lineWidth: 0.5)
                        )
                        .shadow(color: isSelected ? .black.opacity(0.12) : .clear,
                                radius: 1.5, y: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
