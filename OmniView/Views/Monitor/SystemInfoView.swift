import AppKit
import SwiftUI

/// 系统信息视图
/// 布局与内容丰富度参考 mac-scope 的「系统信息」页：
/// 设备头部 + 分组表单（Mac / 处理器与内存 / 存储 / 电池 / 显示器 / USB / 蓝牙 / Wi-Fi）
struct SystemInfoView: View {
    @EnvironmentObject private var viewModel: SystemMonitorViewModel
    @State private var battery: BatteryUsage?
    @State private var batteryTemperature: Double?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let hardware = viewModel.hardware {
                    deviceHeader(hardware)
                    hardwareList(hardware)
                } else {
                    ProgressView("正在读取系统信息…")
                        .frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .navigationTitle("系统信息")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: copySummary) {
                    Label("复制摘要", systemImage: "doc.on.doc")
                }
                .help("复制摘要")
                .disabled(viewModel.hardware == nil)

                Button(action: refreshAll) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新")
            }
        }
        .task {
            loadBattery()
        }
    }

    private func refreshAll() {
        viewModel.refreshHardware()
        loadBattery()
    }

    private func loadBattery() {
        battery = BatteryInfoService.read()
        batteryTemperature = TemperatureReader.read().batteryCelsius
    }

    // MARK: - 设备头部

    private func deviceHeader(_ hardware: HardwareInfo) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "macbook")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 210, height: 120)
                .accessibilityHidden(true)

            Text(hardware.modelName)
                .font(.title2.weight(.semibold))

            Text("\(hardware.chip) · \(Format.bytes(hardware.memoryBytes))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 分组列表

    private func hardwareList(_ hardware: HardwareInfo) -> some View {
        Form {
            Section("Mac") {
                infoRow("型号", value: hardware.modelName, systemImage: "laptopcomputer")
                infoRow("型号标识符", value: hardware.modelIdentifier, systemImage: "number")
                infoRow("macOS", value: "\(hardware.macOSVersion) (\(hardware.macOSBuild))", systemImage: "apple.logo")
                infoRow("内核", value: hardware.kernelVersion, systemImage: "terminal")
                infoRow("运行时间", value: Format.time(hardware.systemUptime), systemImage: "clock")
                statusRow(
                    "热状态",
                    value: hardware.thermalState.rawValue,
                    systemImage: "thermometer.medium",
                    color: thermalColor(hardware.thermalState)
                )
            }

            Section("处理器与内存") {
                infoRow("芯片", value: hardware.chip, systemImage: "cpu")
                infoRow("架构", value: hardware.architecture, systemImage: "terminal")
                infoRow("CPU 核心", value: hardware.coreSummary, systemImage: "circle.grid.3x3")
                infoRow("内存", value: Format.bytes(hardware.memoryBytes), systemImage: "memorychip")
                infoRow("图形处理器", value: hardware.graphics, systemImage: "gpu")
            }

            Section("存储") {
                infoRow("总容量", value: Format.bytes(hardware.storageTotal), systemImage: "internaldrive")
                infoRow("可用空间", value: Format.bytes(hardware.storageAvailable), systemImage: "internaldrive.fill")
                infoRow("启动磁盘", value: hardware.bootVolumeName ?? "—", systemImage: "folder")
                infoRow("序列号", value: hardware.serialNumber, systemImage: "number.square")
            }

            Section("电池") {
                if let battery {
                    batteryRows(battery)
                } else {
                    unavailableRow("未检测到电池。")
                }
            }

            Section("显示器") {
                if hardware.displays.isEmpty {
                    unavailableRow("未获取到显示器信息。")
                } else {
                    ForEach(hardware.displays) { display in
                        HStack(spacing: 12) {
                            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(display.name)
                                    if display.isMain {
                                        Text("主显示器")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if display.isBuiltIn {
                                        Text("内建")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text("\(display.resolution) · \(display.pixelResolution)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("USB") {
                if hardware.usbDevices.isEmpty {
                    unavailableRow("当前未检测到 USB 设备。")
                } else {
                    ForEach(hardware.usbDevices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: "cable.connector")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(usbDetail(device))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("蓝牙") {
                statusRow(
                    "状态",
                    value: connectionStatus(
                        isAvailable: hardware.bluetooth.isAvailable,
                        isPoweredOn: hardware.bluetooth.isPoweredOn
                    ),
                    systemImage: "wave.3.right",
                    color: hardware.bluetooth.isPoweredOn ? .green : .secondary
                )
                if hardware.bluetooth.isAvailable {
                    infoRow("控制器", value: hardware.bluetooth.chipset, systemImage: "dot.radiowaves.left.and.right")
                }
                if hardware.bluetooth.connectedDevices.isEmpty {
                    unavailableRow("当前没有已连接的蓝牙设备。")
                } else {
                    ForEach(hardware.bluetooth.connectedDevices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: "headphones")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(bluetoothDetail(device))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Wi-Fi") {
                statusRow(
                    "状态",
                    value: connectionStatus(
                        isAvailable: hardware.wifi.isAvailable,
                        isPoweredOn: hardware.wifi.isPoweredOn
                    ),
                    systemImage: "wifi",
                    color: hardware.wifi.isPoweredOn ? .green : .secondary
                )
                if hardware.wifi.isAvailable {
                    infoRow("接口", value: hardware.wifi.interfaceName, systemImage: "network")
                    infoRow("网络", value: hardware.wifi.ssid ?? "不可用", systemImage: "wifi")
                    if let signal = hardware.wifi.signalDBm {
                        infoRow("信号强度", value: "\(signal) dBm", systemImage: "chart.bar")
                    }
                    if let rate = hardware.wifi.transmitRateMbps {
                        infoRow("传输速率", value: String(format: "%.0f Mbps", rate), systemImage: "arrow.up.arrow.down")
                    }
                    if let channel = hardware.wifi.channel {
                        infoRow("频道", value: String(channel), systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 电池

    @ViewBuilder
    private func batteryRows(_ battery: BatteryUsage) -> some View {
        statusRow(
            "电源来源",
            value: battery.isExternalConnected == true ? "电源适配器" : "电池",
            systemImage: "powerplug",
            color: battery.isExternalConnected == true ? .green : .secondary
        )
        statusRow(
            "充电状态",
            value: battery.isCharging ? "正在充电" : "未充电",
            systemImage: "bolt",
            color: battery.isCharging ? .green : .secondary
        )
        if let percent = battery.percent {
            infoRow("当前电量", value: String(format: "%.0f%%", percent), systemImage: "battery.75percent")
        }
        if let health = battery.healthPercent {
            infoRow("最大容量（健康度）", value: "\(health)%", systemImage: "heart.text.square")
        }
        if let cycles = battery.cycleCount {
            infoRow("循环次数", value: String(cycles), systemImage: "arrow.triangle.2.circlepath")
        }
        if let voltage = battery.voltageMillivolts {
            infoRow("电压", value: String(format: "%.2f V", Double(voltage) / 1_000), systemImage: "waveform.path")
        }
        if let amperage = battery.amperageMilliamps {
            infoRow("电流", value: "\(amperage) mA", systemImage: "bolt.badge.a")
        }
        infoRow("温度", value: Format.celsius(batteryTemperature), systemImage: "thermometer.medium")
    }

    // MARK: - 行组件

    private func infoRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func statusRow(_ title: String, value: String, systemImage: String, color: Color) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(color)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func unavailableRow(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    // MARK: - 辅助

    private func thermalColor(_ state: HardwareThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }

    private func connectionStatus(isAvailable: Bool, isPoweredOn: Bool) -> String {
        guard isAvailable else { return "不可用" }
        return isPoweredOn ? "已开启" : "已关闭"
    }

    private func usbDetail(_ device: HardwareUSBDevice) -> String {
        [device.manufacturer, device.speed, device.productID, device.vendorID]
            .filter { $0 != "-" && $0 != "—" }
            .joined(separator: " · ")
    }

    private func bluetoothDetail(_ device: HardwareBluetoothDevice) -> String {
        var values = device.type == "—" ? [] : [device.type]
        if let signal = device.signal {
            values.append("\(signal) dBm")
        }
        return values.isEmpty ? "已连接" : values.joined(separator: " · ")
    }

    private func copySummary() {
        guard let hardware = viewModel.hardware else { return }
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let lines = [
            "OmniView \(appVersion)",
            "型号：\(hardware.modelName) (\(hardware.modelIdentifier))",
            "芯片：\(hardware.chip)",
            "CPU 核心：\(hardware.coreSummary)",
            "内存：\(Format.bytes(hardware.memoryBytes))",
            "macOS：\(hardware.macOSVersion) (\(hardware.macOSBuild))",
            "显示器：\(hardware.displays.map(\.name).joined(separator: ", "))",
            "Wi-Fi：\(hardware.wifi.isPoweredOn ? "已开启" : "已关闭")",
            "蓝牙：\(hardware.bluetooth.isPoweredOn ? "已开启" : "已关闭")",
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - Previews

#Preview("系统信息") {
    let viewModel = SystemMonitorViewModel()
    return SystemInfoView()
        .environmentObject(viewModel)
        .frame(width: 900, height: 800)
        .task { viewModel.refreshHardware() }
}
