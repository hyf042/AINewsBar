import Foundation

/// 摘要并发管道：接收 pending 文章 → 有界并发调 AI → 返回 (id, summary) 映射
/// 调用方负责把结果回写 SwiftData（保持 Engine 无副作用）
struct SummaryPipeline {
    struct Task: Sendable {
        let id: UUID
        let title: String
        let content: String?
    }

    struct Result: Sendable {
        let completed: [(id: UUID, summary: String)]
        let total: Int

        var completionRate: Double {
            RefreshDecision.completionRate(completed: completed.count, total: total)
        }
    }

    let ai: any AISummarizing
    let maxConcurrent: Int

    /// 有界并发执行：先种入 maxConcurrent 个任务，每完成一个再添加一个
    func run(tasks: [Task], apiKey: String, model: String) async -> Result {
        guard !tasks.isEmpty else { return Result(completed: [], total: 0) }
        Log.write("[Summary] pending=\(tasks.count), concurrency=\(maxConcurrent)")

        let aiRef = ai
        let cap = maxConcurrent
        var completed: [(UUID, String)] = []

        await withTaskGroup(of: (UUID, String?).self) { group in
            var next = min(cap, tasks.count)
            for i in 0..<next {
                let t = tasks[i]
                group.addTask {
                    await Self.runOne(t, apiKey: apiKey, model: model, ai: aiRef)
                }
            }
            for await (id, summary) in group {
                if let s = summary { completed.append((id, s)) }
                if next < tasks.count {
                    let t = tasks[next]
                    next += 1
                    group.addTask {
                        await Self.runOne(t, apiKey: apiKey, model: model, ai: aiRef)
                    }
                }
            }
        }

        let result = Result(completed: completed, total: tasks.count)
        Log.write("[Summary] done: \(completed.count)/\(tasks.count) = \(Int(result.completionRate * 100))%")
        return result
    }

    private static func runOne(_ t: Task, apiKey: String, model: String, ai: any AISummarizing) async -> (UUID, String?) {
        guard let s = try? await ai.generateSummary(
            title: t.title, content: t.content, apiKey: apiKey, model: model
        ) else {
            Log.write("[Summary] failed: \(t.title.prefix(30))")
            return (t.id, nil)
        }
        return (t.id, s)
    }
}
