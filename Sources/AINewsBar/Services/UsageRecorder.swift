import Foundation
import SwiftData

/// SwiftData 后端的 UsageRecording 实现。所有写入都走 `ModelContext+Safe`。
@MainActor
final class UsageRecorder: UsageRecording {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(
        scene: UsageScene, category: AINewsBar.Category,
        model: String, input: Int, output: Int, success: Bool
    ) {
        let record = UsageRecord(
            scene: scene,
            category: category,
            model: model,
            inputTokens: max(0, input),
            outputTokens: max(0, output),
            success: success
        )
        context.insert(record)
        context.safeSave()
    }

    func cleanupOlderThan(days: Int) {
        guard days > 0 else { return }
        // fallback 到 distantPast 而非 Date() —— 异常时变 no-op 保护历史数据
        // 旧逻辑 fallback Date() 会让 predicate 匹配全部记录并清空整张表
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let old = context.safeFetch(
            FetchDescriptor<UsageRecord>(predicate: #Predicate { $0.timestamp < cutoff })
        )
        guard !old.isEmpty else { return }
        old.forEach { context.delete($0) }
        context.safeSave()
        Log.write("[Usage] cleanup removed \(old.count) records older than \(days)d")
    }
}

// MARK: - 查询辅助（纯函数，方便 UI 复用）

extension UsageRecorder {
    /// 今日所有成功调用的总 token（input + output）。
    static func todayTotalTokens(in context: ModelContext, now: Date = Date()) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        let records = context.safeFetch(
            FetchDescriptor<UsageRecord>(predicate: #Predicate {
                $0.timestamp >= start && $0.success == true
            })
        )
        return records.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }
}
