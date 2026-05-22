import SwiftUI
import SwiftData

@main
struct AINewsBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var refreshService = RefreshService.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .modelContainer(AppDelegate.container)
                .environmentObject(refreshService)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(AppDelegate.container)
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
