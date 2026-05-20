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

    var summarized: [Item] {
        all.filter { $0.summary != nil }
    }

    var summarizedCount: Int { summarized.count }

    /// DigestEngine 使用：(title, summary)，仅含已有摘要的条目
    var summarizedPairs: [(title: String, summary: String)] {
        all.compactMap { item in
            guard let s = item.summary else { return nil }
            return (title: item.title, summary: s)
        }
    }

    /// RecommendEngine 使用：(id, title, summary?)，包含所有文章
    var pickInputs: [(id: UUID, title: String, summary: String?)] {
        all.map { ($0.id, $0.title, $0.summary) }
    }

    @MainActor
    static func capture(from context: ModelContext) -> ArticleSnapshot {
        let articles = context.safeFetch(FetchDescriptor<Article>())
        return ArticleSnapshot(all: articles.map {
            Item(id: $0.id, title: $0.title, summary: $0.aiSummary)
        })
    }
}
