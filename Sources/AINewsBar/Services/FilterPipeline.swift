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
        let failedIds: [UUID]       // AI 调用失败（HTTP / 解析失败）；caller 走 filterFailCount++ 路径
        let cancelledCount: Int     // 取消≠失败：不记 UsageRecord
        let usages: [UsageInfo]     // 与所有 accepted/rejected/failed 一一对应（cancelled 无 usage）
        let total: Int

        static let empty = Result(
            acceptedIds: [], rejectedIds: [], failedIds: [],
            cancelledCount: 0, usages: [], total: 0
        )
    }

    let ai: any AISummarizing
    let maxConcurrent: Int
    let promptTemplate: String   // 来自 CategoryConfig.filterPrompt（caller 确保非 nil）

    /// 有界并发执行。Task.isCancelled 时停止派发 + cancelAll；cancelled 不污染 failedIds。
    func run(tasks: [Task], apiKey: String, model: String) async -> Result {
        guard !tasks.isEmpty else { return .empty }
        Log.write("[Filter] pending=\(tasks.count), concurrency=\(maxConcurrent)")

        let aiRef = ai
        let template = promptTemplate
        let cap = maxConcurrent
        var accepted: [UUID] = []
        var rejected: [UUID] = []
        var failed: [UUID] = []
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
                case .failed(let id):
                    failed.append(id)
                    // failed 不记 usage（HTTP 失败无 token；解析失败 token 微小可忽略）
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
            acceptedIds: accepted, rejectedIds: rejected, failedIds: failed,
            cancelledCount: cancelled, usages: usages, total: tasks.count
        )
        Log.write("[Filter] done: \(accepted.count) accepted, \(rejected.count) rejected, \(failed.count) failed, \(cancelled) cancelled, total=\(tasks.count)")
        return result
    }

    private enum TaskOutcome: Sendable {
        case accepted(UUID, UsageInfo)
        case rejected(UUID, UsageInfo)
        case failed(UUID)
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
            Log.write("[Filter] failed: \(t.title.prefix(30)) — \(error.localizedDescription)")
            return .failed(t.id)
        }
    }
}
