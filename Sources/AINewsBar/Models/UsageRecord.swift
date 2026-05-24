import Foundation
import SwiftData

/// AI 调用的场景标签。4 个业务场景；testConnection 不计入。
enum UsageScene: String, CaseIterable, Sendable {
    case summary
    case recommend
    case digest
    /// 新增 (v2-multi-category)：单篇文章分类筛选（仅财报 cat 启用，未来可扩展新闻）
    case filter
}

/// 单次 AI 调用的 token 用量（从 DashScope `usage` 字段提取）。
struct UsageInfo: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }

    static let zero = UsageInfo(inputTokens: 0, outputTokens: 0)
}

/// 一次 AI 调用的明细记录。失败调用 inputTokens/outputTokens 为 0、success=false。
@Model
final class UsageRecord {
    var id: UUID
    var timestamp: Date
    /// 存 `UsageScene.rawValue`；SwiftData 对 String 比 enum 更友好。
    var scene: String
    var model: String
    var inputTokens: Int
    var outputTokens: Int
    var success: Bool

    /// 资讯分类（= Category.rawValue）。v2-multi-category 新增，
    /// 用于 Settings 用量 Tab 按 cat 过滤展示。旧记录全清不存在迁移问题。
    var category: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        scene: UsageScene,
        category: Category = .ai,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        success: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.scene = scene.rawValue
        self.category = category.rawValue
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.success = success
    }

    var totalTokens: Int { inputTokens + outputTokens }
    var sceneEnum: UsageScene? { UsageScene(rawValue: scene) }
    var categoryEnum: Category { Category.from(rawValue: category) }
}
