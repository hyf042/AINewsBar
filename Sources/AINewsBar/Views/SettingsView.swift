import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            FeedsSettingsView()
                .tabItem { Label("订阅源", systemImage: "list.bullet") }
            APISettingsView()
                .tabItem { Label("API", systemImage: "key") }
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 440)
    }
}
