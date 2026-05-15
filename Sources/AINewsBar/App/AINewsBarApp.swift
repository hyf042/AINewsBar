import SwiftUI
import SwiftData

@main
struct AINewsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let container: ModelContainer = {
        let schema = Schema([Feed.self, Article.self, AISummary.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: config)
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
