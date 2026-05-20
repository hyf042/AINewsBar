import Foundation
import SwiftData

// 统一收口 SwiftData 操作错误：失败时 Log 记录 + 返回安全默认值
// 替代散落各处的 try? context.{fetch,save,fetchCount}
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
}
