import Foundation

/// AI 推荐生成引擎：纯执行器，无决策、无副作用
/// 决策（gate）由调用方 (RefreshService) 完成；本引擎只负责"喂数据 → 调 AI → 包结果"
struct RecommendEngine {
    struct Outcome: Sendable {
        let ids: [UUID]
        let generatedAt: Date
        let articleCount: Int
        let usage: UsageInfo
    }

    let ai: any AISummarizing

    /// 返回 nil = 候选不足（数据完整性保护）；throws = AI 调用失败
    func run(
        snapshot: ArticleSnapshot,
        apiKey: String,
        model: String
    ) async throws -> Outcome? {
        guard snapshot.all.count >= 3 else { return nil }

        let (ids, usage) = try await ai.recommendArticles(snapshot.all, apiKey: apiKey, model: model)
        Log.write("[Recommend] picked \(ids.count) from \(snapshot.all.count) articles")
        return Outcome(
            ids: ids,
            generatedAt: Date(),
            articleCount: snapshot.summarizedCount,
            usage: usage
        )
    }
}
