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

        // P3-C: 检查 syncInto 返回值。失败意味着 feed 表可能不完整或空，
        // 后续 refresh 会跑出"无 feed → 0 文章 → lastRefreshDate 更新但 UI 空"
        // 的诡异状态。失败路径：banner 提示用户重启 + 跳过 launchBackgroundRefresh
        // 避免污染 "最后刷新时间"。已存在的旧 feed 数据仍可被 refresh 使用。
        let feedsSynced = BuiltInFeeds.syncInto(context: ctx)
        RefreshService.shared.postUnreadCount(context: ctx)

        if feedsSynced {
            RefreshService.shared.launchBackgroundRefreshIfNeeded()
        } else {
            // 走 startupError 而非 globalAIError：RSS/store 启动错误不是 AI 故障，
            // 不应被任何 AI 成功调用静默清除，也不应让 UI 文案显示成"AI 不可用"。
            Log.write("[Startup] BuiltInFeeds.syncInto failed; skip auto-refresh, surface error in UI")
            RefreshService.shared.startupError = "内置 RSS 源初始化失败，请重启应用"
        }

        // 监听系统从睡眠唤醒：Timer.scheduledTimer 在 App Nap/睡眠期间不按真实时间累计
        // 唤醒后只合并触发一次，跨日重置可能在用户不点菜单时丢失 24h+；这里兜底
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await RefreshService.shared.handleSystemWake()
            }
        }
    }

    // MARK: - Schema 版本与 Migration

    /// 当前 schema 版本。每次 schema 不兼容变更时升版本号触发主动全清。
    /// v2-multi-category (2026-05-24)：引入 Category 维度，Article/Feed/UsageRecord 加字段。
    private static let currentSchemaVersion = "v2-multi-category"

    /// 永远保留的 prefs key（schema migration 不清理）。
    /// API Key + Model：避免用户每次升级重填。
    /// 其他系统 key（launchAtLogin / SwiftUI window 状态）通过"前缀白名单"自然保留。
    private static let preservedPrefsKeys: Set<String> = [
        "com.ainewsbar.claude-api-key",
        "com.ainewsbar.model",
    ]

    /// schema 版本不匹配时主动清理：
    /// 1. 删 SwiftData store（schema 不兼容）
    /// 2. 用白名单方式清理 `com.ainewsbar.` 前缀业务 key（保留 API Key + Model）
    /// 3. 非 `com.ainewsbar.` 前缀的 key（如 launchAtLogin / SwiftUI 状态）自然保留
    /// 4. 标记首次启动（启动刷新据此仅触发 AI cat）
    /// 用户决策：无数据迁移需求，全清接受。
    private static func performSchemaMigrationIfNeeded() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: "schemaVersion")
        guard stored != currentSchemaVersion else { return }

        Log.write("[Migration] schema version mismatch: \(stored ?? "nil") → \(currentSchemaVersion), wiping...")

        // 1. 删 SwiftData store（含 -shm / -wal sidecars）
        // M4: 失败不能静默 —— 权限/锁文件被占用导致删除失败时，下面 ModelContainer
        // 用旧 schema 数据库继续 → 抛错 → fallback in-memory（用户数据丢失）。
        // 至少记录失败原因供 Console.app 排查。
        for suffix in ["", "-shm", "-wal"] {
            let url = URL.applicationSupportDirectory.appending(path: "default.store\(suffix)")
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // 正常路径：sidecar 文件不存在
            } catch {
                Log.write("[Migration] failed to delete \(url.lastPathComponent): \(error)")
            }
        }

        // 2. 白名单清理：删 `com.ainewsbar.` 前缀且非保留项的 key
        // 这样：API Key + Model 保留；旧 digest/recommend 业务 key 清掉；
        // 非 `com.ainewsbar.` 前缀的系统 key (launchAtLogin / SwiftUI window 状态) 自然保留
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainewsbar.app"
        let allKeys = defaults.persistentDomain(forName: bundleID)?.keys ?? Dictionary<String, Any>().keys
        var removed = 0
        for key in allKeys where key.hasPrefix("com.ainewsbar.") && !preservedPrefsKeys.contains(key) {
            defaults.removeObject(forKey: key)
            removed += 1
        }

        // 3. 写新版本号 + 标记首次启动
        defaults.set(currentSchemaVersion, forKey: "schemaVersion")
        defaults.set(true, forKey: "firstLaunchAfterSchemaUpgrade")

        Log.write("[Migration] wipe complete; removed \(removed) old prefs keys; API Key+Model preserved; firstLaunch flag set")
    }

    // MARK: - Container 构造（含迁移失败重建路径 + in-memory fallback）

    private static func makeContainer() -> ModelContainer {
        // 优先做 schema 版本检测；不匹配则主动清 store/prefs，再继续走构造路径
        performSchemaMigrationIfNeeded()

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
                do {
                    try FileManager.default.removeItem(at: url)
                } catch CocoaError.fileNoSuchFile {
                    // 正常路径
                } catch {
                    Log.write("[Migration] reset failed to delete \(url.lastPathComponent): \(error)")
                }
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
