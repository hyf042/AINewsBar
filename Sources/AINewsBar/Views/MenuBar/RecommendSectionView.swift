import SwiftUI

/// v2-multi-category: 按当前 selectedTab 显示对应 cat 的推荐。
struct RecommendSectionView: View {
    let category: AINewsBar.Category
    /// 来自父视图的 @Query 投影（已过滤当前 cat）；用于在内存中按 id 查找推荐文章（避免重复 fetch）
    let articles: [Article]
    let onOpen: (Article) -> Void
    @EnvironmentObject private var refreshService: RefreshService

    private var perCatState: CategoryState { refreshService.state(for: category) }
    private var isCurrentCatSummarizing: Bool { refreshService.isSummarizing(category: category) }

    private var title: String {
        switch category {
        case .ai:        return "AI 今日推荐"
        case .earnings:  return "财报今日推荐"
        case .news:      return "新闻今日推荐"
        }
    }

    /// #4 优化：复用父视图 @Query 数据，按 id 内存查找并保序，O(n) 无 IO
    /// 注意：用 uniquingKeysWith 而非 uniqueKeysWithValues —— SwiftData 容灾路径
    /// (BuiltInFeeds.deduplicateArticles) 的存在证明历史曾出现过重复 Article id，
    /// uniqueKeysWithValues 在重复 key 时会 fatalError 让推荐区直接崩溃
    private var picks: [Article] {
        let ids = perCatState.recommendedArticleIDs
        guard !ids.isEmpty else { return [] }
        let byID = Dictionary(articles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// RecommendEngine 阈值：候选 < recommendCount 不生成。
    /// 走 CategoryConfig.recommendCount 保证 prompt / parser cap / UI threshold 一致。
    private var recommendThreshold: Int { CategoryConfig.for(category).recommendCount }

    /// 第十二轮 P2 review：候选数按"有摘要"算，与 RecommendEngine 一致。
    /// 旧实现按 articles.count 显示，5 篇里只 3 篇有摘要时 UI 仍说"候选够了"，
    /// 但 Engine 实际不调 AI（summarized < 5），永远 placeholder 像 bug。
    private var summarizedCount: Int {
        articles.filter { $0.aiSummary != nil }.count
    }

    var body: some View {
        let loading = picks.isEmpty
        let candidateShort = summarizedCount < recommendThreshold
        VStack(alignment: .leading, spacing: 0) {
            header(loading: loading)
            if loading {
                if candidateShort {
                    candidateShortFootnote
                } else {
                    placeholderRows
                }
            } else {
                pickRows
            }
        }
        .padding(.bottom, 4)
        .background(BrandColor.surfaceMuted)
    }

    /// 候选不足时显示文案而非 N 个占位条（避免永远 placeholder 像 bug）
    private var candidateShortFootnote: some View {
        HStack {
            Text("候选不足，需 ≥\(recommendThreshold) 篇有摘要文章 (当前 \(summarizedCount))")
                .font(Typography.caption)
                .foregroundStyle(TextColor.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func header(loading: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(Typography.titleEmphasized)
                .foregroundStyle(loading ? AnyShapeStyle(TextColor.secondary) : AnyShapeStyle(BrandColor.accent))
            Text(title)
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.secondary)
            if let date = perCatState.lastRecommendDate {
                Text(date, style: .time)
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
            }
            Spacer()
            if perCatState.isRegeneratingRecommend {
                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                Text("生成中…").font(Typography.caption).foregroundStyle(TextColor.tertiary)
            } else if loading && isCurrentCatSummarizing {
                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                Text("生成中…").font(Typography.caption).foregroundStyle(TextColor.tertiary)
            } else {
                Button {
                    Task { await refreshService.forceRegenerateRecommend(category) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(TextColor.tertiary)
                .disabled(perCatState.isRegeneratingRecommend || isCurrentCatSummarizing)
                .help("重新生成推荐")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var placeholderRows: some View {
        let count = recommendThreshold
        return ForEach(Array(1...count), id: \.self) { i in
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i)")
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(TextColor.tertiary)
                        .frame(width: 14)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 11)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if i < count { Divider().padding(.leading, 34) }
            }
        }
    }

    private var pickRows: some View {
        // 不再用 Divider 分隔 —— 横线会在两项之间挤断左侧色条 1pt，
        // 改由 RecommendItemView 自身的 vertical padding (6pt) 自然分隔
        ForEach(Array(picks.enumerated()), id: \.element.id) { index, article in
            RecommendItemView(index: index + 1, article: article) {
                onOpen(article)
            }
        }
    }
}
