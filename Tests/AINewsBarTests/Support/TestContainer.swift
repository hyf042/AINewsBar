import Foundation
import SwiftData
@testable import AINewsBar

// MARK: - 内存 ModelContainer 工厂，每个测试独立 schema 实例
@MainActor
enum TestContainer {
    static func make() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Article.self, Feed.self, UsageRecord.self])
        let config = ModelConfiguration("test-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }
}
