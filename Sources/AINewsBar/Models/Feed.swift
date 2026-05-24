import Foundation
import SwiftData

@Model
final class Feed {
    var id: UUID
    var title: String
    var url: String
    var iconURL: String?
    var isBuiltIn: Bool
    var isEnabled: Bool
    var addedAt: Date

    // MARK: - Multi-Category (v2-multi-category schema)

    /// 资讯分类（= Category.rawValue）。Feed:Category 1:1，
    /// 同一 RSS 源只能归属一个 tab；feed 的 articles.category 由此派生。
    var category: String

    /// 是否跳过 AI Filter（仅财报/新闻 cat 有效）。true 时该源所有文章入库
    /// 直接 accepted=true 不跑 filter，省 token。用于用户标记"纯净源"。
    var skipFilter: Bool

    init(id: UUID = UUID(), title: String, url: String, iconURL: String? = nil,
         isBuiltIn: Bool = false, isEnabled: Bool = true,
         category: Category = .ai, skipFilter: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.iconURL = iconURL
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.addedAt = Date()
        self.category = category.rawValue
        self.skipFilter = skipFilter
    }
}
