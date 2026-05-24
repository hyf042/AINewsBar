import Foundation

/// 移除 AI 输出中常见的 markdown 噪声标记，避免在不渲染 markdown 的 UI 中字面显示
///
/// 处理范围（按 spec）：
/// - `**bold**` / `__bold__` → 去掉标记，保留内容
/// - 行首 `#` / `##` / `###` 等标题前缀 → 整段去掉
///
/// 不处理：
/// - 行首 `- ` / `* ` / `+ ` 列表符号（中文摘要里合理的层次表达，保留更自然）
/// - 单个 `*` `_` 强调（误伤普通文本风险高，且实测罕见）
/// - 反引号、链接、图片（AI 摘要中几乎不出现）
enum MarkdownStripper {
    static func strip(_ text: String) -> String {
        let withoutBold = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")

        // 逐行处理标题前缀：split 后保留空行，处理完再 join
        let lines = withoutBold.split(separator: "\n", omittingEmptySubsequences: false)
        let cleanedLines = lines.map { line -> String in
            String(line).replacingOccurrences(
                of: #"^#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
        }
        return cleanedLines.joined(separator: "\n")
    }
}
