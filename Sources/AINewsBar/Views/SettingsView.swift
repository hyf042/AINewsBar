import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            FeedsSettingsView()
                .tabItem { Label("订阅源", systemImage: "list.bullet") }
            APISettingsView()
                .tabItem { Label("API", systemImage: "key") }
            UsageSettingsView()
                .tabItem { Label("用量", systemImage: "chart.bar") }
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 520, height: 460)
    }
}
