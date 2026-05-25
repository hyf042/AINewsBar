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
    /// v2-multi-category: category 参数选 cat-specific prompt（默认 .ai 兼容 Phase 4 前调用方）
    func run(
        snapshot: ArticleSnapshot,
        category: AINewsBar.Category = .ai,
        apiKey: String,
        model: String
    ) async throws -> Outcome? {
        // 与 BailianService.recommendArticles 内部 guard 阈值保持一致（5 篇）
        // 前置 guard 避免无谓 LLM 调用；推荐展示数从 3 升 5 后同步抬升
        guard snapshot.all.count >= 5 else { return nil }

        let (ids, usage) = try await ai.recommendArticles(
            snapshot.all, category: category, apiKey: apiKey, model: model
        )
        guard ids.count >= 3 else {
            throw BailianError.malformedResponse(reason: "推荐响应有效序号不足（\(ids.count)/5）")
        }
        Log.write("[Recommend][\(category.rawValue)] picked \(ids.count) from \(snapshot.all.count) articles")
        return Outcome(
            ids: ids,
            generatedAt: Date(),
            articleCount: snapshot.summarizedCount,
            usage: usage
        )
    }
}
