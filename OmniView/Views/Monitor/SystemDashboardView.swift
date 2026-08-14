import Charts
import SwiftUI

/// 系统监控仪表盘
/// 布局参考 mac-scope 的「性能与功耗」页：
/// 状态指标行 + CPU / 功耗 / 温度 / 散热 面板 + 内存 / 网络 / 磁盘 / 电池面板
struct SystemDashboardView: View {
    @EnvironmentObject private var viewModel: SystemMonitorViewModel

    private let statusColumns = [
        GridItem(.adaptive(minimum: 175, maximum: 260), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let snapshot = viewModel.snapshot {
                    statusMetrics(snapshot)
                    cpuPanel(snapshot)
                    powerPanel(snapshot)
                    thermalPanel(snapshot)
                    coolingPanel(snapshot)
                    memoryPanel(snapshot)
                    networkPanel(snapshot)
                    diskPanel(snapshot)
                    batteryPanel(snapshot)
                } else {
                    ProgressView("正在采集系统指标…")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .frame(maxWidth: 900)
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

    // MARK: - 状态指标行

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
                title: "风扇转速",
                systemImage: "fan",
                value: fanHeadline(snapshot.cooling),
                detail: fanSupportDetail(snapshot.cooling),
                indicatorColor: .secondary
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

    private func fanHeadline(_ cooling: CoolingUsage) -> String {
        guard cooling.state == .available else { return "—" }
        return Format.rpm(cooling.fans.map(\.currentRPM).max())
    }

    private func fanSupportDetail(_ cooling: CoolingUsage) -> String {
        switch cooling.state {
        case .available:
            return cooling.fans.count == 1 ? "1 个风扇" : "\(cooling.fans.count) 个风扇"
        case .fanless:
            return "无风扇机型"
        case .unavailable:
            return "风扇遥测不可用"
        }
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
                height: 180
            )
        }
    }

    // MARK: - 功耗面板

    private func powerPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "功耗活动", subtitle: "最近 60 秒") {
            HStack(spacing: 24) {
                ChartLegendValue(
                    title: "系统功耗",
                    value: Format.watts(snapshot.power.systemWatts),
                    color: .orange
                )
                ChartLegendValue(
                    title: "充电功耗",
                    value: Format.watts(snapshot.power.chargingWatts),
                    color: .green
                )
                if snapshot.power.adapterInputWatts != nil {
                    ChartLegendValue(
                        title: "适配器输入",
                        value: Format.watts(snapshot.power.adapterInputWatts),
                        color: .secondary
                    )
                }
                Spacer(minLength: 0)
            }

            // 多序列折线（仅线条，无面积填充，配合安全 y 域避免颜色溢出）
            PerformanceLineChart(
                points: recent(viewModel.powerHistory, keyPath: \.timestamp).flatMap { entry in
                    [
                        entry.systemWatts.map {
                            LineChartPoint(timestamp: entry.timestamp, value: $0, series: "系统", color: .orange)
                        },
                        entry.chargingWatts.map {
                            LineChartPoint(timestamp: entry.timestamp, value: $0, series: "充电", color: .green)
                        },
                    ].compactMap { $0 }
                },
                yDomain: PerformanceLineChart.safeDomain(
                    values: recent(viewModel.powerHistory, keyPath: \.timestamp).compactMap(\.systemWatts)
                        + recent(viewModel.powerHistory, keyPath: \.timestamp).compactMap(\.chargingWatts)
                ),
                height: 180
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
                    height: 160
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

    private func fanDetails(_ cooling: CoolingUsage) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(cooling.fans.enumerated()), id: \.element.id) { index, fan in
                if index > 0 { Divider() }
                HStack(spacing: 16) {
                    Label(fan.name, systemImage: "fan")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    fanDetailValue("当前", value: fan.currentRPM)
                    fanDetailValue("最低", value: fan.minimumRPM)
                    fanDetailValue("目标", value: fan.targetRPM)
                    fanDetailValue("最高", value: fan.maximumRPM)
                }
                .frame(minHeight: 52)
            }
        }
    }

    private func fanDetailValue(_ title: String, value: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.rpm(value))
                .font(.subheadline)
                .monospacedDigit()
        }
        .frame(minWidth: 86, alignment: .trailing)
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

    // MARK: - 内存面板

    private func memoryPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "内存占用", subtitle: "当前") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.bytes(snapshot.memory.used))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已用 · \(Format.percent(snapshot.memory.usedFraction * 100))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("共 \(Format.bytes(snapshot.memory.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                PercentBar(
                    fraction: snapshot.memory.usedFraction,
                    color: memoryColor(snapshot.memory.usedFraction)
                )
                HStack {
                    Text("可用 \(Format.bytes(snapshot.memory.available))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("压缩 / 活动内存等详细数据由系统管理")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
            }
        }
    }

    private func memoryColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .blue
        case ..<0.85: return .orange
        default: return .red
        }
    }

    // MARK: - 网络面板

    private func networkPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "网络活动", subtitle: "最近 60 秒") {
            HStack(spacing: 24) {
                ChartLegendValue(
                    title: "下载",
                    value: Format.rate(snapshot.network.downloadRate),
                    color: .blue
                )
                ChartLegendValue(
                    title: "上传",
                    value: Format.rate(snapshot.network.uploadRate),
                    color: .green
                )
                Spacer(minLength: 0)
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
                height: 160
            )
            Text("速率单位：MB/s · 累计下载 \(Format.bytes(snapshot.network.downloadTotal)) · 累计上传 \(Format.bytes(snapshot.network.uploadTotal))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 磁盘面板

    private func diskPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "磁盘", subtitle: "当前") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.bytes(snapshot.disk.used))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已用 · \(Format.percent(snapshot.disk.usedFraction * 100))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("共 \(Format.bytes(snapshot.disk.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                PercentBar(
                    fraction: snapshot.disk.usedFraction,
                    color: diskColor(snapshot.disk.usedFraction)
                )
                HStack(spacing: 20) {
                    Label("读 \(Format.rate(snapshot.disk.readRate))", systemImage: "arrow.down")
                    Label("写 \(Format.rate(snapshot.disk.writeRate))", systemImage: "arrow.up")
                    Spacer()
                    Text("可用 \(Format.bytes(snapshot.disk.available))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func diskColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.7: return .blue
        case ..<0.9: return .orange
        default: return .red
        }
    }

    // MARK: - 电池面板

    private func batteryPanel(_ snapshot: SystemSnapshot) -> some View {
        InfoPanel(title: "电池", subtitle: batterySubtitle(snapshot.battery)) {
            if let percent = snapshot.battery.percent {
                HStack(spacing: 20) {
                    batteryGauge(
                        title: "当前电量",
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
                        title: "循环次数",
                        systemImage: "arrow.triangle.2.circlepath",
                        value: nil,
                        valueText: snapshot.battery.cycleCount.map(String.init) ?? "—",
                        tint: .secondary
                    )
                    Spacer(minLength: 0)
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
                    batteryDetailRow("电流", systemImage: "bolt.badge.a",
                        value: snapshot.battery.amperageMilliamps.map { "\($0) mA" } ?? "—")
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
        VStack(spacing: 6) {
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
            .scaleEffect(1.1)
            .frame(width: 96, height: 88)

            Text(title)
                .font(.subheadline.weight(.semibold))
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
        .frame(minHeight: 34)
    }
}
