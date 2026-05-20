import SwiftUI
import SwiftData

@main
struct AINewsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
            return c
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .modelContainer(container)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(container)
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
