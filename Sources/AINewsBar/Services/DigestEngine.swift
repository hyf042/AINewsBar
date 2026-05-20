import Foundation

/// 今日日报生成引擎：纯执行器，无决策、无副作用
/// 决策（gate）由调用方 (RefreshService) 完成；本引擎只负责"喂数据 → 调 AI → 包结果"
struct DigestEngine {
    struct Outcome: Sendable {
        let content: String
        let generatedAt: Date
        let articleCount: Int
    }

    let ai: any AISummarizing

    /// 返回 nil = 摘要不足（数据完整性保护）；throws = AI 调用失败
    func run(
        snapshot: ArticleSnapshot,
        apiKey: String,
        model: String
    ) async throws -> Outcome? {
        guard snapshot.summarizedCount >= 3 else { return nil }

        let content = try await ai.generateDigest(
            items: snapshot.summarized,
            apiKey: apiKey,
            model: model
        )
        Log.write("[Digest] generated from \(snapshot.summarizedCount) summaries")
        return Outcome(
            content: content,
            generatedAt: Date(),
            articleCount: snapshot.summarizedCount
        )
    }
}
