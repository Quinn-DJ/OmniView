import Foundation
import IOKit

/// 电池信息读取：IORegistry AppleSmartBattery
enum BatteryInfoService {
    static func read() -> BatteryUsage {
        let unavailable = BatteryUsage(
            currentCapacity: nil, maxCapacity: nil, isCharging: false,
            isExternalConnected: nil, voltageMillivolts: nil, amperageMilliamps: nil,
            cycleCount: nil, healthPercent: nil
        )
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return unavailable }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return unavailable }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service, &unmanagedProperties, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS,
            let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
        else {
            return unavailable
        }

        func int(_ key: String) -> Int? {
            (properties[key] as? NSNumber)?.intValue
        }
        let current = int("CurrentCapacity") ?? int("AppleRawCurrentCapacity")
        let maxCapacity = int("MaxCapacity") ?? int("AppleRawMaxCapacity")
        let designCapacity = int("DesignCapacity")
        let cycleCount = int("CycleCount")
        let voltage = int("Voltage")
        let amperage = int("InstantAmperage") ?? int("Amperage")
        let isCharging = (properties["IsCharging"] as? NSNumber)?.boolValue ?? false
        let externalConnected = (properties["ExternalConnected"] as? NSNumber)?.boolValue
            ?? (properties["AppleRawExternalConnected"] as? NSNumber)?.boolValue
        let health: Int? = {
            guard let maxCapacity, let designCapacity, designCapacity > 0 else { return nil }
            return Int(Double(maxCapacity) / Double(designCapacity) * 100)
        }()

        return BatteryUsage(
            currentCapacity: current, maxCapacity: maxCapacity, isCharging: isCharging,
            isExternalConnected: externalConnected, voltageMillivolts: voltage,
            amperageMilliamps: amperage, cycleCount: cycleCount, healthPercent: health
        )
    }
}
