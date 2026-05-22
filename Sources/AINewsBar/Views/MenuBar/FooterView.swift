import SwiftUI
import SwiftData

struct FooterView: View {
    @EnvironmentObject private var refreshService: RefreshService
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \UsageRecord.timestamp, order: .reverse) private var usageRecords: [UsageRecord]

    /// 今日成功调用的 token 总数（input + output）。
    /// 在 body 内计算以规避 @Query 谓词初始化时捕获 Date() 的问题（CLAUDE.md 踩坑 #6）。
    private var todayTokenTotal: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return usageRecords
            .filter { $0.success && $0.timestamp >= start }
            .reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }

    var body: some View {
        HStack {
            if let date = refreshService.lastRefreshDate {
                VStack(alignment: .leading, spacing: 1) {
                    Text("最后更新")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 6) {
                        Text(date, format: .dateTime.hour().minute().second())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if todayTokenTotal > 0 {
                            Text("· 今日 \(UsageFormatter.formatTokens(todayTokenTotal)) tokens")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                Text("未刷新")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if refreshService.lastFetchErrorCount > 0 {
                Button("⚠ \(refreshService.lastFetchErrorCount) 个源失败") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.orange)
            }
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Text("设置")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("退出")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
