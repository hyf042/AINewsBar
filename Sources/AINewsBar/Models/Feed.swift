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

    init(id: UUID = UUID(), title: String, url: String, iconURL: String? = nil, isBuiltIn: Bool = false, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.url = url
        self.iconURL = iconURL
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.addedAt = Date()
    }
}
