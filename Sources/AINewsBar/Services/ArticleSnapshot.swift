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

    /// 全表快照（旧 API，等价 capture(from:category:nil)，仅 .ai cat 时建议显式传 .ai）
    @MainActor
    static func capture(from context: ModelContext) -> ArticleSnapshot {
        let articles = context.safeFetch(FetchDescriptor<Article>())
        return ArticleSnapshot(all: articles.map {
            Item(id: $0.id, title: $0.title, summary: $0.aiSummary)
        })
    }

    /// v2: 单 cat 快照。仅 fetch 该 cat 且 accepted==true 的文章（filter rejected 的不进 snapshot
    /// 避免污染 Recommend/Digest 输入）。
    @MainActor
    static func capture(from context: ModelContext, category: AINewsBar.Category) -> ArticleSnapshot {
        let catRaw = category.rawValue
        let articles = context.safeFetch(
            FetchDescriptor<Article>(predicate: #Predicate {
                $0.category == catRaw && $0.accepted == true
            })
        )
        return ArticleSnapshot(all: articles.map {
            Item(id: $0.id, title: $0.title, summary: $0.aiSummary)
        })
    }

    /// 严格版本：用于推荐/摘要生成等关键路径。DB 查询失败不应被解释为空文章集。
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
