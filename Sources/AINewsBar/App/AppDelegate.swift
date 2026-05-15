import AppKit
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏 Dock 图标，仅菜单栏运行
        NSApp.setActivationPolicy(.accessory)
        setupRefreshService()
        seedBuiltInFeeds()
    }

    private func setupRefreshService() {
        // RefreshService 在 MenuBarView.task 中拿到 modelContext 后配置
    }

    private func seedBuiltInFeeds() {
        // 内置 Feed 的初始化在 MenuBarView onAppear 中完成，避免此处没有 context
    }
}
