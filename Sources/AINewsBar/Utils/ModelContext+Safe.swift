import Foundation
import SwiftData

// 统一收口 SwiftData 操作错误：失败时 Log 记录 + 返回安全默认值
// 替代散落各处的 try? context.{fetch,save,fetchCount}
//
// 双轨 API 说明：
// - `safeFetch / safeSave / safeFetchCount`：失败容忍（返回空集合 / false / 0）。
//   仅用于失败可降级的非关键路径，如 cleanupOldArticles、postUnreadCount、insert 后 save 等。
// - `safeFetchOrThrow / safeSaveOrThrow`：失败抛出。用于关键路径（去重 fetch、commit 等），
//   让 caller 区分"真的无数据"与"fetch 失败" —— 旧逻辑容忍空集合会导致重复入库/假空决策。
extension ModelContext {

    /// 保存失败返回 false，并写入日志（含调用位置）
    @discardableResult
    func safeSave(file: String = #fileID, line: Int = #line) -> Bool {
        do {
            try save()
            return true
        } catch {
            Log.write("[DB] save failed at \(file):\(line) — \(error)")
            return false
        }
    }

    /// 查询失败返回空数组，并写入日志（含调用位置）
    func safeFetch<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        file: String = #fileID,
        line: Int = #line
    ) -> [T] {
        do {
            return try fetch(descriptor)
        } catch {
            Log.write("[DB] fetch failed at \(file):\(line) — \(error)")
            return []
        }
    }

    /// 计数失败返回 0，并写入日志（含调用位置）
    func safeFetchCount<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        file: String = #fileID,
        line: Int = #line
    ) -> Int {
        do {
            return try fetchCount(descriptor)
        } catch {
            Log.write("[DB] fetchCount failed at \(file):\(line) — \(error)")
            return 0
        }
    }

    /// 严格模式：查询失败抛出，并记录日志。用于关键路径（去重检查、commit 前重查等）
    func safeFetchOrThrow<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        file: String = #fileID,
        line: Int = #line
    ) throws -> [T] {
        do {
            return try fetch(descriptor)
        } catch {
            Log.write("[DB] fetch (strict) failed at \(file):\(line) — \(error)")
            throw error
        }
    }

    /// 严格模式：保存失败抛出，并记录日志。用于关键路径（commit summaries 等）
    func safeSaveOrThrow(file: String = #fileID, line: Int = #line) throws {
        do {
            try save()
        } catch {
            Log.write("[DB] save (strict) failed at \(file):\(line) — \(error)")
            throw error
        }
    }
}
