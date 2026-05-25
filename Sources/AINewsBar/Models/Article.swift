import Foundation
import SwiftData

@Model
final class Article {
    var id: UUID
    var title: String
    var url: String
    var content: String?
    var publishedAt: Date
    var feedID: UUID
    var feedTitle: String
    var isRead: Bool
    var aiSummary: String?

    // MARK: - Multi-Category (v2-multi-category schema)

    /// 资讯分类（= Category.rawValue）。冗余 from Feed.category，
    /// 写入时由 RefreshService.mergeNewArticles 保证与 feed.category 一致。
    /// SwiftData @Query 跨 relation predicate 性能差，故冗余 1 字段换 O(1) 过滤。
    var category: String

    /// AI Filter 分类结果。nil=未分类（filter 待跑或不需要）  true=通过  false=拒绝。
    /// 未配 filterPrompt 的 cat（AI tab）或 feed.skipFilter==true 时入库直接为 true，
    /// 保证 @Query predicate `accepted == true` 三 cat 通用。
    var accepted: Bool?

    /// Filter 调用失败计数。≥3 时自动 accepted=false 永久 reject，
    /// 避免黑名单文章反复重试烧 token。
    var filterFailCount: Int

    // L2: accepted 默认 nil（"未跑 filter"），让"通过"成为显式行为。
    // 旧 default true 与设计意图（filter cat 入库时应 nil）相悖，新建 Article
    // 路径漏传时静默跳过 filter → 财报 cat 噪声泄漏到 UI。
    // RefreshService.mergeNewArticles 已显式根据 needFilter / skipFilter 传值。
    init(id: UUID = UUID(), title: String, url: String, content: String? = nil,
         publishedAt: Date, feedID: UUID, feedTitle: String,
         category: Category = .ai, accepted: Bool? = nil, filterFailCount: Int = 0) {
        self.id = id
        self.title = title
        self.url = url
        self.content = content
        self.publishedAt = publishedAt
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.isRead = false
        self.aiSummary = nil
        self.category = category.rawValue
        self.accepted = accepted
        self.filterFailCount = filterFailCount
    }
}

extension Article {
    /// 记录 filter 失败一次：累加计数 + 达到上限永久 reject。
    /// caller（FilterPipeline 写回路径）原本散在 RefreshService.runFilterStage 里
    /// 的 if/else，现收敛到 model；避免新增 filter cat 时漏改任一处。
    func recordFilterFailure(maxBeforeReject: Int) {
        filterFailCount += 1
        if filterFailCount >= maxBeforeReject {
            accepted = false
        }
    }
}
