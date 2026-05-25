import Foundation
import SwiftData

/// 文章数据的 Sendable 快照：一次 fetch 后可被多个 Engine 复用
/// 解决：原 RefreshService 多次重复 fetchAll 同份数据的浪费
struct ArticleSnapshot: Sendable {
    struct Item: Sendable {
        let id: UUID
        let title: String
        let summary: String?
    }

    let all: [Item]

    /// 仅含已生成摘要的条目（DigestEngine 使用）
    var summarized: [Item] {
        all.filter { $0.summary != nil }
    }

    var summarizedCount: Int { summarized.count }

    /// 单 cat 快照（严格）：用于推荐/摘要生成等关键路径。DB 查询失败抛错，
    /// caller 必须显式处理而非把"查询失败"当"无文章"。
    ///
    /// **按 publishedAt 倒序**（第八轮 P2 review）：后续 BailianService.makeRecommendPrompt
    /// prefix(50) 与 makeDigestPrompt prefix(20) 截断假设输入"按时间倒序"才有意义。
    /// 旧实现不带 sort 依赖 SwiftData 默认返回顺序 + RSS 并发完成顺序，AI 输入
    /// 不一定包含最新文章，prompt 截断会随机切掉。
    ///
    /// 注：sort 在内存中执行（`articles.sorted`）而非 `FetchDescriptor.sortBy`。
    /// SwiftData in-memory store + SortDescriptor + #Predicate 组合在测试场景下
    /// 触发 SIGTRAP（类似踩坑 #34 的 SwiftData predicate/sort 边界脆性）。
    /// 单 cat 文章量小（数十至数百），内存 sort 开销可忽略；行为可预测可测试。
    @MainActor
    static func captureOrThrow(from context: ModelContext, category: AINewsBar.Category) throws -> ArticleSnapshot {
        let catRaw = category.rawValue
        let articles = try context.safeFetchOrThrow(
            FetchDescriptor<Article>(
                predicate: #Predicate { $0.category == catRaw && $0.accepted == true }
            )
        )
        let sorted = articles.sorted { $0.publishedAt > $1.publishedAt }
        return ArticleSnapshot(all: sorted.map {
            Item(id: $0.id, title: $0.title, summary: $0.aiSummary)
        })
    }
}
