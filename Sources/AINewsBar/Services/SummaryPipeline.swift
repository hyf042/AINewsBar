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

        init(id: UUID, title: String, content: String?, category: AINewsBar.Category) {
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
        let globalError: GlobalAIError?

        var completionRate: Double {
            RefreshDecision.completionRate(completed: completed.count, total: total)
        }
    }

    let ai: any AISummarizing
    let maxConcurrent: Int

    func run(tasks: [Task], apiKey: String, model: String) async -> Result {
        guard !tasks.isEmpty else {
            return Result(completed: [], failedIds: [], total: 0, globalError: nil)
        }

        let aiRef = ai
        var completed: [CompletedItem] = []
        var failed: [UUID] = []
        var globalError: GlobalAIError?

        let outcomes = await PipelineConcurrency.run(
            items: tasks,
            maxConcurrent: maxConcurrent,
            logPrefix: "[Summary]",
            runOne: { task in
                // 取消时返回 nil，不计入 completed/failed
                await Self.runOne(task, apiKey: apiKey, model: model, ai: aiRef)
            }
        )

        for outcome in outcomes {
            switch outcome {
            case .success(let item): completed.append(item)
            case .failure(let id, let mappedGlobalError):
                failed.append(id)
                if globalError == nil { globalError = mappedGlobalError }
            }
        }

        return Result(completed: completed, failedIds: failed,
                      total: tasks.count, globalError: globalError)
    }

    private enum TaskOutcome: Sendable {
        case success(CompletedItem)
        case failure(UUID, GlobalAIError?)
    }

    /// 返回 nil = 取消（不计入结果），非 nil = success/failure。
    private static func runOne(_ t: Task, apiKey: String, model: String, ai: any AISummarizing) async -> TaskOutcome? {
        if _Concurrency.Task.isCancelled { return nil }
        do {
            let (summary, usage) = try await ai.generateSummary(
                title: t.title, content: t.content,
                category: t.category, apiKey: apiKey, model: model
            )
            if _Concurrency.Task.isCancelled { return nil }
            let stripped = MarkdownStripper.strip(summary)
            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Log.write("[Summary] empty content for: \(t.title.prefix(30))")
                return .failure(t.id, nil)
            }
            return .success(CompletedItem(id: t.id, summary: trimmed, usage: usage))
        } catch is CancellationError {
            return nil
        } catch {
            Log.write("[Summary] failed: \(t.title.prefix(30)) — \(error.localizedDescription)")
            return .failure(t.id, GlobalAIError.from(error))
        }
    }
}
