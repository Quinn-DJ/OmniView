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
    let state: CoolingState
    let fans: [FanReading]

    static let unavailable = CoolingUsage(state: .unavailable, fans: [])
}

enum ThermalStatus {
    case normal, warm, hot, unavailable
}

struct TemperatureUsage {
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

struct HardwareInfo {
    let modelName: String          // e.g. "MacBook Pro"
    let modelIdentifier: String    // e.g. "MacBookPro18,3"
    let chip: String               // e.g. "Apple M1 Pro"
    let cpuCores: Int
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
