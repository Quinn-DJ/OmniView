import AppKit
import CoreGraphics
import CoreWLAN
import Darwin
import Foundation
import IOKit
import IOBluetooth

/// 硬件与系统信息读取：sysctl + IORegistry + NSScreen + CoreWLAN + IOBluetooth
/// 参考 mac-scope (https://github.com/shenmuoso/mac-scope) 的 HardwareInfoService
@MainActor
enum HardwareInfoService {
    static func read() -> HardwareInfo {
        let modelIdentifier = sysctlString("hw.model") ?? "Unknown"
        let chip = sysctlString("machdep.cpu.brand_string")
            ?? sysctlString("hw.machine")
            ?? "Unknown"
        let architecture = sysctlString("hw.machine") ?? "Unknown"
        let logicalCores = sysctlInt("hw.logicalcpu") ?? 0
        let physicalCores = sysctlInt("hw.physicalcpu") ?? logicalCores
        let memory = UInt64(sysctlInt64("hw.memsize") ?? 0)
        let version = sysctlString("kern.osproductversion") ?? "Unknown"
        let build = sysctlString("kern.osversion") ?? "Unknown"
        let kernel = sysctlString("kern.osrelease") ?? "Unknown"
        let uptime = ProcessInfo.processInfo.systemUptime
        let serial = ioSerialNumber()
        let graphics = readGraphics()
        let bootVolume = readBootVolumeName()
        let capacity = diskCapacity()

        return HardwareInfo(
            modelName: modelDisplayName(modelIdentifier),
            modelIdentifier: modelIdentifier,
            chip: chip,
            architecture: architecture,
            physicalCores: physicalCores,
            logicalCores: logicalCores,
            performanceCores: perfCores(level: 0),
            efficiencyCores: perfCores(level: 1),
            memoryBytes: memory,
            macOSVersion: version,
            macOSBuild: build,
            serialNumber: serial,
            bootVolumeName: bootVolume,
            storageTotal: capacity.total,
            storageAvailable: capacity.available,
            graphics: graphics,
            kernelVersion: kernel,
            systemUptime: uptime,
            thermalState: thermalState,
            displays: readDisplays(),
            usbDevices: readUSBDevices(),
            bluetooth: readBluetooth(),
            wifi: readWiFi()
        )
    }

    // MARK: - sysctl

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func sysctlInt64(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    /// Apple Silicon 性能/能效核数量（perflevel0 = 性能，perflevel1 = 能效）
    private static func perfCores(level: Int) -> Int? {
        guard let value = sysctlInt("hw.perflevel\(level).logicalcpu"), value > 0 else {
            return nil
        }
        return value
    }

    // MARK: - 热状态

    private static var thermalState: HardwareThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }

    // MARK: - IORegistry

    private static func ioSerialNumber() -> String {
        guard let matching = IOServiceMatching("IOPlatformExpertDevice") else { return "—" }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return "—" }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(
            service, "IOPlatformSerialNumber" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? String
        return value?.isEmpty == false ? value! : "—"
    }

    private static func readGraphics() -> String {
        guard let matching = IOServiceMatching("IOGPU") else { return "—" }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return "—" }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(
            service, "model" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Data
        guard let data = value else { return "—" }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
            ?? "—"
    }

    private static func readBootVolumeName() -> String? {
        let url = URL(fileURLWithPath: "/")
        var resourceValues: URLResourceValues?
        do {
            resourceValues = try url.resourceValues(forKeys: [.volumeNameKey])
        } catch {
            return nil
        }
        return resourceValues?.volumeName
    }

    private static func diskCapacity() -> (total: UInt64, available: UInt64) {
        var statistics = statvfs()
        guard statvfs("/", &statistics) == 0 else { return (0, 0) }
        let blockSize = UInt64(statistics.f_frsize)
        return (
            UInt64(statistics.f_blocks) * blockSize,
            UInt64(statistics.f_bavail) * blockSize
        )
    }

    // MARK: - 显示器

    private static func readDisplays() -> [HardwareDisplayInfo] {
        NSScreen.screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = CGDirectDisplayID(number?.uint32Value ?? 0)
            let isBuiltIn = displayID != 0 && CGDisplayIsBuiltin(displayID) != 0
            let isMain = (screen === NSScreen.main)
            let size = screen.frame.size
            let scale = screen.backingScaleFactor
            return HardwareDisplayInfo(
                id: "\(displayID)",
                name: screen.localizedName,
                resolution: "\(Int(size.width)) × \(Int(size.height))",
                pixelResolution: "\(Int(size.width * scale)) × \(Int(size.height * scale)) 像素",
                isBuiltIn: isBuiltIn,
                isMain: isMain
            )
        }
    }

    // MARK: - USB

    private static func readUSBDevices() -> [HardwareUSBDevice] {
        var devices: [HardwareUSBDevice] = []
        for serviceClass in ["IOUSBHostDevice", "IOUSBDevice"] {
            guard let matching = IOServiceMatching(serviceClass) else { continue }
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
                == KERN_SUCCESS
            else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer { IOObjectRelease(service) }
                if let properties = ioProperties(of: service) {
                    if let device = usbDevice(from: properties) {
                        devices.append(device)
                    }
                }
                service = IOIteratorNext(iterator)
            }
        }
        // 去重（IOUSBHostDevice 与 IOUSBDevice 可能同时命中同一设备）
        var seen = Set<String>()
        return devices.filter { seen.insert($0.id).inserted }
    }

    private static func ioProperties(of service: io_service_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service, &unmanagedProperties, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS
        else {
            return nil
        }
        return unmanagedProperties?.takeRetainedValue() as? [String: Any]
    }

    private static func usbDevice(from properties: [String: Any]) -> HardwareUSBDevice? {
        func stringProperty(_ key: String) -> String? {
            if let value = properties[key] as? String { return value }
            if let data = properties[key] as? Data {
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .controlCharacters)
            }
            return nil
        }

        let name = stringProperty("USB Product Name")?.trimmingCharacters(in: .whitespaces)
        guard let name, !name.isEmpty, name.lowercased() != "root hub simulation" else {
            return nil
        }
        let vendorID = (properties["USB Vendor ID"] as? NSNumber)?.uint16Value ?? 0
        let productID = (properties["USB Product ID"] as? NSNumber)?.uint16Value ?? 0
        let speed = usbSpeedName((properties["USB Speed"] as? NSNumber)?.intValue)

        return HardwareUSBDevice(
            id: "\(vendorID):\(productID):\(name)",
            name: name,
            manufacturer: stringProperty("USB Vendor Name") ?? "未知厂商",
            speed: speed,
            productID: String(format: "0x%04x", productID),
            vendorID: String(format: "0x%04x", vendorID)
        )
    }

    private static func usbSpeedName(_ raw: Int?) -> String {
        guard let raw else { return "—" }
        switch raw {
        case 1: return "1.5 Mb/s (Low)"
        case 2: return "12 Mb/s (Full)"
        case 3: return "480 Mb/s (High)"
        case 4: return "5 Gb/s (Super)"
        case 5: return "10 Gb/s (Super+)"
        case 6: return "20 Gb/s (Super+ 2x)"
        case 7: return "40 Gb/s (Thunderbolt)"
        default: return "\(raw)"
        }
    }

    // MARK: - 蓝牙

    private static func readBluetooth() -> HardwareBluetoothInfo {
        guard let controller = IOBluetoothHostController.default() else {
            return .unavailable
        }
        let poweredOn = controller.powerState == kBluetoothHCIPowerStateON
        let chipset = controller.nameAsString() ?? "—"

        let devices: [HardwareBluetoothDevice] = (IOBluetoothDevice.pairedDevices()
            as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
            .map { device in
                let rssi = Int(device.rawRSSI())
                return HardwareBluetoothDevice(
                    id: device.addressString ?? UUID().uuidString,
                    name: device.name ?? "未知设备",
                    type: bluetoothTypeName(device.classOfDevice),
                    signal: (rssi > -127 && rssi < 127) ? rssi : nil
                )
            }

        return HardwareBluetoothInfo(
            isAvailable: true,
            isPoweredOn: poweredOn,
            chipset: chipset,
            connectedDevices: devices
        )
    }

    private static func bluetoothTypeName(_ classOfDevice: BluetoothClassOfDevice) -> String {
        let major = Int((classOfDevice >> 8) & 0x1F)
        switch major {
        case Int(kBluetoothDeviceClassMajorComputer): return "电脑"
        case Int(kBluetoothDeviceClassMajorPhone): return "手机"
        case Int(kBluetoothDeviceClassMajorAudio): return "音频"
        case Int(kBluetoothDeviceClassMajorPeripheral): return "外设"
        case Int(kBluetoothDeviceClassMajorImaging): return "影像"
        case Int(kBluetoothDeviceClassMajorWearable): return "穿戴"
        case Int(kBluetoothDeviceClassMajorToy): return "玩具"
        case Int(kBluetoothDeviceClassMajorHealth): return "健康"
        default: return "其他"
        }
    }

    // MARK: - Wi-Fi

    private static func readWiFi() -> HardwareWiFiInfo {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface(), interface.interfaceName != nil else {
            return .unavailable
        }
        return HardwareWiFiInfo(
            isAvailable: true,
            isPoweredOn: interface.powerOn(),
            interfaceName: interface.interfaceName ?? "—",
            ssid: interface.ssid(),
            signalDBm: interface.rssiValue(),
            transmitRateMbps: interface.transmitRate(),
            channel: interface.wlanChannel()?.channelNumber
        )
    }

    // MARK: - 机型名称

    private static func modelDisplayName(_ identifier: String) -> String {
        // 常用机型映射；未知时直接显示标识符
        let mapping: [String: String] = [
            "MacBookPro18,1": "MacBook Pro 14 英寸 (2021)",
            "MacBookPro18,2": "MacBook Pro 16 英寸 (2021)",
            "MacBookPro18,3": "MacBook Pro 14 英寸 (2021)",
            "MacBookPro18,4": "MacBook Pro 16 英寸 (2021)",
            "MacBookPro14,1": "MacBook Pro (2016)",
            "MacBookPro14,3": "MacBook Pro (2016)",
            "MacBookAir10,1": "MacBook Air (M1, 2020)",
            "MacBookPro17,1": "MacBook Pro 13 英寸 (M1, 2020)",
            "Macmini9,1": "Mac mini (M1, 2020)",
            "iMac21,1": "iMac 24 英寸 (M1, 2021)",
            "MacBookPro19,1": "MacBook Pro 14 英寸 (2023)",
            "MacBookPro19,2": "MacBook Pro 16 英寸 (2023)",
            "MacBookAir7,2": "MacBook Air 13 英寸 (2015)",
        ]
        return mapping[identifier] ?? identifier
    }
}
