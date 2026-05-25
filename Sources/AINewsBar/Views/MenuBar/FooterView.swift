import SwiftUI
import SwiftData

struct FooterView: View {
    let category: AINewsBar.Category
    @EnvironmentObject private var refreshService: RefreshService
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \UsageRecord.timestamp, order: .reverse) private var usageRecords: [UsageRecord]

    private var perCatState: CategoryState { refreshService.state(for: category) }

    /// v2: 今日成功调用的 token 总数 (三 cat 累加 — spec Q5f Footer 显示总和)。
    /// 在 body 内计算以规避 @Query 谓词初始化时捕获 Date() 的问题（CLAUDE.md 踩坑 #6）。
    private var todayTokenTotal: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return usageRecords
            .filter { $0.success && $0.timestamp >= start }
            .reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
    }

    var body: some View {
        HStack {
            if let date = perCatState.lastRefreshDate {
                VStack(alignment: .leading, spacing: 1) {
                    Text("最后更新")
                        .font(Typography.caption)
                        .foregroundStyle(TextColor.tertiary)
                    HStack(spacing: 6) {
                        Text(date, format: .dateTime.hour().minute().second())
                            .font(Typography.caption)
                            .foregroundStyle(TextColor.secondary)
                        if todayTokenTotal > 0 {
                            Text("· 今日 \(UsageFormatter.formatTokens(todayTokenTotal)) tokens")
                                .font(Typography.caption)
                                .foregroundStyle(TextColor.tertiary)
                        }
                    }
                }
            } else {
                Text("未刷新")
                    .font(Typography.caption)
                    .foregroundStyle(TextColor.tertiary)
            }
            Spacer()
            if perCatState.lastFetchErrorCount > 0 {
                // v2: 点击直接重试当前 cat（启动期网络未就绪是常见 race，让用户一键验证）
                Button {
                    Task { await refreshService.refresh(category) }
                } label: {
                    Text("⚠ 上次 \(perCatState.lastFetchErrorCount) 源失败 · 点击重试")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColor.accent)
                }
                .buttonStyle(.plain)
                .disabled(perCatState.isRefreshing)
                .help("启动期网络问题常见。点击重新抓取该 tab；如仍失败再去设置查具体源")
            }
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Text("设置")
                    .font(Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TextColor.secondary)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("退出")
                    .font(Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(TextColor.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
