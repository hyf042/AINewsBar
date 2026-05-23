import SwiftUI

/// 折叠式文章列表区块
/// - 折叠 header 永远显示（与 摘要/推荐 同款 .quaternary 风格），副文案随状态自适应
/// - 默认折叠（in-memory @State，每次菜单打开重置——产品立场：摘要+推荐是主视野）
/// - 展开后承载 loading/error/empty/list，保持白底（macOS Disclosure 标准模式）
struct ArticleListSection: View {
    let unreadArticles: [Article]
    let readArticles: [Article]
    let onOpen: (Article) -> Void

    @EnvironmentObject private var refreshService: RefreshService
    @State private var isExpanded = false

    private var totalCount: Int { unreadArticles.count + readArticles.count }

    /// 与 MenuBarView 原 listHeight 算法保持一致（实现迁移，行为不变）
    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 52
        let separatorHeight: CGFloat = readArticles.isEmpty ? 0 : 28
        return min(max(CGFloat(totalCount) * rowHeight + separatorHeight, 120), 460)
    }

    /// 5 状态副文案（风格 A：" · " 分隔）
    /// totalCount==0 && isRefreshing → 加载中…
    /// totalCount==0 && lastError    → 获取失败
    /// totalCount==0 && idle         → 暂无文章
    /// unread > 0                    → X 未读
    /// unread==0 && total>0          → 全部已读 (N 篇)
    private var subtitle: String {
        if totalCount == 0 {
            if refreshService.isRefreshing { return "加载中…" }
            if refreshService.lastError != nil { return "获取失败" }
            return "暂无文章"
        }
        let unread = unreadArticles.count
        if unread > 0 { return "\(unread) 未读" }
        return "全部已读 (\(totalCount) 篇)"
    }

    var body: some View {
        VStack(spacing: 0) {
            foldedHeader
            if isExpanded {
                Divider()
                articleListContent
            }
        }
    }

    private var foldedHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("今日文章")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            Text("· \(subtitle)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        }
    }

    @ViewBuilder
    private var articleListContent: some View {
        if refreshService.isRefreshing && totalCount == 0 {
            loadingState
        } else if let error = refreshService.lastError, totalCount == 0 {
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
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
            Text("正在获取资讯…")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("获取失败")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
                .foregroundStyle(.secondary)
            Text("暂无文章，点击刷新获取")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
