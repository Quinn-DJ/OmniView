import Darwin
import Foundation
import IOKit

/// 硬件与系统信息读取：sysctl + IORegistry
enum HardwareInfoService {
    static func read() -> HardwareInfo {
        let modelIdentifier = sysctlString("hw.model") ?? "Unknown"
        let chip = sysctlString("machdep.cpu.brand_string")
            ?? sysctlString("hw.machine")
            ?? "Unknown"
        let cores = sysctlInt("hw.ncpu") ?? 0
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
            cpuCores: cores,
            memoryBytes: memory,
            macOSVersion: version,
            macOSBuild: build,
            serialNumber: serial,
            bootVolumeName: bootVolume,
            storageTotal: capacity.total,
            storageAvailable: capacity.available,
            graphics: graphics,
            kernelVersion: kernel,
            systemUptime: uptime
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
