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
    /// 历史上同时存在 `capture(from:)` / `capture(from:category:)` 两个 tolerant 版本
    /// （safeFetch 失败→空快照）。生产路径全部迁到 `captureOrThrow` 后，
    /// 那两个 API 已无 caller — 保留只会给后人挖"再写个 fallback"的坑（踩坑 #22 同型）。
    /// 第五轮 review 删除。
    @MainActor
    static func captureOrThrow(from context: ModelContext, category: AINewsBar.Category) throws -> ArticleSnapshot {
        let catRaw = category.rawValue
        let articles = try context.safeFetchOrThrow(
            FetchDescriptor<Article>(predicate: #Predicate {
                $0.category == catRaw && $0.accepted == true
            })
        )
        return ArticleSnapshot(all: articles.map {
            Item(id: $0.id, title: $0.title, summary: $0.aiSummary)
        })
    }
}
