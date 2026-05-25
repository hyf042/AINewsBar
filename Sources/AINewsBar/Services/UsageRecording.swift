import Foundation

/// 用量记录协议。RefreshService 持有；测试通过 InMemoryUsageRecorder mock。
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

extension UsageRecording {
    // 便利重载：直接吃 UsageInfo
    func record(
        scene: UsageScene, category: AINewsBar.Category,
        model: String, info: UsageInfo, success: Bool = true
    ) {
        record(scene: scene, category: category, model: model,
               input: info.inputTokens, output: info.outputTokens, success: success)
    }

    // 失败便捷方法
    func recordFailure(scene: UsageScene, category: AINewsBar.Category, model: String) {
        record(scene: scene, category: category, model: model,
               input: 0, output: 0, success: false)
    }
}
