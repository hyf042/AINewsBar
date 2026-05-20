import SwiftUI
import SwiftData

@main
struct AINewsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var refreshService = RefreshService.shared

    private let container: ModelContainer = {
        let schema = Schema([Feed.self, Article.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let c = try ModelContainer(for: schema, configurations: config)
            Log.write("ModelContainer created OK")
            return c
        } catch {
            // 迁移失败时删除旧库重建（今日文章重新抓取即可）
            Log.write("ModelContainer failed, resetting store: \(error)")
            let base = URL.applicationSupportDirectory.appending(path: "default.store")
            for suffix in ["", "-shm", "-wal"] {
                let url = URL.applicationSupportDirectory.appending(path: "default.store\(suffix)")
                try? FileManager.default.removeItem(at: url)
            }
            let c = try! ModelContainer(for: schema, configurations: config)
            Log.write("ModelContainer recreated OK")
            // 容灾去重：重建后理论上空库，此调用作为防御兜底（KISS 保留以便未来迁移场景）
            Task { @MainActor in
                BuiltInFeeds.deduplicateArticles(context: ModelContext(c))
            }
            return c
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .modelContainer(container)
                .environmentObject(refreshService)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(container)
                .environmentObject(refreshService)
        }
    }
}

struct MenuBarLabel: View {
    @State private var unreadCount = 0

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "brain")
            if unreadCount > 0 {
                Text("\(min(unreadCount, 99))")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .unreadCountChanged)) { note in
            unreadCount = (note.object as? Int) ?? 0
        }
    }
}
