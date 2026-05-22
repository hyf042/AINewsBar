import AppKit
import SwiftData

/// macOS 启动 entry。容纳 ModelContainer 与 RefreshService 的冷启动初始化，
/// 避免之前依赖 MenuBarView.task（popover lazy view，用户点击前不触发）导致定时器不启动。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 全局 ModelContainer。AppDelegate 持有以供 applicationDidFinishLaunching 启动期访问，
    /// 同时 AINewsBarApp.body 通过 `.modelContainer(AppDelegate.container)` 注入到 SwiftUI 环境。
    static let container: ModelContainer = makeContainer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let ctx = Self.container.mainContext
        let recorder = UsageRecorder(context: ctx)
        recorder.cleanupOlderThan(days: 30)
        RefreshService.shared.configure(with: ctx, usage: recorder)
        BuiltInFeeds.syncInto(context: ctx)
        RefreshService.shared.postUnreadCount(context: ctx)
        RefreshService.shared.launchBackgroundRefreshIfNeeded()

        // 监听系统从睡眠唤醒：Timer.scheduledTimer 在 App Nap/睡眠期间不按真实时间累计
        // 唤醒后只合并触发一次，跨日重置可能在用户不点菜单时丢失 24h+；这里兜底
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                RefreshService.shared.resetCrossedDayStateIfNeeded()
                await RefreshService.shared.refreshIfNeeded()
            }
        }
    }

    // MARK: - Container 构造（含迁移失败重建路径 + in-memory fallback）

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([Feed.self, Article.self, UsageRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let c = try ModelContainer(for: schema, configurations: config)
            Log.write("ModelContainer created OK")
            return c
        } catch {
            // 迁移失败：删旧库重建（今日文章下次 refresh 重新抓取即可）
            Log.write("ModelContainer failed, resetting store: \(error)")
            for suffix in ["", "-shm", "-wal"] {
                let url = URL.applicationSupportDirectory.appending(path: "default.store\(suffix)")
                try? FileManager.default.removeItem(at: url)
            }
            do {
                let c = try ModelContainer(for: schema, configurations: config)
                Log.write("ModelContainer recreated OK")
                // 容灾去重：重建后理论上空库，此调用作为防御兜底
                Task { @MainActor in
                    BuiltInFeeds.deduplicateArticles(context: ModelContext(c))
                }
                return c
            } catch {
                // 二次失败 → fallback in-memory，避免 SIGABRT 直接退出
                // 用户至少能看到菜单栏，本次会话数据不持久化（下次启动若磁盘恢复会自动重试）
                Log.write("ModelContainer second attempt failed, falling back to in-memory: \(error)")
                let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(for: schema, configurations: memConfig)
                } catch {
                    // in-memory 都构造不出来属于 schema 严重错误，此时崩溃可接受
                    Log.write("[FATAL] in-memory ModelContainer also failed: \(error)")
                    fatalError("无法初始化数据存储：\(error.localizedDescription)")
                }
            }
        }
    }
}
