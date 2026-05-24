import Foundation

/// 用量记录协议。RefreshService 持有；测试通过 InMemoryUsageRecorder mock。
/// v2-multi-category 双轨：新签名加 category 参数；旧签名走 extension fallback 到 .ai。
@MainActor
protocol UsageRecording: AnyObject {
    /// 记录一次 AI 调用。失败时 input/output 应传 0。category 用于按 tab 分组 token 统计。
    func record(
        scene: UsageScene, category: AINewsBar.Category,
        model: String, input: Int, output: Int, success: Bool
    )

    /// 删除超过 days 天的旧记录。在应用启动 + refresh 完成时调用。
    func cleanupOlderThan(days: Int)
}

/// Recorder 便利重载：直接吃 UsageInfo + 默认 .ai cat 兼容旧调用方。
/// Phase 4 RefreshService 改造后，旧签名调用点全部显式传 cat 参数，此 extension 可保留。
extension UsageRecording {
    // 旧无 cat 签名：fallback to .ai（保持 Phase 3 SummaryPipeline 等调用方零侵入）
    func record(scene: UsageScene, model: String, input: Int, output: Int, success: Bool) {
        record(scene: scene, category: .ai, model: model,
               input: input, output: output, success: success)
    }

    // 便利重载：直接吃 UsageInfo（新签名）
    func record(
        scene: UsageScene, category: AINewsBar.Category,
        model: String, info: UsageInfo, success: Bool = true
    ) {
        record(scene: scene, category: category, model: model,
               input: info.inputTokens, output: info.outputTokens, success: success)
    }

    // 便利重载：直接吃 UsageInfo（旧签名 fallback .ai）
    func record(scene: UsageScene, model: String, info: UsageInfo, success: Bool = true) {
        record(scene: scene, category: .ai, model: model,
               input: info.inputTokens, output: info.outputTokens, success: success)
    }

    // 失败便捷方法（新签名）
    func recordFailure(scene: UsageScene, category: AINewsBar.Category, model: String) {
        record(scene: scene, category: category, model: model,
               input: 0, output: 0, success: false)
    }

    // 失败便捷方法（旧签名 fallback .ai）
    func recordFailure(scene: UsageScene, model: String) {
        record(scene: scene, category: .ai, model: model, input: 0, output: 0, success: false)
    }
}
