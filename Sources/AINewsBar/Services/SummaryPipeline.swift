import Foundation

/// 摘要并发管道：接收 pending 文章 → 有界并发调 AI → 返回 (id, summary, usage) 映射 + 失败列表
/// 调用方负责把结果回写 SwiftData 与 UsageRecorder（保持 Engine 无副作用）
struct SummaryPipeline {
    struct Task: Sendable {
        let id: UUID
        let title: String
        let content: String?
        /// v2-multi-category: 每个 task 携带 cat，BailianService 据此选 prompt 文案
        let category: AINewsBar.Category

        init(id: UUID, title: String, content: String?, category: AINewsBar.Category = .ai) {
            self.id = id
            self.title = title
            self.content = content
            self.category = category
        }
    }

    struct CompletedItem: Sendable {
        let id: UUID
        let summary: String
        let usage: UsageInfo
    }

    struct Result: Sendable {
        let completed: [CompletedItem]
        let failedIds: [UUID]
        let total: Int

        var completionRate: Double {
            RefreshDecision.completionRate(completed: completed.count, total: total)
        }
    }

    let ai: any AISummarizing
    let maxConcurrent: Int

    /// 有界并发执行：先种入 maxConcurrent 个任务，每完成一个再添加一个
    /// 响应 Task.isCancelled —— 取消时停止派发新任务 + cancelAll + 不污染 failedIds（取消≠失败）
    func run(tasks: [Task], apiKey: String, model: String) async -> Result {
        guard !tasks.isEmpty else { return Result(completed: [], failedIds: [], total: 0) }
        Log.write("[Summary] pending=\(tasks.count), concurrency=\(maxConcurrent)")

        let aiRef = ai
        let cap = maxConcurrent
        var completed: [CompletedItem] = []
        var failed: [UUID] = []
        var cancelled = 0

        await withTaskGroup(of: TaskOutcome.self) { group in
            var next = min(cap, tasks.count)
            for i in 0..<next {
                if _Concurrency.Task.isCancelled { break }
                let t = tasks[i]
                group.addTask {
                    await Self.runOne(t, apiKey: apiKey, model: model, ai: aiRef)
                }
            }
            for await outcome in group {
                if _Concurrency.Task.isCancelled {
                    group.cancelAll()
                }
                switch outcome {
                case .success(let item): completed.append(item)
                case .failure(let id): failed.append(id)
                case .cancelled: cancelled += 1
                }
                if next < tasks.count, !_Concurrency.Task.isCancelled {
                    let t = tasks[next]
                    next += 1
                    group.addTask {
                        await Self.runOne(t, apiKey: apiKey, model: model, ai: aiRef)
                    }
                }
            }
        }

        let result = Result(completed: completed, failedIds: failed, total: tasks.count)
        Log.write("[Summary] done: \(completed.count) success, \(failed.count) failed, \(cancelled) cancelled, total=\(tasks.count)")
        return result
    }

    private enum TaskOutcome: Sendable {
        case success(CompletedItem)
        case failure(UUID)
        case cancelled  // 与 failure 区分：不计入 failedIds，不记 UsageRecord
    }

    private static func runOne(_ t: Task, apiKey: String, model: String, ai: any AISummarizing) async -> TaskOutcome {
        // 调用 AI 前检查取消，避免无谓 token 浪费
        if _Concurrency.Task.isCancelled { return .cancelled }
        do {
            let (summary, usage) = try await ai.generateSummary(
                title: t.title, content: t.content,
                category: t.category, apiKey: apiKey, model: model
            )
            // 调用后再检查一次取消：若 await 期间被取消，丢弃这次结果但仍计 cancelled（不是 failure）
            if _Concurrency.Task.isCancelled { return .cancelled }
            // 空内容降级为 failure —— AI HTTP 200 但返回空串时，旧逻辑会写入 aiSummary=""
            // 导致 ArticleSnapshot.summarized 判定通过，digest prompt 退化为纯标题列表
            // 先 strip markdown 噪声再 trim，避免 stripper 后只剩空白通过判空
            let stripped = MarkdownStripper.strip(summary)
            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Log.write("[Summary] empty content for: \(t.title.prefix(30))")
                return .failure(t.id)
            }
            return .success(CompletedItem(id: t.id, summary: trimmed, usage: usage))
        } catch is CancellationError {
            return .cancelled
        } catch {
            Log.write("[Summary] failed: \(t.title.prefix(30)) — \(error.localizedDescription)")
            return .failure(t.id)
        }
    }
}
