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
    ///
    /// v2-multi-category (2026-05-24)：引入 Category 维度，Article/Feed/UsageRecord 加字段。
    ///
    /// **v2-multi-category-r2 (2026-05-26)** — 第十轮 review，根因修复：
    /// v2 phase 1 后 v2 内部演进期（539da46 → a11a8f5）字段 init 默认值改过若干次
    /// （Article.accepted true→nil 等），SwiftData 自动迁移会保留旧行加列默认 NULL。
    /// 旧字符串 "v2-multi-category" 让所有跑过早期 v2 的机器 guard 跳过 → 21 行残留
    /// Article.category=NULL，fetch 时 mandatory field 校验失败 / 业务静默失败。
    /// bump 到 r2 强制全部早期机器再 nuke 一次。后续任何 v2 内部 schema 变更（含改默认值）
    /// 都应跟着升 r3 / r4，把"升 schemaVersion"列入 schema 变更必做项。
    private static let currentSchemaVersion = "v2-multi-category-r2"

    /// 永远保留的 prefs key（schema migration 不清理）。
    /// API Key + Model：避免用户每次升级重填。
    /// 其他系统 key（launchAtLogin / SwiftUI window 状态）通过"前缀白名单"自然保留。
    private static let preservedPrefsKeys: Set<String> = [
        "com.ainewsbar.claude-api-key",
        "com.ainewsbar.model",
    ]

    /// 删 store 文件（含 -shm / -wal sidecar）。fileNoSuchFile 不报错（sidecar 可能不存在）；
    /// 其他错误（权限、IO 锁）抛出由 caller 决定是否推进 guard。
    /// 抽成独立函数让 schemaVersion guard 路径与 makeContainer 二次重建路径复用。
    private static func wipeStoreFiles() throws {
        for suffix in ["", "-shm", "-wal"] {
            let url = URL.applicationSupportDirectory.appending(path: "default.store\(suffix)")
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // 正常路径：sidecar 文件不存在
            }
        }
    }

    /// store 已被强制清空（或视为重建过）后的善后：清业务 prefs + 写新版本号 + 标 firstLaunch。
    ///
    /// **P2 第十一轮 review**：抽出 helper 让两条路径共享 ——
    /// 1. `performSchemaMigrationIfNeeded` 主动迁移路径（guard mismatch）
    /// 2. `makeContainer` 兜底重建路径（构造或 sanity 失败 + 兜底 wipe 成功）
    ///
    /// 旧实现兜底路径只 set firstLaunchAfterSchemaUpgrade 不写 schemaVersion → 下次启动
    /// guard 仍判 mismatch → 又触发一次 wipe（用户数据再清一次）。
    /// 也不清业务 prefs → 空库下 prefs 显示有"已生成的日报"但磁盘没文章 → stale 引用。
    ///
    /// 白名单策略：删 `com.ainewsbar.` 前缀且非 preservedPrefsKeys 的 key。
    /// 这样：API Key + Model 保留；业务 key 清掉；系统 key（launchAtLogin / SwiftUI
    /// window 状态）因不带前缀自然保留。
    private static func markSchemaMigrationComplete() {
        let defaults = UserDefaults.standard
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ainewsbar.app"
        let allKeys = defaults.persistentDomain(forName: bundleID)?.keys ?? Dictionary<String, Any>().keys
        var removed = 0
        for key in allKeys where key.hasPrefix("com.ainewsbar.") && !preservedPrefsKeys.contains(key) {
            defaults.removeObject(forKey: key)
            removed += 1
        }
        defaults.set(currentSchemaVersion, forKey: "schemaVersion")
        defaults.set(true, forKey: "firstLaunchAfterSchemaUpgrade")
        Log.write("[Migration] mark complete; removed \(removed) old prefs keys; schemaVersion=\(currentSchemaVersion); API Key+Model preserved; firstLaunch flag set")
    }

    /// schema 版本不匹配时主动清理：删 store + markSchemaMigrationComplete()。
    /// 用户决策：无数据迁移需求，全清接受。
    ///
    /// **P1 第十轮 review（同型踩坑 #28）**：删 store 失败时**不能**推进
    /// schemaVersion 写入 —— 否则下次启动 guard 通过，旧库残留持续静默存在。
    /// 失败抛出由 caller (makeContainer) 决定 fallback（in-memory 或下次重试）。
    private static func performSchemaMigrationIfNeeded() throws {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: "schemaVersion")
        guard stored != currentSchemaVersion else { return }

        Log.write("[Migration] schema version mismatch: \(stored ?? "nil") → \(currentSchemaVersion), wiping...")

        // 删 store 失败抛出 — 不能让 markSchemaMigrationComplete 错误推进。
        try wipeStoreFiles()
        markSchemaMigrationComplete()
    }

    // MARK: - Container 构造（含迁移失败重建路径 + in-memory fallback）

    /// 启动时 sanity sweep：对 schema 中每个 @Model 做一次轻量 fetch（limit=1）。
    /// 目的：捕获 SwiftData 自动迁移留下"旧行 mandatory field=NULL"的隐性损坏
    /// （schemaVersion guard 漏抓时的最后一道防线）。fetch 阶段 SwiftData 会触发
    /// NSValidateForMandatoryAttribute 校验失败 → 抛错 → caller wipe + 重建。
    ///
    /// **P3 第十一轮 review**：原只 fetch Article 漏检 Feed / UsageRecord。
    /// Feed.category 这类 mandatory 字段坏掉时 Article sweep 通过，
    /// BuiltInFeeds.syncInto 才在业务路径失败 —— 结果是启动 banner +
    /// 不自动刷新，而不是自动重建。既然策略是"坏库全清"，sweep 应该覆盖全 schema。
    ///
    /// 失败 cost：误判会触发一次额外的 store 重建（数据全清），但 schemaVersion
    /// 不变。考虑非常少见 + 用户数据本来已经损坏，可接受。
    @MainActor
    private static func sanityCheckSchema(_ container: ModelContainer) throws {
        let ctx = ModelContext(container)
        var articleDesc = FetchDescriptor<Article>()
        articleDesc.fetchLimit = 1
        _ = try ctx.fetch(articleDesc)
        var feedDesc = FetchDescriptor<Feed>()
        feedDesc.fetchLimit = 1
        _ = try ctx.fetch(feedDesc)
        var usageDesc = FetchDescriptor<UsageRecord>()
        usageDesc.fetchLimit = 1
        _ = try ctx.fetch(usageDesc)
    }

    private static func makeContainer() -> ModelContainer {
        // 优先做 schema 版本检测；不匹配则主动清 store/prefs，再继续走构造路径
        do {
            try performSchemaMigrationIfNeeded()
        } catch {
            // P1：schema migration 失败不写 schemaVersion，下次启动重试。
            // 继续走 ModelContainer 构造路径（如果旧库与当前 schema 兼容仍可启动；
            // 不兼容则下面 try ModelContainer 失败进 catch 走 wipeStoreFiles 兜底）。
            Log.write("[Migration] performSchemaMigrationIfNeeded failed (will retry next launch): \(error)")
        }

        let schema = Schema([Feed.self, Article.self, UsageRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let c = try ModelContainer(for: schema, configurations: config)
            // P2 第十轮 review：构造成功不代表数据完整。SwiftData 自动迁移可能让旧行
            // mandatory-field=NULL 通过 schema check；fetch 时才校验。主动 fetch 全 schema
            // 触发校验，失败走重建路径。
            try MainActor.assumeIsolated {
                try sanityCheckSchema(c)
            }
            Log.write("ModelContainer created OK")
            return c
        } catch {
            // 构造或 sanity 失败：删旧库重建（今日文章下次 refresh 重新抓取即可）
            Log.write("ModelContainer or sanity failed, resetting store: \(error)")
            do {
                try wipeStoreFiles()
                // 兜底 wipe 成功 → markSchemaMigrationComplete 把"清业务 prefs + 写
                // schemaVersion + firstLaunch flag" 一起走，避免下次启动 guard 仍 mismatch
                // 又触发一次清库。第十一轮 P2 review。
                markSchemaMigrationComplete()
            } catch {
                Log.write("[Migration] reset failed to delete store: \(error)")
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
