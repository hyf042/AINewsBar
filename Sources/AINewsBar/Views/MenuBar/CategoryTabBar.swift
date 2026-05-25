import SwiftUI
import SwiftData

/// v2-multi-category: 顶部 segmented 切 tab + per-tab 未读 badge。
///
/// 每 tab 独立 @Query count 未读数。@Query 谓词在 init 时捕获，
/// 3 个 cat 各 1 个 @Query 是确定性写法（vs 动态 predicate 不可靠）。
struct CategoryTabBar: View {
    @Binding var selectedTab: AINewsBar.Category

    @Query(filter: #Predicate<Article> { $0.isRead == false && $0.category == "ai" })
    private var aiUnread: [Article]
    @Query(filter: #Predicate<Article> { $0.isRead == false && $0.category == "earnings" })
    private var earningsUnread: [Article]
    @Query(filter: #Predicate<Article> { $0.isRead == false && $0.category == "news" })
    private var newsUnread: [Article]

    private func unreadCount(for cat: AINewsBar.Category) -> Int {
        switch cat {
        case .ai:        return aiUnread.count
        case .earnings:  return earningsUnread.count
        case .news:      return newsUnread.count
        }
    }

    private func label(for cat: AINewsBar.Category) -> String {
        let count = unreadCount(for: cat)
        return count > 0 ? "\(cat.displayName) (\(count))" : cat.displayName
    }

    var body: some View {
        Picker("", selection: $selectedTab) {
            ForEach(AINewsBar.Category.allCases, id: \.self) { cat in
                Text(label(for: cat)).tag(cat)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
