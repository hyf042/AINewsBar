import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var launchAtLoginErrorMessage = ""
    @State private var showLaunchAtLoginErrorAlert = false
    @State private var isRevertingLaunchAtLogin = false

    /// v2.1: per-cat 后台自动刷新开关。@State 镜像 prefs 让 SwiftUI bind；
    /// onAppear 从 prefs 恢复；onChange 写回 prefs。
    @State private var autoRefreshAI = true
    @State private var autoRefreshEarnings = true
    @State private var autoRefreshNews = true

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { oldValue, enabled in
                        if isRevertingLaunchAtLogin {
                            isRevertingLaunchAtLogin = false
                            return
                        }
                        toggleLaunchAtLogin(enabled, revertingTo: oldValue)
                    }
            }
            Section {
                Toggle("AI", isOn: $autoRefreshAI)
                    .onChange(of: autoRefreshAI) { _, v in
                        PreferencesService.shared.saveAutoRefreshEnabled(v, for: .ai)
                    }
                Toggle("财报", isOn: $autoRefreshEarnings)
                    .onChange(of: autoRefreshEarnings) { _, v in
                        PreferencesService.shared.saveAutoRefreshEnabled(v, for: .earnings)
                    }
                Toggle("新闻", isOn: $autoRefreshNews)
                    .onChange(of: autoRefreshNews) { _, v in
                        PreferencesService.shared.saveAutoRefreshEnabled(v, for: .news)
                    }
            } header: {
                Text("后台自动刷新")
            } footer: {
                Text("关闭后 timer fire 跳过该 tab，手动点击刷新按钮仍可触发。")
                    .font(.caption)
                    .foregroundStyle(TextColor.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let prefs = PreferencesService.shared
            autoRefreshAI = prefs.loadAutoRefreshEnabled(for: .ai)
            autoRefreshEarnings = prefs.loadAutoRefreshEnabled(for: .earnings)
            autoRefreshNews = prefs.loadAutoRefreshEnabled(for: .news)
        }
        .alert("设置失败", isPresented: $showLaunchAtLoginErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(launchAtLoginErrorMessage)
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool, revertingTo oldValue: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 第十六轮 P3：确定性 guard 时序，照抄 FeedRowView.handleToggle 模式。
            // 1) 先 arm guard 再回写 oldValue（回写会触发 onChange 重入，由 guard 吃掉并 reset）
            // 2) 兜底：下一个 RunLoop turn 强制 reset。若 launchAtLogin = oldValue 因 SwiftUI
            //    去重 / @AppStorage 行为未触发 onChange，guard 会永久卡 true 吃掉用户下次真实 toggle。
            isRevertingLaunchAtLogin = true
            launchAtLogin = oldValue
            Task { @MainActor in
                isRevertingLaunchAtLogin = false
            }
            launchAtLoginErrorMessage = error.localizedDescription
            showLaunchAtLoginErrorAlert = true
        }
    }
}
