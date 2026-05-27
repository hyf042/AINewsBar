import Foundation

/// 文章 URL 去重 normalizer（**仅用于比对**，不替代存储 URL）。
///
/// 第十三轮 P3 review：旧裸字符串 `existingURLs.contains(raw.url)` 让以下 case 重复入库：
/// - "https://a.com/foo" vs "https://a.com/foo/"
/// - "https://Example.com/foo" vs "https://example.com/foo"（RFC 3986: host 大小写不敏感）
/// - "https://a.com/foo" vs "https://a.com/foo#section-1"（fragment 不影响资源）
/// 重复入库 → 重复跑 summary/filter → 重复烧 token。
///
/// **保守原则**（critical）：宁可"漏归一化"重复入库一次（成本：1 篇文章 1 次 AI 调用），
/// **绝不**"误归一化"把两个不同文章合并（成本：用户少看一条新闻 + 数据不可恢复）：
/// - **保留** query 串：`?id=123` 是路径不可丢；`?utm_*` 追踪参数虽常造成重复，但
///   "凡是 query 就丢"会误伤合法路径（GitHub PR URL `?diff=split` 等）
/// - **保留** path / query 大小写：RFC 3986 path 部分大小写敏感
/// - **仅** scheme + host 小写（这两层 RFC 明确大小写不敏感）
/// - **仅** 删 fragment + 单次 path 尾斜杠
enum URLNormalizer {
    /// 返回归一化字符串用于去重比对。**不**做存储字段。
    /// URL 解析失败时 fallback 到"trim + lowercase"兜底（与原 AddFeedSheet 行为兼容，
    /// 避免脏 URL 串崩溃比对逻辑）。
    static func normalize(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        // URLComponents 严格解析；非合法 URL（如 "javascript:...", "data:..." 等）host=nil 走 fallback
        guard var components = URLComponents(string: trimmed),
              components.host != nil else {
            return fallback(trimmed)
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        // path 尾斜杠归一化：删全部尾斜杠（"/foo/" → "/foo"；root "/" → ""）
        // 这样 "https://a.com" 与 "https://a.com/" 等价（RFC 3986 同一资源）
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.string ?? fallback(trimmed)
    }

    /// 兜底：trim + lowercase 整串 + 去单次尾斜杠
    /// 与第九轮 AddFeedSheet.normalize 行为兼容（避免迁移期老脏数据 mismatch）
    private static func fallback(_ s: String) -> String {
        var result = s.lowercased()
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
