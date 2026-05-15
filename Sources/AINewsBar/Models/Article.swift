import Foundation

struct Article: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var content: String?
    var publishedAt: Date
    var feedID: UUID
    var feedTitle: String
    var isRead: Bool
    var aiSummary: String?

    init(id: UUID = UUID(), title: String, url: String, content: String? = nil,
         publishedAt: Date, feedID: UUID, feedTitle: String) {
        self.id = id
        self.title = title
        self.url = url
        self.content = content
        self.publishedAt = publishedAt
        self.feedID = feedID
        self.feedTitle = feedTitle
        self.isRead = false
        self.aiSummary = nil
    }
}
