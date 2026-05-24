import SwiftUI
import SwiftData
import Charts

struct UsageSettingsView: View {
    @Query(sort: \UsageRecord.timestamp) private var records: [UsageRecord]
    @State private var rangeDays = 7
    /// 跨日刷新锚点 —— SwiftUI @Query 仅响应 SwiftData 变更，不响应系统时钟
    /// 用户跨过零点后留着 Tab 不动，今日卡片需要这个 State 强制重 eval
    @State private var now = Date()
    private let clockTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                todaySection
                trendSection
            }
            .padding(20)
        }
        .onReceive(clockTimer) { tick in
            // 仅跨日时才更新 now —— 否则每分钟 view 重 eval 性能浪费（Charts 也会重绘）
            if !Calendar.current.isDate(tick, inSameDayAs: now) {
                now = tick
            }
        }
    }

    // MARK: - Sections

    private var todaySection: some View {
        let stats = UsageAggregator.todayStats(records, now: now)
        return VStack(alignment: .leading, spacing: 8) {
            Text("今日用量")
                .font(Typography.titleEmphasized)
                .foregroundStyle(TextColor.secondary)
            HStack(spacing: 10) {
                statCard(label: "Tokens", value: UsageFormatter.formatTokens(stats.totalTokens))
                statCard(label: "调用次数", value: "\(stats.calls)")
                statCard(label: "失败",
                         value: "\(stats.failures)",
                         tint: stats.failures > 0 ? BrandColor.accent : TextColor.secondary)
            }
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("趋势")
                    .font(Typography.titleEmphasized)
                    .foregroundStyle(TextColor.secondary)
                Spacer()
                Picker("周期", selection: $rangeDays) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            chart
        }
    }

    @ViewBuilder
    private var chart: some View {
        let points = UsageAggregator.dailyByScene(records, days: rangeDays, now: now)
        if points.isEmpty {
            VStack {
                Text("暂无用量数据")
                    .font(Typography.body)
                    .foregroundStyle(TextColor.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            Chart(points) { p in
                BarMark(
                    x: .value("日期", p.day, unit: .day),
                    y: .value("Tokens", p.tokens)
                )
                .foregroundStyle(by: .value("场景", sceneLabel(p.scene)))
            }
            .chartForegroundStyleScale([
                sceneLabel(.summary): .blue,
                sceneLabel(.recommend): .green,
                sceneLabel(.digest): .orange
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
                }
            }
            .frame(height: 220)
        }
    }

    // MARK: - Helpers

    private func sceneLabel(_ scene: UsageScene) -> String {
        switch scene {
        case .summary: return "摘要"
        case .recommend: return "推荐"
        case .digest: return "日报"
        }
    }

    private func statCard(label: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(TextColor.secondary)
            Text(value)
                .font(Typography.stat)
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
    }
}
