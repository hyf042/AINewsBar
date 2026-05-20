import Foundation

/// 今日日报生成引擎：纯业务，无副作用
/// 决策 (Trigger) 与执行分离；force/auto 合一同一份 run 实现
struct DigestEngine {
    enum Trigger: Sendable {
        case auto(
            hasNewArticles: Bool,
            isPresent: Bool,
            lastDate: Date?,
            currentCount: Int,
            lastCount: Int,
            hasEnoughCoverage: Bool,
            regenerateInterval: TimeInterval,
            deltaThreshold: Int
        )
        case forced
    }

    struct Outcome: Sendable {
        let content: String
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
        case .auto(let hasNew, let isPresent, let lastDate, let curr, let last,
                   let coverage, let interval, let delta):
            guard coverage else {
                Log.write("[Digest] skip — coverage below threshold")
                return nil
            }
            guard RefreshDecision.shouldRegenerateDigest(
                hasNewArticles: hasNew,
                isPresent: isPresent,
                lastDate: lastDate,
                currentCount: curr,
                lastCount: last,
                regenerateInterval: interval,
                deltaThreshold: delta
            ) else {
                Log.write("[Digest] skip — delta=\(curr - last), hasNew=\(hasNew)")
                return nil
            }
        case .forced:
            break
        }
        guard snapshot.summarizedCount >= 3 else { return nil }

        // Execute
        let content = try await ai.generateDigest(
            articleSummaries: snapshot.summarizedPairs,
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
