import Foundation

/// AI Filter 并发管道（v2-multi-category）：mirror SummaryPipeline 结构。
///
/// 接收 pending 文章 → 有界并发调 AI Filter → 返回 (accepted/rejected/failed) 映射 + usage 列表
/// 调用方 (RefreshService) 负责把结果写回 SwiftData (Article.accepted / filterFailCount) 与 UsageRecorder。
///
/// Filter 提示词从 CategoryConfig.filterPrompt 模板取，由 BailianService.classifyArticle 内部完成
/// `<title>` / `<description>` 占位符替换。
struct FilterPipeline {
    struct Task: Sendable {
        let id: UUID
        let title: String
        let description: String   // RSS 原始 description，FilterPipeline 不裁剪，BailianService 取前 200 字
        let category: AINewsBar.Category

        init(id: UUID, title: String, description: String, category: AINewsBar.Category) {
            self.id = id
            self.title = title
            self.description = description
            self.category = category
        }
    }

    struct Result: Sendable {
        let acceptedIds: [UUID]
        let rejectedIds: [UUID]
        /// **真实的"模型无法分类"**：BailianError.malformedResponse 解析失败。
        /// caller 走 `Article.recordFilterFailure` 路径，累计到 maxBeforeReject 永久 reject。
        let classificationFailedIds: [UUID]
        /// **transient 失败**：HTTP 401/403/429/5xx / 网络抖动 / 其他临时错误。
        /// caller **不能**累计 filterFailCount —— 否则网络抖动会把财报文章永久拒绝。
        /// 保持 accepted=nil，等下一轮 refresh 重试。
        let transientFailedIds: [UUID]
        let cancelledCount: Int     // 取消≠失败：不记 UsageRecord
        let usages: [UsageInfo]     // 与所有 accepted/rejected 一一对应（failed/cancelled 无 usage）
        /// 第一条 transient 失败映射出来的全局错误（可用于 set globalAIError，UI 提示用户）
        let firstTransientGlobalError: GlobalAIError?
        let total: Int

        static let empty = Result(
            acceptedIds: [], rejectedIds: [],
            classificationFailedIds: [], transientFailedIds: [],
            cancelledCount: 0, usages: [], firstTransientGlobalError: nil, total: 0
        )
    }

    let ai: any AISummarizing
    let maxConcurrent: Int
    let promptTemplate: String   // 来自 CategoryConfig.filterPrompt（caller 确保非 nil）

    /// 有界并发执行。Task.isCancelled 时停止派发 + cancelAll；cancelled 不污染 failed*Ids。
    func run(tasks: [Task], apiKey: String, model: String) async -> Result {
        guard !tasks.isEmpty else { return .empty }
        Log.write("[Filter] pending=\(tasks.count), concurrency=\(maxConcurrent)")

        let aiRef = ai
        let template = promptTemplate
        let cap = maxConcurrent
        var accepted: [UUID] = []
        var rejected: [UUID] = []
        var classificationFailed: [UUID] = []
        var transientFailed: [UUID] = []
        var firstTransient: GlobalAIError?
        var cancelled = 0
        var usages: [UsageInfo] = []

        await withTaskGroup(of: TaskOutcome.self) { group in
            var next = min(cap, tasks.count)
            for i in 0..<next {
                if _Concurrency.Task.isCancelled { break }
                let t = tasks[i]
                group.addTask {
                    await Self.runOne(t, apiKey: apiKey, model: model,
                                      ai: aiRef, prompt: template)
                }
            }
            for await outcome in group {
                if _Concurrency.Task.isCancelled {
                    group.cancelAll()
                }
                switch outcome {
                case .accepted(let id, let usage):
                    accepted.append(id)
                    usages.append(usage)
                case .rejected(let id, let usage):
                    rejected.append(id)
                    usages.append(usage)
                case .classificationFailed(let id):
                    classificationFailed.append(id)
                    // 不记 usage：BailianError.malformedResponse 抛错前 token 可忽略
                case .transientFailed(let id, let global):
                    transientFailed.append(id)
                    if firstTransient == nil, global != nil {
                        firstTransient = global
                    }
                case .cancelled:
                    cancelled += 1
                }
                if next < tasks.count, !_Concurrency.Task.isCancelled {
                    let t = tasks[next]
                    next += 1
                    group.addTask {
                        await Self.runOne(t, apiKey: apiKey, model: model,
                                          ai: aiRef, prompt: template)
                    }
                }
            }
        }

        let result = Result(
            acceptedIds: accepted, rejectedIds: rejected,
            classificationFailedIds: classificationFailed,
            transientFailedIds: transientFailed,
            cancelledCount: cancelled, usages: usages,
            firstTransientGlobalError: firstTransient,
            total: tasks.count
        )
        Log.write("[Filter] done: \(accepted.count) accepted, \(rejected.count) rejected, \(classificationFailed.count) classFail, \(transientFailed.count) transient, \(cancelled) cancelled, total=\(tasks.count)")
        return result
    }

    private enum TaskOutcome: Sendable {
        case accepted(UUID, UsageInfo)
        case rejected(UUID, UsageInfo)
        /// 模型响应无法解析（BailianError.malformedResponse）→ 真"分类失败"，累计 filterFailCount
        case classificationFailed(UUID)
        /// HTTP / 网络 / credential / 其他临时错误 → 不累计；可用第二个参数提示全局
        case transientFailed(UUID, GlobalAIError?)
        case cancelled
    }

    private static func runOne(
        _ t: Task, apiKey: String, model: String,
        ai: any AISummarizing, prompt: String
    ) async -> TaskOutcome {
        if _Concurrency.Task.isCancelled { return .cancelled }
        do {
            let (accepted, usage) = try await ai.classifyArticle(
                title: t.title, description: t.description,
                prompt: prompt, apiKey: apiKey, model: model
            )
            if _Concurrency.Task.isCancelled { return .cancelled }
            return accepted ? .accepted(t.id, usage) : .rejected(t.id, usage)
        } catch is CancellationError {
            return .cancelled
        } catch {
            // P1 第七轮 review：仅 BailianError.malformedResponse 算"模型确实无法分类"，
            // 其他全归 transient（HTTP 401/403/429/5xx、网络抖动、未知错误），不计入
            // filterFailCount，让下一轮 refresh 自然重试。
            // 防止网络问题把财报文章永久 reject。
            if case BailianError.malformedResponse = error {
                Log.write("[Filter] classificationFailed: \(t.title.prefix(30)) — \(error.localizedDescription)")
                return .classificationFailed(t.id)
            }
            Log.write("[Filter] transientFailed: \(t.title.prefix(30)) — \(error.localizedDescription)")
            return .transientFailed(t.id, GlobalAIError.from(error))
        }
    }
}
