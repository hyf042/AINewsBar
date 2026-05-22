import SwiftUI

struct RecommendSectionView: View {
    /// 来自父视图的 @Query 投影；用于在内存中按 id 查找推荐文章（避免重复 fetch）
    let articles: [Article]
    let onOpen: (Article) -> Void
    @EnvironmentObject private var refreshService: RefreshService

    /// #4 优化：复用父视图 @Query 数据，按 id 内存查找并保序，O(n) 无 IO
    /// 注意：用 uniquingKeysWith 而非 uniqueKeysWithValues —— SwiftData 容灾路径
    /// (BuiltInFeeds.deduplicateArticles) 的存在证明历史曾出现过重复 Article id，
    /// uniqueKeysWithValues 在重复 key 时会 fatalError 让推荐区直接崩溃
    private var picks: [Article] {
        let ids = refreshService.recommendedArticleIDs
        guard !ids.isEmpty else { return [] }
        let byID = Dictionary(articles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    var body: some View {
        let loading = picks.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            header(loading: loading)
            if loading {
                placeholderRows
            } else {
                pickRows
            }
        }
        .padding(.bottom, 4)
        .background(.quaternary)
    }

    private func header(loading: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.footnote)
                .foregroundStyle(loading ? Color.secondary : Color.orange)
            Text("AI 今日推荐")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            if let date = refreshService.lastRecommendDate {
                Text(date, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if refreshService.isRegeneratingRecommend {
                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                Text("生成中…").font(.caption2).foregroundStyle(.tertiary)
            } else if loading && refreshService.isSummarizing {
                ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
                Text("生成中…").font(.caption2).foregroundStyle(.tertiary)
            } else {
                Button {
                    Task { await refreshService.forceRegenerateRecommend() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .disabled(refreshService.isRegeneratingRecommend || refreshService.isSummarizing)
                .help("重新生成推荐")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var placeholderRows: some View {
        ForEach([1, 2, 3], id: \.self) { i in
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 11)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                if i < 3 { Divider().padding(.leading, 34) }
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
