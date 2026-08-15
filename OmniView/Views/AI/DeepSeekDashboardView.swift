import Charts
import SwiftUI

/// DeepSeek 监控看板
struct DeepSeekDashboardView: View {
    @EnvironmentObject private var viewModel: DeepSeekViewModel
    @Environment(\.openSettings) private var openSettings
    @State private var selectedTokenDate: Date?

    var body: some View {
        Group {
            if !viewModel.hasAPIKey {
                apiKeyPrompt
            } else {
                dashboard
            }
        }
        .navigationTitle("DeepSeek 监控")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let updated = viewModel.lastUpdated {
                    Text("更新于 \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoadingBalance || viewModel.isLoadingUsage)
            }
        }
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - 未配置 API Key（引导前往「设置」）

    private var apiKeyPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("配置 DeepSeek API Key")
                .font(.title2.weight(.semibold))
            Text("请在「设置 → DeepSeek」中配置 API Key。Key 将安全存储在 macOS 钥匙串中，仅用于向 DeepSeek 官方 API 查询余额与用量。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                openSettings()
            } label: {
                Label("打开设置…", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 看板

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.isLoadingBalance && viewModel.balance == nil {
                    ProgressView("正在查询余额…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if let balance = viewModel.balance {
                    balanceCard(balance)
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                usageSection

                if !viewModel.modelSummary.isEmpty {
                    modelSummaryCard
                }
            }
            .padding(14)
        }
    }

    // MARK: - 余额

    private func balanceCard(_ balance: BalanceInfo) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("账户余额")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(currencySymbol)
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(balance.totalDecimal.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(balance.currency)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                statPill("赠送余额", balance.grantedBalance, icon: "gift")
                statPill("充值余额", balance.toppedUpBalance, icon: "creditcard")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
    }

    private var currencySymbol: String {
        balanceCurrency == "CNY" ? "¥" : (balanceCurrency == "USD" ? "$" : "")
    }

    private var balanceCurrency: String {
        viewModel.balance?.currency ?? "CNY"
    }

    private func statPill(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 用量

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Token 用量")
                    .font(.headline)
                Spacer()
                Picker("", selection: $viewModel.usageDays) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: viewModel.usageDays) { _ in
                    Task { await viewModel.refresh() }
                }
            }

            if viewModel.isLoadingUsage && viewModel.usageRecords.isEmpty {
                ProgressView("正在加载用量数据…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if viewModel.usageRecords.isEmpty {
                VStack(spacing: 8) {
                    Text("暂无用量数据")
                        .foregroundStyle(.secondary)
                    Text("DeepSeek 用量接口可能尚未开放，或该时间段内没有调用记录。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                usageChart
                tokenUsageChart
                usageStatsRow
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var usageChart: some View {
        Chart(viewModel.dailyCostSeries, id: \.date) { entry in
            BarMark(
                x: .value("日期", entry.date, unit: .day),
                y: .value("费用", entry.cost)
            )
            .foregroundStyle(.blue.gradient)
            .cornerRadius(3)
        }
        .chartYAxisLabel("费用 (\(balanceCurrency))")
        .frame(height: 180)
    }

    // MARK: - 按日 Token 堆叠柱 + hover 明细

    private var tokenUsageChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("按日 Token 消耗")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("合计 \(compactTokens(viewModel.totalTokens))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Chart(viewModel.dailyTokenUsage, id: \.date) { day in
                BarMark(
                    x: .value("日期", day.date, unit: .day),
                    y: .value("Tokens", day.cacheHit),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("类型", "输入 · 缓存命中"))

                BarMark(
                    x: .value("日期", day.date, unit: .day),
                    y: .value("Tokens", day.cacheMiss),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("类型", "输入 · 未命中"))

                BarMark(
                    x: .value("日期", day.date, unit: .day),
                    y: .value("Tokens", day.output),
                    stacking: .standard
                )
                .foregroundStyle(by: .value("类型", "输出"))
            }
            .chartForegroundStyleScale([
                "输入 · 缓存命中": Color.teal,
                "输入 · 未命中": Color.orange,
                "输出": Color.indigo,
            ])
            .chartYAxisLabel("Tokens")
            .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                selectedTokenDate = proxy.value(atX: location.x) as Date?
                            case .ended:
                                selectedTokenDate = nil
                            }
                        }
                        .overlay(alignment: .top) {
                            if let day = hoveredTokenDay {
                                TokenUsageTooltip(day: day)
                                    .frame(width: 190)
                                    .offset(
                                        x: tooltipOffsetX(proxy: proxy, chartWidth: geometry.size.width),
                                        y: 4
                                    )
                            }
                        }
                }
            }
            .frame(height: 180)
        }
    }

    private var hoveredTokenDay: DailyTokenUsage? {
        guard let selectedTokenDate else { return nil }
        return viewModel.dailyTokenUsage.first {
            Calendar.current.isDate($0.date, inSameDayAs: selectedTokenDate)
        }
    }

    private func tooltipOffsetX(proxy: ChartProxy, chartWidth: CGFloat) -> CGFloat {
        guard let day = hoveredTokenDay,
              let x = proxy.position(forX: day.date)
        else {
            return 0
        }
        let tooltipWidth: CGFloat = 190
        let minOffset: CGFloat = 6
        let maxOffset = max(minOffset, chartWidth - tooltipWidth - 6)
        return min(max(x - tooltipWidth / 2, minOffset), maxOffset)
    }

    private func compactTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.2fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private var usageStatsRow: some View {
        HStack(spacing: 24) {
            statItem("总 Token", "\(viewModel.totalTokens)", icon: "number")
            statItem("本月费用", viewModel.totalCostThisMonth.formatted(.number.precision(.fractionLength(2))), icon: "yensign")
            statItem("记录天数", "\(viewModel.usageRecords.count)", icon: "calendar")
            Spacer()
        }
        .font(.callout)
    }

    private func statItem(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - 模型用量汇总

    private var modelSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("按模型统计")
                .font(.headline)
            ForEach(viewModel.modelSummary, id: \.model) { entry in
                HStack(spacing: 10) {
                    Text(entry.model)
                        .font(.callout.weight(.medium))
                        .frame(width: 140, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            let maxCost = viewModel.modelSummary.first?.cost ?? 1
                            Capsule()
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: max(6, proxy.size.width * CGFloat(NSDecimalNumber(decimal: entry.cost).doubleValue / max(0.0001, NSDecimalNumber(decimal: maxCost).doubleValue))))
                        }
                    }
                    .frame(height: 8)
                    Text("\(entry.tokens) tokens")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                    Text(entry.cost.formatted(.number.precision(.fractionLength(2))))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - 按日 Token 明细浮层

private struct TokenUsageTooltip: View {
    let day: DailyTokenUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.date.formatted(.dateTime.month().day()))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(day.total) tokens")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            Divider()

            tooltipRow(title: "输入 · 缓存命中", value: day.cacheHit, color: .teal)
            tooltipRow(title: "输入 · 未命中", value: day.cacheMiss, color: .orange)
            tooltipRow(title: "输出", value: day.output, color: .indigo)
            tooltipRow(title: "请求次数", value: day.requests, color: .secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func tooltipRow(title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}

// MARK: - Previews

#Preview("DeepSeek 看板") {
    DeepSeekDashboardView()
        .environmentObject(DeepSeekViewModel())
        .frame(width: 900, height: 700)
}
