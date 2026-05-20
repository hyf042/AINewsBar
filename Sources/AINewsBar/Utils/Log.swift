import Foundation
import os

// 包装 os.Logger：调用点签名兼容（write(_:)）；线程安全、零文件 IO 开销
// 输出可在 Console.app 用 subsystem=com.ainewsbar 过滤；Xcode 控制台直接可见
enum Log {
    private static let logger = Logger(subsystem: "com.ainewsbar", category: "app")

    static func write(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }
}
