import Charts
import SwiftUI

/// 系统监控仪表盘
/// 布局：顶部 6 项简要指标（CPU / 内存 / 功耗 / 温度 / 网络 / 磁盘）
///       + 下方 3 列图表/详情面板
struct SystemDashboardView: View {
    @EnvironmentObject private var viewModel: SystemMonitorViewModel

    private let statusColumns = [
        GridItem(.adaptive(minimum: 165, maximum: 240), spacing: 12),
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
                    LazyVGrid(columns: panelColumns, spacing: 12) {
                        cpuPanel(snapshot)
                        memoryPanel(snapshot)
                        powerPanel(snapshot)
                        thermalPanel(snapshot)
                        coolingPanel(snapshot)
                        networkPanel(snapshot)
                        diskPanel(snapshot)
                        batteryPanel(snapshot)
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

    // MARK: - 简要指标行（6 项）

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
                title: "系统功耗",
                systemImage: "bolt.fill",
                value: Format.watts(snapshot.power.systemWatts),
                detail: powerDetail(snapshot.power),
                indicatorColor: .orange
            )

            StatusMetricCard(
                title: "SoC 温度",
                systemImage: "thermometer.medium",
                value: Format.celsius(snapshot.temperature.socCelsius),
                detail: thermalStatusTitle(snapshot.temperature.status),
                indicatorColor: temperatureColor(snapshot.temperature.socCelsius)
            )

            StatusMetricCard(
                title: "网络",
                systemImage: "network",
                value: "↓ \(Format.rate(snapshot.network.downloadRate))",
                detail: "↑ \(Format.rate(snapshot.network.uploadRate))",
                indicatorColor: .blue
            )

            StatusMetricCard(
                title: "磁盘",
                systemImage: "internaldrive",
                value: Format.percent(snapshot.disk.usedFraction * 100),
                detail: "可用 \(Format.bytes(snapshot.disk.available)) · 共 \(Format.bytes(snapshot.disk.total))",
                indicatorColor: diskColor(snapshot.disk.usedFraction)
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

    private func powerDetail(_ power: PowerUsage) -> String {
        guard power.systemWatts != nil else { return "功耗遥测不可用" }
        switch power.isExternalPowerConnected {
        case true: return "已连接电源"
        case false: return "正在使用电池"
        case nil: return "实时系统负载"
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
                height: 160
            )
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

    // MARK: - 散热面板

    private func coolingPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "散热", subtitle: snapshot.cooling.state == .available ? "最近 60 秒" : "只读") {
            switch snapshot.cooling.state {
            case .available:
                let fanPoints = recent(viewModel.coolingHistory, keyPath: \.timestamp).flatMap { cooling in
                    cooling.fans.map { fan in
                        LineChartPoint(
                            timestamp: cooling.timestamp,
                            value: fan.currentRPM,
                            series: fan.name,
                            color: Self.fanChartColors[fan.id % Self.fanChartColors.count]
                        )
                    }
                }
                PerformanceLineChart(
                    points: fanPoints,
                    yDomain: PerformanceLineChart.safeDomain(
                        values: fanPoints.map(\.value), floor: 1_000
                    ),
                    height: 140
                )

                Divider()
                fanDetails(snapshot.cooling)
            case .fanless:
                capabilityView(
                    systemImage: "fan.slash",
                    title: "无风扇 Mac",
                    message: "这台 Mac 使用被动散热，不提供风扇转速。"
                )
            case .unavailable:
                capabilityView(
                    systemImage: "fan",
                    title: "风扇遥测不可用",
                    message: "无法读取此 Mac 的风扇转速。"
                )
            }
        }
    }

    /// 窄列布局：每个风扇一行「名称 + 当前转速」，下方一行最低/目标/最高
    private func fanDetails(_ cooling: CoolingUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cooling.fans) { fan in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Label(fan.name, systemImage: "fan")
                            .font(.subheadline)
                        Spacer()
                        Text(Format.rpm(fan.currentRPM))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    Text("最低 \(Format.rpm(fan.minimumRPM)) · 目标 \(Format.rpm(fan.targetRPM)) · 最高 \(Format.rpm(fan.maximumRPM))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func capabilityView(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private static let fanChartColors: [Color] = [.blue, .teal, .indigo, .cyan]

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

    // MARK: - 磁盘面板

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
                HStack(spacing: 16) {
                    Label("读 \(Format.rate(snapshot.disk.readRate))", systemImage: "arrow.down")
                    Label("写 \(Format.rate(snapshot.disk.writeRate))", systemImage: "arrow.up")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                HStack {
                    Text("可用 \(Format.bytes(snapshot.disk.available))")
                    Spacer()
                    Text("共 \(Format.bytes(snapshot.disk.total))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 电池面板

    private func batteryPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "电池", subtitle: batterySubtitle(snapshot.battery)) {
            if let percent = snapshot.battery.percent {
                HStack(spacing: 10) {
                    batteryGauge(
                        title: "电量",
                        systemImage: batterySymbol(snapshot.battery),
                        value: percent / 100,
                        valueText: String(format: "%.0f%%", percent),
                        tint: batteryPercentColor(percent)
                    )
                    batteryGauge(
                        title: "最大容量",
                        systemImage: "heart.text.square",
                        value: snapshot.battery.healthPercent.map { Double($0) / 100 },
                        valueText: snapshot.battery.healthPercent.map { "\($0)%" } ?? "—",
                        tint: snapshot.battery.healthPercent.map { healthColor($0) } ?? .secondary
                    )
                    batteryGauge(
                        title: "循环",
                        systemImage: "arrow.triangle.2.circlepath",
                        value: nil,
                        valueText: snapshot.battery.cycleCount.map(String.init) ?? "—",
                        tint: .secondary
                    )
                }

                Divider()

                VStack(spacing: 0) {
                    batteryDetailRow("电源来源", systemImage: "powerplug",
                        value: snapshot.battery.isExternalConnected == true ? "电源适配器" : "电池")
                    Divider()
                    batteryDetailRow("充电状态", systemImage: "bolt",
                        value: snapshot.battery.isCharging ? "正在充电" : "未充电")
                    Divider()
                    batteryDetailRow("电压", systemImage: "waveform.path",
                        value: snapshot.battery.voltageMillivolts.map { String(format: "%.2f V", Double($0) / 1_000) } ?? "—")
                    Divider()
                    batteryDetailRow("温度", systemImage: "thermometer.medium",
                        value: Format.celsius(snapshot.temperature.batteryCelsius))
                }
            } else {
                capabilityView(
                    systemImage: "battery.slash",
                    title: "未检测到电池",
                    message: "这台 Mac 未报告内置电池。"
                )
            }
        }
    }

    private func batterySubtitle(_ battery: BatteryUsage) -> String {
        if battery.isCharging { return "充电中" }
        if battery.isExternalConnected == true { return "已连接电源" }
        return "使用电池"
    }

    private func batterySymbol(_ battery: BatteryUsage) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        guard let percent = battery.percent else { return "battery.0percent" }
        switch percent {
        case 75...: return "battery.100percent"
        case 50...: return "battery.75percent"
        case 25...: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    private func batteryPercentColor(_ percent: Double) -> Color {
        percent < 20 ? .red : (percent < 40 ? .orange : .green)
    }

    private func healthColor(_ percent: Int) -> Color {
        percent < 70 ? .red : (percent < 80 ? .orange : .green)
    }

    private func batteryGauge(
        title: String,
        systemImage: String,
        value: Double?,
        valueText: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 4) {
            Gauge(value: min(1, max(0, value ?? 0))) {
                Label(title, systemImage: systemImage)
            } currentValueLabel: {
                Text(valueText)
                    .font(.headline)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(value == nil ? .secondary : tint)
            .controlSize(.large)
            .scaleEffect(0.95)
            .frame(width: 82, height: 74)

            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func batteryDetailRow(_ title: String, systemImage: String, value: String) -> some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minHeight: 32)
    }
}
