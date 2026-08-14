import Foundation

// MARK: - 系统监控模型

struct CPUSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let total: Double   // 0-100
    let user: Double
    let system: Double
}

struct MemoryUsage {
    let used: UInt64
    let available: UInt64
    let total: UInt64

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct DiskUsage {
    let used: UInt64
    let available: UInt64
    let total: UInt64
    let readRate: Double   // bytes/s
    let writeRate: Double

    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct NetworkUsage {
    let timestamp: Date
    let downloadRate: Double  // bytes/s
    let uploadRate: Double
    let downloadTotal: UInt64
    let uploadTotal: UInt64
}

struct PowerUsage {
    let timestamp: Date = .now
    let systemWatts: Double?
    let chargingWatts: Double?
    let adapterInputWatts: Double?
    let hasBattery: Bool
    let isExternalPowerConnected: Bool?
    let isCharging: Bool

    static let unavailable = PowerUsage(
        systemWatts: nil, chargingWatts: nil, adapterInputWatts: nil,
        hasBattery: false, isExternalPowerConnected: nil, isCharging: false
    )
}

struct FanReading: Identifiable {
    let id: Int
    let name: String
    let currentRPM: Double
    let minimumRPM: Double?
    let maximumRPM: Double?
    let targetRPM: Double?
}

enum CoolingState {
    case available
    case fanless
    case unavailable
}

struct CoolingUsage {
    let timestamp: Date = .now
    let state: CoolingState
    let fans: [FanReading]

    static let unavailable = CoolingUsage(state: .unavailable, fans: [])
}

enum ThermalStatus {
    case normal, warm, hot, unavailable
}

struct TemperatureUsage {
    let timestamp: Date = .now
    let socCelsius: Double?
    let batteryCelsius: Double?
    let storageCelsius: Double?
    let status: ThermalStatus

    static let unavailable = TemperatureUsage(
        socCelsius: nil, batteryCelsius: nil, storageCelsius: nil, status: .unavailable
    )
}

struct BatteryUsage {
    let currentCapacity: Int?
    let maxCapacity: Int?
    let isCharging: Bool
    let isExternalConnected: Bool?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
    let cycleCount: Int?
    let healthPercent: Int?

    var percent: Double? {
        guard let currentCapacity, let maxCapacity, maxCapacity > 0 else { return nil }
        return Double(currentCapacity) / Double(maxCapacity) * 100
    }
}

struct SystemSnapshot {
    let timestamp: Date
    let cpu: CPUSample
    let memory: MemoryUsage
    let disk: DiskUsage
    let network: NetworkUsage
    let power: PowerUsage
    let temperature: TemperatureUsage
    let cooling: CoolingUsage
    let battery: BatteryUsage
    let uptime: TimeInterval
}

// MARK: - 硬件信息

enum HardwareThermalState: String {
    case nominal = "正常"
    case fair = "偏高"
    case serious = "较高"
    case critical = "严重"
    case unknown = "不可用"
}

struct HardwareDisplayInfo: Identifiable {
    let id: String
    let name: String
    let resolution: String        // 逻辑分辨率
    let pixelResolution: String   // 物理像素分辨率
    let isBuiltIn: Bool
    let isMain: Bool
}

struct HardwareUSBDevice: Identifiable {
    let id: String
    let name: String
    let manufacturer: String
    let speed: String
    let productID: String
    let vendorID: String
}

struct HardwareBluetoothDevice: Identifiable {
    let id: String
    let name: String
    let type: String
    let signal: Int?
}

struct HardwareBluetoothInfo {
    let isAvailable: Bool
    let isPoweredOn: Bool
    let chipset: String
    let connectedDevices: [HardwareBluetoothDevice]

    static let unavailable = HardwareBluetoothInfo(
        isAvailable: false, isPoweredOn: false, chipset: "—", connectedDevices: []
    )
}

struct HardwareWiFiInfo {
    let isAvailable: Bool
    let isPoweredOn: Bool
    let interfaceName: String
    let ssid: String?
    let signalDBm: Int?
    let transmitRateMbps: Double?
    let channel: Int?

    static let unavailable = HardwareWiFiInfo(
        isAvailable: false, isPoweredOn: false, interfaceName: "—",
        ssid: nil, signalDBm: nil, transmitRateMbps: nil, channel: nil
    )
}

struct HardwareInfo {
    let modelName: String          // e.g. "MacBook Pro"
    let modelIdentifier: String    // e.g. "MacBookPro18,3"
    let chip: String               // e.g. "Apple M1 Pro"
    let architecture: String       // e.g. "arm64"
    let physicalCores: Int
    let logicalCores: Int
    let performanceCores: Int?
    let efficiencyCores: Int?
    let memoryBytes: UInt64
    let macOSVersion: String
    let macOSBuild: String
    let serialNumber: String
    let bootVolumeName: String?
    let storageTotal: UInt64
    let storageAvailable: UInt64
    let graphics: String
    let kernelVersion: String
    let systemUptime: TimeInterval
    let thermalState: HardwareThermalState
    let displays: [HardwareDisplayInfo]
    let usbDevices: [HardwareUSBDevice]
    let bluetooth: HardwareBluetoothInfo
    let wifi: HardwareWiFiInfo

    var coreSummary: String {
        var summary = "\(physicalCores) 物理 · \(logicalCores) 逻辑"
        if let performance = performanceCores, let efficiency = efficiencyCores {
            summary += " · \(performance) 性能 · \(efficiency) 能效"
        }
        return summary
    }
}

// MARK: - 格式辅助

enum Format {
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 0 { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        let value = formatter.string(fromByteCount: Int64(bytesPerSecond))
        return "\(value)/s"
    }

    static func percent(_ value: Double, fractionDigits: Int = 0) -> String {
        String(format: "%.\(fractionDigits)f%%", value)
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f W", value)
    }

    static func rpm(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f RPM", value)
    }

    static func celsius(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f°C", value)
    }

    static func time(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86_400
        let hours = (Int(interval) % 86_400) / 3_600
        let minutes = (Int(interval) % 3_600) / 60
        if days > 0 { return "\(days)天 \(hours)小时" }
        if hours > 0 { return "\(hours)小时 \(minutes)分钟" }
        return "\(minutes)分钟"
    }
}
