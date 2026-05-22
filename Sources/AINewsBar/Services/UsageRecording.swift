import Foundation

/// 用量记录协议。RefreshService 持有；测试通过 InMemoryUsageRecorder mock。
@MainActor
protocol UsageRecording: AnyObject {
    /// 记录一次 AI 调用。失败时 input/output 应传 0。
    func record(scene: UsageScene, model: String, input: Int, output: Int, success: Bool)

    /// 删除超过 days 天的旧记录。在应用启动 + refresh 完成时调用。
    func cleanupOlderThan(days: Int)
}

/// Recorder 便利重载：直接吃 UsageInfo。
extension UsageRecording {
    func record(scene: UsageScene, model: String, info: UsageInfo, success: Bool = true) {
        record(scene: scene, model: model,
               input: info.inputTokens, output: info.outputTokens, success: success)
    }

    func recordFailure(scene: UsageScene, model: String) {
        record(scene: scene, model: model, input: 0, output: 0, success: false)
    }
}
