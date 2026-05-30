import SwiftUI

/// 折叠式文章列表区块
/// - 折叠 header 永远显示（与 摘要/推荐 同款 .quaternary 风格），副文案随状态自适应
/// - 默认折叠（in-memory @State，每次菜单打开重置——产品立场：摘要+推荐是主视野）
/// - 展开后承载 loading/error/empty/list，保持白底（macOS Disclosure 标准模式）
struct ArticleListSection: View {
    let category: AINewsBar.Category
    let unreadArticles: [Article]
    let readArticles: [Article]
    let onOpen: (Article) -> Void
    /// 父级共享的"主视野互斥状态"。点 header 在 .recommend ↔ .article 之间 toggle。
    /// 折叠态（.recommend）下仅渲染 foldedHeader，文章列表隐藏。
    @Binding var expandedSection: ExpandedSection

    @EnvironmentObject private var refreshService: RefreshService

    private var perCatState: CategoryState { refreshService.state(for: category) }
    private var totalCount: Int { unreadArticles.count + readArticles.count }

    private var title: String {
        switch category {
        case .ai:        return "今日 AI 文章"
        case .earnings:  return "今日财报文章"
        case .news:      return "今日新闻文章"
        }
    }

    /// 单行高度估算 95pt：摘要从 1 行升 2 行后实际单 row ~93pt（标题 2 行 + 摘要 2 行 + padding）。
    /// max 480pt：上限上调 — 互斥折叠落地后 article 展开时 recommend 自动折，
    /// 推荐区让出 ~400pt 给 article，配合 MenuBarView .frame(maxHeight: 1000) 兜底，
    /// article 展开后可见 ~5 行文章。文章超量时 List 内 scroll 而非 popover 撑高。
    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 95
        let separatorHeight: CGFloat = readArticles.isEmpty ? 0 : 28
        return min(max(CGFloat(totalCount) * rowHeight + separatorHeight, 120), 480)
    }

    /// 5 状态副文案（风格 A：" · " 分隔）
    /// totalCount==0 && isRefreshing → 加载中…
    /// totalCount==0 && lastError    → 获取失败
    /// totalCount==0 && idle         → 暂无文章
    /// unread > 0                    → X 未读
    /// unread==0 && total>0          → 全部已读 (N 篇)
    private var subtitle: String {
        if totalCount == 0 {
            if perCatState.isRefreshing { return "加载中…" }
            if perCatState.lastError != nil { return "获取失败" }
            return "暂无文章"
        }
        let unread = unreadArticles.count
        if unread > 0 { return "\(unread) 未读" }
        return "全部已读 (\(totalCount) 篇)"
    }

    var body: some View {
        let isExpanded = expandedSection == .article
        return VStack(spacing: 0) {
            foldedHeader(isExpanded: isExpanded)
            if isExpanded {
                Divider()
                articleListContent
            }
        }
    }

    /// foldedHeader toggle 在 .recommend ↔ .article 之间。
    /// 单字段互斥模型：点 article header = 切到 .article（recommend 自动折）/
    /// 已展开时点 = 切回 .recommend（recommend 自动展开）。
    private func foldedHeader(isExpanded: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet")
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.secondary)
            Text(title)
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.secondary)
            Text("· \(subtitle)")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
            Spacer()
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.surfaceMuted)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedSection = (expandedSection == .article) ? .recommend : .article
            }
        }
    }

    @ViewBuilder
    private var articleListContent: some View {
        if perCatState.isRefreshing && totalCount == 0 {
            loadingState
        } else if let error = perCatState.lastError, totalCount == 0 {
            errorState(error)
        } else if totalCount == 0 {
            emptyState
        } else {
            articleList
        }
    }

    private var articleList: some View {
        List {
            ForEach(unreadArticles) { article in
                ArticleRowView(article: article) {
                    onOpen(article)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.visible)
            }
            if !readArticles.isEmpty {
                HStack {
                    Text("已读 (\(readArticles.count))")
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color(nsColor: .separatorColor).opacity(0.12))

                ForEach(readArticles) { article in
                    ArticleRowView(article: article) {
                        onOpen(article)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.visible)
                }
            }
        }
        .listStyle(.plain)
        .frame(height: listHeight)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("正在获取…")
                .foregroundStyle(TextColor.secondary)
                .font(Typography.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(TextColor.secondary)
            Text("获取失败")
                .font(Typography.body)
                .foregroundStyle(TextColor.secondary)
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "newspaper")
                .font(.largeTitle)
                .foregroundStyle(TextColor.secondary)
            Text("暂无文章，点击刷新获取")
                .foregroundStyle(TextColor.secondary)
                .font(Typography.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
