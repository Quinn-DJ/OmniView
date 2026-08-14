import Darwin
import Foundation

/// 温度读取器：通过私有 IOHIDEventSystemClient API 读取 Apple Silicon 温度传感器
/// 移植自 mac-scope (https://github.com/shenmuoso/mac-scope)
private typealias HIDClientCreate = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
private typealias HIDClientSetMatching =
    @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void
private typealias HIDClientCopyServices =
    @convention(c) (UnsafeMutableRawPointer?) -> UnsafeRawPointer?
private typealias HIDServiceCopyProperty =
    @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?) -> UnsafeRawPointer?
private typealias HIDServiceCopyEvent =
    @convention(c) (UnsafeRawPointer?, Int64, Int32, Int64) -> UnsafeRawPointer?
private typealias HIDEventGetFloatValue = @convention(c) (UnsafeRawPointer?, Int64) -> Double

enum TemperatureReader {
    static func read() -> TemperatureUsage {
        #if arch(arm64)
            let framework = "/System/Library/Frameworks/IOKit.framework/IOKit"
            guard let handle = dlopen(framework, RTLD_LAZY | RTLD_LOCAL) else {
                return .unavailable
            }
            defer { dlclose(handle) }

            guard
                let create = loadSymbol(handle, "IOHIDEventSystemClientCreate", as: HIDClientCreate.self),
                let setMatching = loadSymbol(
                    handle, "IOHIDEventSystemClientSetMatching", as: HIDClientSetMatching.self
                ),
                let copyServices = loadSymbol(
                    handle, "IOHIDEventSystemClientCopyServices", as: HIDClientCopyServices.self
                ),
                let copyProperty = loadSymbol(
                    handle, "IOHIDServiceClientCopyProperty", as: HIDServiceCopyProperty.self
                ),
                let copyEvent = loadSymbol(
                    handle, "IOHIDServiceClientCopyEvent", as: HIDServiceCopyEvent.self
                ),
                let getFloatValue = loadSymbol(
                    handle, "IOHIDEventGetFloatValue", as: HIDEventGetFloatValue.self
                )
            else {
                return .unavailable
            }

            let matching: NSDictionary = [
                "PrimaryUsagePage": NSNumber(value: 0xFF00),
                "PrimaryUsage": NSNumber(value: 0x0005),
            ]
            guard let system = create(nil) else { return .unavailable }
            defer { Unmanaged<CFTypeRef>.fromOpaque(system).release() }
            setMatching(system, Unmanaged.passUnretained(matching).toOpaque())

            guard let servicesPointer = copyServices(system) else { return .unavailable }
            let services = Unmanaged<CFArray>.fromOpaque(servicesPointer).takeRetainedValue()
            let productKey: NSString = "Product"
            let productKeyPointer = Unmanaged.passUnretained(productKey).toOpaque()
            var sensors: [(String, Double)] = []

            for index in 0..<CFArrayGetCount(services) {
                guard let service = CFArrayGetValueAtIndex(services, index) else { continue }
                let name: String
                if let namePointer = copyProperty(service, productKeyPointer) {
                    let property = Unmanaged<CFTypeRef>.fromOpaque(namePointer).takeRetainedValue()
                    name = property as? String ?? "Unknown sensor"
                } else {
                    name = "Unknown sensor"
                }

                let temperatureEvent: Int64 = 15
                guard let event = copyEvent(service, temperatureEvent, 0, 0) else { continue }
                let value = getFloatValue(event, temperatureEvent << 16)
                Unmanaged<CFTypeRef>.fromOpaque(event).release()
                if value > 0, value <= 150 {
                    sensors.append((name, value))
                }
            }

            return summarize(sensors)
        #else
            return .unavailable
        #endif
    }

    private static func summarize(_ sensors: [(String, Double)]) -> TemperatureUsage {
        var soc = sensors.filter { $0.0.localizedCaseInsensitiveContains("tdie") }.map(\.1)
        let battery = sensors.filter { $0.0.localizedCaseInsensitiveContains("battery") }.map(\.1)
        let storage = sensors.filter { $0.0.localizedCaseInsensitiveContains("nand") }.map(\.1)
        if soc.isEmpty {
            soc = sensors.filter { sensor in
                let name = sensor.0.lowercased()
                return !name.contains("battery") && !name.contains("nand") && !name.contains("tcal")
            }.map(\.1)
        }
        let socTemperature = soc.max()
        let status: ThermalStatus
        switch socTemperature {
        case .some(let value) where value >= 95:
            status = .hot
        case .some(let value) where value >= 80:
            status = .warm
        case .some:
            status = .normal
        case .none:
            status = .unavailable
        }
        return TemperatureUsage(
            socCelsius: socTemperature,
            batteryCelsius: battery.isEmpty ? nil : battery.reduce(0, +) / Double(battery.count),
            storageCelsius: storage.max(),
            status: status
        )
    }

    private static func loadSymbol<T>(
        _ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type
    ) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
}
