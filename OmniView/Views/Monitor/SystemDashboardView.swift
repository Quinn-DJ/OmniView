import SwiftUI

/// 系统监控仪表盘
struct SystemDashboardView: View {
    @EnvironmentObject private var viewModel: SystemMonitorViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = viewModel.snapshot {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        cpuCard(snapshot)
                        memoryCard(snapshot)
                        powerCard(snapshot)
                        temperatureCard(snapshot)
                        fansCard(snapshot)
                        batteryCard(snapshot)
                        networkCard(snapshot)
                        diskCard(snapshot)
                    }
                } else {
                    ProgressView("正在采集系统指标…")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .padding(14)
        }
        .navigationTitle("系统监控")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if viewModel.isSampling {
                        StatusDot(color: .green)
                        Text("实时监控中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - CPU

    private func cpuCard(_ snapshot: SystemSnapshot) -> some View {
        MetricCard(title: "CPU 负载", icon: "cpu") {
            HStack(spacing: 16) {
                RingGauge(
                    value: snapshot.cpu.total / 100,
                    displayValue: String(format: "%.0f", snapshot.cpu.total),
                    unit: "%",
                    color: cpuColor(snapshot.cpu.total)
                )
                VStack(alignment: .leading, spacing: 6) {
                    statRow("用户", String(format: "%.1f%%", snapshot.cpu.user), color: .blue)
                    statRow("系统", String(format: "%.1f%%", snapshot.cpu.system), color: .orange)
                    Text("\(ProcessInfo.processInfo.activeProcessorCount) 核")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MiniLineChart(
                        points: viewModel.cpuHistory.map {
                            MiniLineChart.Point(timestamp: $0.timestamp, value: $0.total)
                        },
                        color: cpuColor(snapshot.cpu.total),
                        baseline: 0
                    )
                }
            }
        }
    }

    private func cpuColor(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return .blue
        case ..<80: return .orange
        default: return .red
        }
    }

    // MARK: - 内存

    private func memoryCard(_ snapshot: SystemSnapshot) -> some View {
        MetricCard(title: "内存", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Format.bytes(snapshot.memory.used))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text(Format.percent(snapshot.memory.usedFraction * 100))
                        .font(.headline)
                        .foregroundStyle(memoryColor(snapshot.memory.usedFraction))
                }
                PercentBar(fraction: snapshot.memory.usedFraction, color: memoryColor(snapshot.memory.usedFraction))
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

    private func memoryColor(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .blue
        case ..<0.85: return .orange
        default: return .red
        }
    }

    // MARK: - 功耗

    private func powerCard(_ snapshot: SystemSnapshot) -> some View {
        MetricCard(title: "功耗", icon: "bolt.fill") {
            let power = snapshot.power
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(power.systemWatts.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("W")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if power.isExternalPowerConnected == true {
                        Label("电源适配器", systemImage: "powerplug.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                HStack {
                    Text("适配器输入")
                    Spacer()
                    Text(Format.watts(power.adapterInputWatts))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if power.hasBattery {
                    HStack {
                        Text(power.isCharging ? "正在充电" : "未充电")
                        Spacer()
                        Text(Format.watts(power.chargingWatts))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                let powerPoints: [MiniLineChart.Point] = viewModel.powerHistory.compactMap { entry in
                    guard let watts = entry.systemWatts else { return nil }
                    return MiniLineChart.Point(timestamp: entry.timestamp, value: watts)
                }
                MiniLineChart(points: powerPoints, color: .green, baseline: 0)
            }
        }
    }

    // MARK: - 温度

    private func temperatureCard(_ snapshot: SystemSnapshot) -> some View {
        MetricCard(title: "温度", icon: "thermometer.medium") {
            let temp = snapshot.temperature
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.celsius(temp.socCelsius))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    switch temp.status {
                    case .normal:
                        Label("正常", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    case .warm:
                        Label("偏高", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    case .hot:
                        Label("过热", systemImage: "flame")
                            .foregroundStyle(.red)
                    case .unavailable:
                        Text("不可用")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                HStack {
                    Text("电池")
                    Spacer()
                    Text(Format.celsius(temp.batteryCelsius))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Text("存储")
                    Spacer()
                    Text(Format.celsius(temp.storageCelsius))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 风扇

    private func fansCard(_ snapshot: SystemSnapshot) -> some View {
        MetricCard(title: "风扇", icon: "fan") {
            let cooling = snapshot.cooling
            switch cooling.state {
            case .fanless:
                Label("无风扇设备", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, minHeight: 60)
            case .unavailable:
                Label("风扇信息不可用", systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            case .available:
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cooling.fans) { fan in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(fan.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Format.rpm(fan.currentRPM))
                                    .font(.system(.body, design: .rounded))
                                    .monospacedDigit()
                            }
                            if let max = fan.maximumRPM, max > 0 {
                                PercentBar(fraction: fan.currentRPM / max, color: .cyan)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 电池

    private func batteryCard(_ snapshot: SystemSnapshot) -> some View {
        MetricCard(title: "电池", icon: "battery.100percent") {
            let battery = snapshot.battery
            if let percent = battery.percent {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(format: "%.0f%%", percent))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Spacer()
                        if battery.isCharging {
                            Label("充电中", systemImage: "bolt.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if battery.isExternalConnected == true {
                            Label("已接电源", systemImage: "powerplug")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    PercentBar(fraction: percent / 100, color: batteryColor(percent))
                    HStack {
                        Text("循环次数")
                        Spacer()
                        Text(battery.cycleCount.map(String.init) ?? "—")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    HStack {
                        Text("电池健康")
                        Spacer()
                        Text(battery.healthPercent.map { "\($0)%" } ?? "—")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Label("未检测到电池", systemImage: "battery.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }

    private func batteryColor(_ percent: Double) -> Color {
        switch percent {
        case ..<20: return .red
        case ..<50: return .orange
        default: return .green
        }
    }

    // MARK: - 网络

    private func networkCard(_ snapshot: SystemSnapshot) -> some View {
        MetricCard(title: "网络", icon: "network") {
            let network = snapshot.network
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("↓ \(Format.rate(network.downloadRate))")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                        Text("↑ \(Format.rate(network.uploadRate))")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("共下载 \(Format.bytes(network.downloadTotal))")
                        Text("共上传 \(Format.bytes(network.uploadTotal))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                MiniLineChart(
                    points: viewModel.networkHistory.map { entry in
                        MiniLineChart.Point(
                            timestamp: entry.timestamp,
                            value: entry.downloadRate / 1_048_576
                        )
                    },
                    color: .blue,
                    baseline: 0
                )
                Text("最近 30 分钟下载速率（MB/s）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 磁盘

    private func diskCard(_ snapshot: SystemSnapshot) -> some View {
        MetricCard(title: "磁盘", icon: "internaldrive") {
            let disk = snapshot.disk
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已用 \(Format.bytes(disk.used))")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Text(Format.percent(disk.usedFraction * 100))
                        .font(.headline)
                        .foregroundStyle(diskColor(disk.usedFraction))
                }
                PercentBar(fraction: disk.usedFraction, color: diskColor(disk.usedFraction))
                HStack {
                    Text("可用 \(Format.bytes(disk.available))")
                    Spacer()
                    Text("共 \(Format.bytes(disk.total))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Label("读 \(Format.rate(disk.readRate))", systemImage: "arrow.down")
                    Label("写 \(Format.rate(disk.writeRate))", systemImage: "arrow.up")
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

    // MARK: - 辅助

    private func statRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            StatusDot(color: color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}
