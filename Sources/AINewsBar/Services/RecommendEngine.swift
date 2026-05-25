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
    /// per-cat recommendCount 来自 CategoryConfig；caller 不传，避免与 prompt/parser cap 漂移
    func run(
        snapshot: ArticleSnapshot,
        category: AINewsBar.Category,
        apiKey: String,
        model: String
    ) async throws -> Outcome? {
        let count = CategoryConfig.for(category).recommendCount
        // 与 BailianService.recommendArticles 内部 guard 阈值保持一致（count 篇）
        // 前置 guard 避免无谓 LLM 调用；阈值与 UI 候选不足文案同源
        guard snapshot.all.count >= count else { return nil }

        let (ids, usage) = try await ai.recommendArticles(
            snapshot.all, count: count,
            category: category, apiKey: apiKey, model: model
        )
        // 最低有效阈值：要求至少返回 count 的一半（向上取整），低于此判定 AI 输出退化
        let minimumValid = (count + 1) / 2
        guard ids.count >= minimumValid else {
            throw BailianError.malformedResponse(reason: "推荐响应有效序号不足（\(ids.count)/\(count)）")
        }
        Log.write("[Recommend][\(category.rawValue)] picked \(ids.count) from \(snapshot.all.count) articles (target=\(count))")
        return Outcome(
            ids: ids,
            generatedAt: Date(),
            articleCount: snapshot.summarizedCount,
            usage: usage
        )
    }
}
