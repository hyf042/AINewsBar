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

    @MainActor
    static func capture(from context: ModelContext) -> ArticleSnapshot {
        let articles = context.safeFetch(FetchDescriptor<Article>())
        return ArticleSnapshot(all: articles.map {
            Item(id: $0.id, title: $0.title, summary: $0.aiSummary)
        })
    }
}
