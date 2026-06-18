import Foundation
import SwiftData

// MARK: - AI Pipeline 组件（Filter / Summary / Recommend / Digest / Commit）
// 从 RefreshService 主文件拆分（C2 review），降低单文件行数，不改任何逻辑。

extension RefreshService {

    // MARK: - Filter Stage Outcome

    /// Filter stage 产出：persisted 决定是否继续 AI pipeline；newlyAccepted 是本轮 filter 新判
    /// accepted=true 的篇数 —— 代表"本轮新增的用户可见文章"，供派生内容触发决策（避免全 reject 时白烧 token）。
    struct FilterStageOutcome {
        let persisted: Bool
        let newlyAccepted: Int
        /// noop / 无 pending：放行后续 AI，无新可见内容。
        static let proceed = FilterStageOutcome(persisted: true, newlyAccepted: 0)
        /// 持久化失败：中止 AI pipeline。
        static let abort = FilterStageOutcome(persisted: false, newlyAccepted: 0)
    }

    // MARK: - Filter Stage

    /// AI Filter：仅对配了 filterPrompt 的 cat 启用。
    /// fetch accepted==nil && filterFailCount<3 → FilterPipeline → 写回 accepted / 累加 filterFailCount。
    func runFilterStage(cat: AINewsBar.Category, context: ModelContext) async -> FilterStageOutcome {
        let config = CategoryConfig.for(cat)
        guard let filterPrompt = config.filterPrompt else { return .proceed }

        let catRaw = cat.rawValue
        let maxFailures = filterMaxFailures
        let pending: [Article]
        do {
            pending = try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate {
                    $0.category == catRaw && $0.accepted == nil && $0.filterFailCount < maxFailures
                })
            )
        } catch {
            Log.write("[Filter][\(catRaw)] fetch pending failed: \(error)")
            mutate(cat) { $0.lastError = "数据库查询失败，跳过筛选" }
            return .abort
        }
        guard !pending.isEmpty else { return .proceed }
        guard let (apiKey, model) = ensureCredentials(cat: cat) else { return .abort }

        let tasks = pending.map {
            FilterPipeline.Task(
                id: $0.id, title: $0.title,
                description: $0.content ?? "",
                category: cat
            )
        }
        let pipeline = FilterPipeline(ai: ai, maxConcurrent: 5, promptTemplate: filterPrompt)
        let result = await pipeline.run(tasks: tasks, apiKey: apiKey, model: model)

        // 写回 Article（用 id 重 fetch alive，避免持有跨 await @Model 引用）。
        // 仅 classificationFailedIds 计入 filterFailCount；transientFailedIds（HTTP/网络/credential）
        // 保持 accepted=nil，下轮 refresh 的 pending 谓词会再抓到重试，避免网络抖动永久 reject 财报文章。
        let acceptedSet = Set(result.acceptedIds)
        let rejectedSet = Set(result.rejectedIds)
        let classificationFailedSet = Set(result.classificationFailedIds)
        // transient 不写（accepted/filterFailCount 都不动），省一次 fetch
        let writeIds = Array(acceptedSet) + Array(rejectedSet) + Array(classificationFailedSet)

        var persistSucceeded = true
        if !writeIds.isEmpty {
            let alive: [Article]
            do {
                alive = try context.safeFetchOrThrow(
                    FetchDescriptor<Article>(predicate: #Predicate { writeIds.contains($0.id) })
                )
            } catch {
                mutate(cat) { $0.lastError = "数据库查询失败，跳过筛选结果保存" }
                Log.write("[Filter][\(catRaw)] refetch alive articles failed: \(error)")
                persistSucceeded = false
                alive = []
            }

            for article in alive {
                if acceptedSet.contains(article.id) {
                    article.accepted = true
                } else if rejectedSet.contains(article.id) {
                    article.accepted = false
                } else if classificationFailedSet.contains(article.id) {
                    article.recordFilterFailure(maxBeforeReject: filterMaxFailures)
                    if article.accepted == false {
                        Log.write("[Filter][\(catRaw)] permanently rejecting after \(filterMaxFailures) classification failures: \(article.title.prefix(30))")
                    }
                }
            }
            if persistSucceeded {
                do {
                    try context.safeSaveOrThrow()
                } catch {
                    context.rollback()
                    mutate(cat) { $0.lastError = "筛选结果保存失败" }
                    Log.write("[Filter][\(catRaw)] save failed: \(error)")
                    persistSucceeded = false
                }
            }
        }

        // transient 错误期间至少把 globalAIError 提示用户（不污染 per-cat unavailable，可能下轮自愈）。
        if let transientGlobal = result.firstTransientGlobalError {
            globalAIError = transientGlobal
        }

        // filter 持久化成功后补 postUnreadCount：财报文章入库时 accepted=nil 被过滤掉，
        // 这里 accepted 变 true/false 改变计数，menu bar label 只听通知，不补就 stale。
        if persistSucceeded && !writeIds.isEmpty {
            postUnreadCount(context: context)
        }

        // accepted + rejected 记 token；classificationFailed 与 transientFailed 不记 token；
        // 仅 classificationFailed 记 recordFailure（transient 不算 AI 服务质量损坏）。
        for usageInfo in result.usages {
            usage?.record(scene: .filter, category: cat, model: model,
                          info: usageInfo, success: persistSucceeded)
        }
        for _ in result.classificationFailedIds {
            usage?.recordFailure(scene: .filter, category: cat, model: model)
        }
        // newlyAccepted = 本轮 filter 判 accepted=true 数（持久化失败时无意义，置 0）。
        return FilterStageOutcome(
            persisted: persistSucceeded,
            newlyAccepted: persistSucceeded ? acceptedSet.count : 0
        )
    }

    // MARK: - AI Pipeline (per-cat)

    func processAI(cat: AINewsBar.Category, context: ModelContext, hasNewArticles: Bool) async {
        guard let (apiKey, model) = ensureCredentials(cat: cat) else { return }

        let catRaw = cat.rawValue
        let pendingTasks: [SummaryPipeline.Task]
        do {
            // 仅处理该 cat、accepted=true、aiSummary=nil 的文章
            let pending = try context.safeFetchOrThrow(
                FetchDescriptor<Article>(predicate: #Predicate {
                    $0.category == catRaw && $0.accepted == true && $0.aiSummary == nil
                })
            )
            pendingTasks = pending.map {
                SummaryPipeline.Task(id: $0.id, title: $0.title, content: $0.content, category: cat)
            }
        } catch {
            mutate(cat) { $0.lastError = "数据库查询失败，跳过本次 AI 处理" }
            return
        }
        let coverage: Bool
        if pendingTasks.isEmpty {
            coverage = true
        } else {
            beginSummaryPipeline(cat)
            let result = await summaryPipeline.run(tasks: pendingTasks, apiKey: apiKey, model: model)
            endSummaryPipeline(cat)
            if let globalError = result.globalError {
                self.globalAIError = globalError
            } else if !result.completed.isEmpty {
                clearGlobalAIErrorAfterAISuccess()
            }
            commitSummaries(cat: cat, result: result, model: model, context: context)
            coverage = result.completionRate >= coverageThreshold
            if !coverage && !result.failedIds.isEmpty {
                mutate(cat) {
                    $0.aiAvailability = .unavailable("摘要调用多数失败 (\(result.failedIds.count)/\(result.total))")
                }
            }
        }

        let snapshot: ArticleSnapshot
        do {
            snapshot = try ArticleSnapshot.captureOrThrow(from: context, category: cat)
        } catch {
            mutate(cat) { $0.lastError = "数据库查询失败，跳过推荐/摘要生成" }
            return
        }
        guard snapshot.summarizedCount >= 3 else { return }

        let s = state(for: cat)
        // coverage gate 同时挡 recommend 与 digest："摘要质量不足就不生成派生内容"。
        // RecommendEngine 用 snapshot.summarized，coverage 不足意味候选含 nil-summary 文章。
        if !coverage {
            Log.write("[Recommend][\(catRaw)] skip — coverage below threshold")
        } else if RefreshDecision.shouldRegenerateRecommend(
            hasNewArticles: hasNewArticles,
            isEmpty: s.recommendedArticleIDs.isEmpty,
            currentCount: snapshot.summarizedCount,
            lastCount: s.recommendArticleCount,
            deltaThreshold: summaryDeltaThreshold
        ) {
            await runRecommend(cat: cat, snapshot: snapshot, apiKey: apiKey, model: model)
        } else {
            Log.write("[Recommend][\(catRaw)] skip — delta=\(snapshot.summarizedCount - s.recommendArticleCount), hasNew=\(hasNewArticles)")
        }

        if !coverage {
            Log.write("[Digest][\(catRaw)] skip — coverage below threshold")
        } else if RefreshDecision.shouldRegenerateDigest(
            hasNewArticles: hasNewArticles,
            isPresent: s.dailyDigest != nil,
            lastDate: s.lastDigestDate,
            currentCount: snapshot.summarizedCount,
            lastCount: s.digestArticleCount,
            regenerateInterval: digestRegenerateInterval,
            deltaThreshold: summaryDeltaThreshold
        ) {
            await runDigest(cat: cat, snapshot: snapshot, apiKey: apiKey, model: model)
        } else {
            Log.write("[Digest][\(catRaw)] skip — delta=\(snapshot.summarizedCount - s.digestArticleCount), hasNew=\(hasNewArticles)")
        }
    }

    // MARK: - Recommend / Digest runners

    func runRecommend(
        cat: AINewsBar.Category, snapshot: ArticleSnapshot,
        apiKey: String, model: String
    ) async {
        do {
            if let outcome = try await recommendEngine.run(
                snapshot: snapshot, category: cat, apiKey: apiKey, model: model
            ) {
                commit(cat: cat, recommend: outcome, model: model)
            }
        } catch {
            applyGlobalAIErrorIfNeeded(error)
            mutate(cat) { $0.aiAvailability = .unavailable(error.localizedDescription) }
            usage?.recordFailure(scene: .recommend, category: cat, model: model)
            Log.write("[Recommend][\(cat.rawValue)] ERROR: \(error)")
        }
    }

    func runDigest(
        cat: AINewsBar.Category, snapshot: ArticleSnapshot,
        apiKey: String, model: String
    ) async {
        do {
            if let outcome = try await digestEngine.run(
                snapshot: snapshot, category: cat, apiKey: apiKey, model: model
            ) {
                commit(cat: cat, digest: outcome, model: model)
            }
        } catch {
            applyGlobalAIErrorIfNeeded(error)
            mutate(cat) { $0.aiAvailability = .unavailable(error.localizedDescription) }
            usage?.recordFailure(scene: .digest, category: cat, model: model)
            Log.write("[Digest][\(cat.rawValue)] ERROR: \(error)")
        }
    }

    // MARK: - Commit (per-cat 原子更新)

    func commit(cat: AINewsBar.Category, recommend outcome: RecommendEngine.Outcome, model: String) {
        mutate(cat) {
            $0.recommendedArticleIDs = outcome.ids
            $0.lastRecommendDate = outcome.generatedAt
            $0.recommendArticleCount = outcome.articleCount
            $0.aiAvailability = .available
        }
        clearGlobalAIErrorAfterAISuccess()
        prefs.saveRecommendArticleCount(outcome.articleCount, for: cat)
        usage?.record(scene: .recommend, category: cat, model: model, info: outcome.usage)
    }

    func commit(cat: AINewsBar.Category, digest outcome: DigestEngine.Outcome, model: String) {
        mutate(cat) {
            $0.dailyDigest = outcome.content
            $0.lastDigestDate = outcome.generatedAt
            $0.digestArticleCount = outcome.articleCount
        }
        clearGlobalAIErrorAfterAISuccess()
        prefs.saveDigest(content: outcome.content, date: outcome.generatedAt, for: cat)
        prefs.saveDigestArticleCount(outcome.articleCount, for: cat)
        usage?.record(scene: .digest, category: cat, model: model, info: outcome.usage)
        // 不重置 aiAvailability —— Recommend 设的 .unavailable 应保留
    }

    /// 摘要原子持久化：safeSaveOrThrow 失败用 context.rollback() 撤回内存改动（保证内存/磁盘一致）
    /// + 设 .unavailable + token 记 success=false。
    func commitSummaries(
        cat: AINewsBar.Category, result: SummaryPipeline.Result, model: String,
        context: ModelContext
    ) {
        let map = Dictionary(uniqueKeysWithValues: result.completed.map { ($0.id, $0) })

        var persistSucceeded = true
        if !map.isEmpty {
            let ids = Array(map.keys)
            do {
                let alive = try context.safeFetchOrThrow(
                    FetchDescriptor<Article>(predicate: #Predicate { ids.contains($0.id) })
                )
                for article in alive {
                    if let item = map[article.id] { article.aiSummary = item.summary }
                }
                try context.safeSaveOrThrow()
            } catch {
                context.rollback()
                mutate(cat) { $0.aiAvailability = .unavailable("摘要保存失败") }
                Log.write("[Summary][\(cat.rawValue)] commit failed, rolled back: \(error)")
                persistSucceeded = false
            }
        }

        for item in result.completed {
            // 走 helper record(info:success:)：persistSucceeded=false 时 token 自动归零。
            usage?.record(
                scene: .summary, category: cat, model: model,
                info: item.usage, success: persistSucceeded
            )
        }
        for _ in result.failedIds {
            usage?.recordFailure(scene: .summary, category: cat, model: model)
        }
    }
}
