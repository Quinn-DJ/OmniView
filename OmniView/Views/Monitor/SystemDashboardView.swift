import Charts
import SwiftUI

/// 系统监控仪表盘
/// 布局：
///   - 顶部简要指标：CPU / 内存 / 温度 / 网络
///   - 下方 3×2 图表面板：CPU 活动、内存占用、网络活动 / 温度活动、功耗活动、磁盘详情
///   - 电池信息已移至「系统信息」页
struct SystemDashboardView: View {
    @EnvironmentObject private var viewModel: SystemMonitorViewModel

    private let statusColumns = [
        GridItem(.adaptive(minimum: 175, maximum: 250), spacing: 12),
    ]
    private let panelColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let snapshot = viewModel.snapshot {
                    statusMetrics(snapshot)
                    // 3×2 图表面板：第一行 CPU/内存/网络，第二行 温度/功耗/磁盘
                    LazyVGrid(columns: panelColumns, spacing: 12) {
                        cpuPanel(snapshot)
                        memoryPanel(snapshot)
                        networkPanel(snapshot)
                        thermalPanel(snapshot)
                        powerPanel(snapshot)
                        diskPanel(snapshot)
                    }
                } else {
                    ProgressView("正在采集系统指标…")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .frame(maxWidth: 1060)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .navigationTitle("系统监控")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.sampleNow()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("立即采样")
            }
        }
    }

    // MARK: - 简要指标行（CPU / 内存 / 温度 / 网络）

    private func statusMetrics(_ snapshot: SystemSnapshot) -> some View {
        LazyVGrid(columns: statusColumns, spacing: 12) {
            StatusMetricCard(
                title: "CPU 使用率",
                systemImage: "cpu",
                value: Format.percent(snapshot.cpu.total),
                detail: "用户 \(Format.percent(snapshot.cpu.user, fractionDigits: 1)) · 系统 \(Format.percent(snapshot.cpu.system, fractionDigits: 1))",
                indicatorColor: utilizationColor(snapshot.cpu.total / 100)
            )

            StatusMetricCard(
                title: "内存",
                systemImage: "memorychip",
                value: Format.percent(snapshot.memory.usedFraction * 100),
                detail: "已用 \(Format.bytes(snapshot.memory.used)) · 可用 \(Format.bytes(snapshot.memory.available))",
                indicatorColor: memoryColor(snapshot.memory.usedFraction)
            )

            StatusMetricCard(
                title: "SoC 温度",
                systemImage: "thermometer.medium",
                value: Format.celsius(snapshot.temperature.socCelsius),
                detail: "\(thermalStatusTitle(snapshot.temperature.status)) · 电池 \(Format.celsius(snapshot.temperature.batteryCelsius))",
                indicatorColor: temperatureColor(snapshot.temperature.socCelsius)
            )

            StatusMetricCard(
                title: "网络",
                systemImage: "network",
                value: "↓ \(Format.rate(snapshot.network.downloadRate))",
                detail: "↑ \(Format.rate(snapshot.network.uploadRate))",
                indicatorColor: .blue
            )
        }
    }

    private func utilizationColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.5: return .blue
        case ..<0.8: return .orange
        default: return .red
        }
    }

    private func memoryColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .blue
        case ..<0.85: return .orange
        default: return .red
        }
    }

    private func diskColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.7: return .blue
        case ..<0.9: return .orange
        default: return .red
        }
    }

    private func thermalStatusTitle(_ status: ThermalStatus) -> String {
        switch status {
        case .unavailable: return "不可用"
        case .normal: return "正常"
        case .warm: return "偏高"
        case .hot: return "过热"
        }
    }

    private func temperatureColor(_ celsius: Double?) -> Color {
        guard let celsius else { return .secondary }
        if celsius >= 95 { return .red }
        if celsius >= 80 { return .orange }
        return .blue
    }

    // MARK: - 最近 60 秒

    private var historyStart: Date {
        Date().addingTimeInterval(-60)
    }

    private func recent<T>(_ history: [T], keyPath: KeyPath<T, Date>) -> [T] {
        history.filter { $0[keyPath: keyPath] >= historyStart }
    }

    // MARK: - CPU 面板

    private func cpuPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "CPU 活动", subtitle: "最近 60 秒") {
            PerformanceAreaLineChart(
                points: recent(viewModel.cpuHistory, keyPath: \.timestamp).map {
                    LineChartPoint(timestamp: $0.timestamp, value: $0.total, series: "CPU", color: .blue)
                },
                color: utilizationColor(snapshot.cpu.total / 100),
                height: 160
            )
        }
    }

    // MARK: - 内存面板

    private func memoryPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "内存占用", subtitle: "当前") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.bytes(snapshot.memory.used))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已用 \(Format.percent(snapshot.memory.usedFraction * 100))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                PercentBar(
                    fraction: snapshot.memory.usedFraction,
                    color: memoryColor(snapshot.memory.usedFraction)
                )
                HStack {
                    Text("可用 \(Format.bytes(snapshot.memory.available))")
                    Spacer()
                    Text("共 \(Format.bytes(snapshot.memory.total))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 网络面板

    private func networkPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "网络活动", subtitle: "最近 60 秒") {
            VStack(alignment: .leading, spacing: 8) {
                ChartLegendRow(
                    title: "下载",
                    value: Format.rate(snapshot.network.downloadRate),
                    color: .blue
                )
                ChartLegendRow(
                    title: "上传",
                    value: Format.rate(snapshot.network.uploadRate),
                    color: .green
                )
            }

            let networkPoints = recent(viewModel.networkHistory, keyPath: \.timestamp).flatMap { entry in
                [
                    LineChartPoint(
                        timestamp: entry.timestamp,
                        value: entry.downloadRate / 1_048_576,
                        series: "下载",
                        color: .blue
                    ),
                    LineChartPoint(
                        timestamp: entry.timestamp,
                        value: entry.uploadRate / 1_048_576,
                        series: "上传",
                        color: .green
                    ),
                ]
            }
            PerformanceLineChart(
                points: networkPoints,
                yDomain: PerformanceLineChart.safeDomain(
                    values: networkPoints.map(\.value), floor: 0.1
                ),
                height: 150
            )
            Text("速率单位：MB/s · 累计 ↓\(Format.bytes(snapshot.network.downloadTotal)) · ↑\(Format.bytes(snapshot.network.uploadTotal))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - 温度面板

    private func thermalPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "温度活动", subtitle: "最近 60 秒") {
            let temperaturePoints = recent(viewModel.temperatureHistory, keyPath: \.timestamp)
            PerformanceLineChart(
                points: temperaturePoints.compactMap { entry in
                    entry.socCelsius.map {
                        LineChartPoint(
                            timestamp: entry.timestamp,
                            value: $0,
                            series: "SoC",
                            color: temperatureColor(entry.socCelsius)
                        )
                    }
                },
                yDomain: PerformanceLineChart.paddedDomain(
                    values: temperaturePoints.compactMap(\.socCelsius)
                ),
                height: 160
            )
            HStack(spacing: 12) {
                ChartLegendRow(
                    title: "电池",
                    value: Format.celsius(snapshot.temperature.batteryCelsius),
                    color: .secondary
                )
                ChartLegendRow(
                    title: "存储",
                    value: Format.celsius(snapshot.temperature.storageCelsius),
                    color: .secondary
                )
            }
        }
    }

    // MARK: - 功耗面板

    private func powerPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "功耗活动", subtitle: "最近 60 秒") {
            VStack(alignment: .leading, spacing: 8) {
                ChartLegendRow(
                    title: "系统功耗",
                    value: Format.watts(snapshot.power.systemWatts),
                    color: .orange
                )
                ChartLegendRow(
                    title: "充电功耗",
                    value: Format.watts(snapshot.power.chargingWatts),
                    color: .green
                )
                if snapshot.power.adapterInputWatts != nil {
                    ChartLegendRow(
                        title: "适配器输入",
                        value: Format.watts(snapshot.power.adapterInputWatts),
                        color: .secondary
                    )
                }
            }

            // 多序列折线（仅线条，无面积填充，配合安全 y 域避免颜色溢出）
            let powerPoints = recent(viewModel.powerHistory, keyPath: \.timestamp).flatMap { entry in
                [
                    entry.systemWatts.map {
                        LineChartPoint(timestamp: entry.timestamp, value: $0, series: "系统", color: .orange)
                    },
                    entry.chargingWatts.map {
                        LineChartPoint(timestamp: entry.timestamp, value: $0, series: "充电", color: .green)
                    },
                ].compactMap { $0 }
            }
            PerformanceLineChart(
                points: powerPoints,
                yDomain: PerformanceLineChart.safeDomain(
                    values: powerPoints.map(\.value)
                ),
                height: 150
            )
        }
    }

    // MARK: - 磁盘面板（详细信息）

    private func diskPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "磁盘", subtitle: "当前") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.bytes(snapshot.disk.used))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已用 \(Format.percent(snapshot.disk.usedFraction * 100))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                PercentBar(
                    fraction: snapshot.disk.usedFraction,
                    color: diskColor(snapshot.disk.usedFraction)
                )
                HStack {
                    Text("可用 \(Format.bytes(snapshot.disk.available))")
                    Spacer()
                    Text("共 \(Format.bytes(snapshot.disk.total))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 16) {
                    ChartLegendRow(
                        title: "读取",
                        value: Format.rate(snapshot.disk.readRate),
                        color: .blue
                    )
                    ChartLegendRow(
                        title: "写入",
                        value: Format.rate(snapshot.disk.writeRate),
                        color: .green
                    )
                }
            }
        }
    }
}
