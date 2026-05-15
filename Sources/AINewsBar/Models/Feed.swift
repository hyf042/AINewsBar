import Foundation

struct Feed: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var iconURL: String?
    var isBuiltIn: Bool
    var addedAt: Date

    init(id: UUID = UUID(), title: String, url: String, iconURL: String? = nil, isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.iconURL = iconURL
        self.isBuiltIn = isBuiltIn
        self.addedAt = Date()
    }
}
