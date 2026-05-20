import Foundation

/// AI 推荐生成引擎：纯业务，无副作用
/// 决策 (Trigger) 与执行分离；force/auto 合一同一份 run 实现
struct RecommendEngine {
    enum Trigger: Sendable {
        case auto(hasNewArticles: Bool, isEmpty: Bool, currentCount: Int, lastCount: Int, deltaThreshold: Int)
        case forced
    }

    struct Outcome: Sendable {
        let ids: [UUID]
        let generatedAt: Date
        let articleCount: Int
    }

    let ai: any AISummarizing

    /// 返回 nil = 决策不需要执行；throws = AI 调用失败
    func run(
        trigger: Trigger,
        snapshot: ArticleSnapshot,
        apiKey: String,
        model: String
    ) async throws -> Outcome? {
        // Gate
        switch trigger {
        case .auto(let hasNew, let isEmpty, let curr, let last, let delta):
            guard RefreshDecision.shouldRegenerateRecommend(
                hasNewArticles: hasNew,
                isEmpty: isEmpty,
                currentCount: curr,
                lastCount: last,
                deltaThreshold: delta
            ) else {
                Log.write("[Recommend] skip — delta=\(curr - last), hasNew=\(hasNew)")
                return nil
            }
        case .forced:
            break
        }
        guard snapshot.all.count >= 3 else { return nil }

        // Execute
        let ids = try await ai.recommendArticles(
            snapshot.pickInputs, apiKey: apiKey, model: model
        )
        Log.write("[Recommend] picked \(ids.count) from \(snapshot.all.count) articles")
        return Outcome(
            ids: ids,
            generatedAt: Date(),
            articleCount: snapshot.summarizedCount
        )
    }
}
