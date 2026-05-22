import Foundation

/// Token 数字格式化（纯函数，可单测）。Footer 与 Usage Tab 共用。
enum UsageFormatter {
    /// `<1000` 原值；`<1_000_000` 显示 `12.4K`；否则 `1.2M`。
    /// 一位小数；保证非负输入。
    static func formatTokens(_ n: Int) -> String {
        let v = max(0, n)
        if v < 1_000 { return "\(v)" }
        if v < 1_000_000 {
            let scaled = Double(v) / 1_000
            return "\(trim(scaled))K"
        }
        let scaled = Double(v) / 1_000_000
        return "\(trim(scaled))M"
    }

    /// 一位小数，末尾 0 与小数点去掉：1.0 → "1"，12.4 → "12.4"。
    private static func trim(_ x: Double) -> String {
        let rounded = (x * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded))" }
        return String(format: "%.1f", rounded)
    }
}
