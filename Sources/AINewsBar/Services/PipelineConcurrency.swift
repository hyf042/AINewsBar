import Foundation

/// 有界并发 TaskGroup 执行器：消除 SummaryPipeline / FilterPipeline 的复制粘贴。
///
/// 先派发 min(maxConcurrent, items.count) 个任务，每完成一个补一个。
/// `runOne` 返回 nil 表示任务被取消（不计入结果），非 nil 由 caller 累积。
/// cancellation：停止新派发 + cancelAll。
enum PipelineConcurrency {

    static func run<Item: Sendable, Outcome: Sendable>(
        items: [Item],
        maxConcurrent: Int,
        logPrefix: String,
        runOne: @escaping (Item) async -> Outcome?
    ) async -> [Outcome] {
        guard !items.isEmpty else { return [] }
        Log.write("\(logPrefix) pending=\(items.count), concurrency=\(maxConcurrent)")

        var results: [Outcome] = []

        await withTaskGroup(of: Outcome?.self) { group in
            var next = min(maxConcurrent, items.count)
            for i in 0..<next {
                if Task.isCancelled { break }
                let item = items[i]
                group.addTask { await runOne(item) }
            }
            for await result in group {
                if Task.isCancelled { group.cancelAll() }
                if let r = result { results.append(r) }
                if next < items.count, !Task.isCancelled {
                    let item = items[next]
                    next += 1
                    group.addTask { await runOne(item) }
                }
            }
        }

        let cancelled = items.count - results.count
        Log.write("\(logPrefix) done: \(results.count) success/failure, \(cancelled) cancelled, total=\(items.count)")
        return results
    }
}
