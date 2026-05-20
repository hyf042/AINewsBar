import SwiftUI

struct FooterView: View {
    @EnvironmentObject private var refreshService: RefreshService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            if let date = refreshService.lastRefreshDate {
                VStack(alignment: .leading, spacing: 1) {
                    Text("最后更新")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(date, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
