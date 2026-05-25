import Foundation

/// 用量记录协议。RefreshService 持有；测试通过 InMemoryUsageRecorder mock。
///
/// **契约（P3-B 明确）**：失败的调用（success == false）token 一律视为 0。
/// "今日 Token 用量"语义 = "成功生效的用量"；DashScope 实际可能仍扣费，但 UI
/// 不能让用户误以为失败浪费的 token 也算入总额。
/// - root API `record(scene:category:model:input:output:success:)` 接受任意值
///   （测试 mock 灵活性），但生产 caller 应通过下方 helper 调用以自动归零。
@MainActor
protocol UsageRecording: AnyObject {
    /// 记录一次 AI 调用。**契约**：success == false 时 input/output 应为 0
    /// （helper `record(info:success:)` 会自动归零；直接调本 API 时由 caller 负责）。
    /// category 用于按 tab 分组 token 统计。
    func record(
        scene: UsageScene, category: AINewsBar.Category,
        model: String, input: Int, output: Int, success: Bool
    )

    /// 删除超过 days 天的旧记录。在应用启动 + refresh 完成时调用。
    func cleanupOlderThan(days: Int)
}

extension UsageRecording {
    /// 便利重载：吃 UsageInfo。**自动归零**：success == false 时 input/output 强制 0，
    /// 跟协议契约对齐。caller 可继续传真实 UsageInfo（如保存失败时仍有 DashScope
    /// 返回的 usage），helper 会丢弃 token 数字，仅保留 success=false 信号。
    func record(
        scene: UsageScene, category: AINewsBar.Category,
        model: String, info: UsageInfo, success: Bool = true
    ) {
        let input = success ? info.inputTokens : 0
        let output = success ? info.outputTokens : 0
        record(scene: scene, category: category, model: model,
               input: input, output: output, success: success)
    }

    // 失败便捷方法（与上面 helper 等价：传 .zero + success=false）
    func recordFailure(scene: UsageScene, category: AINewsBar.Category, model: String) {
        record(scene: scene, category: category, model: model,
               input: 0, output: 0, success: false)
    }
}
