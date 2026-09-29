import CoreWLAN
import Foundation
import SystemConfiguration

/// 当前主用网络连接的解析：默认路由出口 → Wi-Fi / 有线 / 其他
///
/// 注意（macOS 14+）：系统在未授予「定位服务」权限时会对 Wi-Fi SSID 打码，
/// `CWWiFiClient.ssid()` 与系统动态存储中的 `SSID_STR` 都会返回空值。
/// 因此这里在拿不到名称时退化为接口类型名（如「Wi-Fi」），由界面负责提示用户授权。
enum NetworkConnectionService {
    /// 结果缓存时长：SSID 不常变化，避免每秒采样都去询问 CoreWLAN
    private static let cacheInterval: TimeInterval = 5
    private static let lock = NSLock()
    private static var cached: (connection: NetworkConnection, timestamp: TimeInterval)?

    /// 读取当前连接（带缓存；权限或网络变化后可传 `forceRefresh`）
    static func current(forceRefresh: Bool = false) -> NetworkConnection {
        lock.lock()
        if !forceRefresh,
           let cached,
           ProcessInfo.processInfo.systemUptime - cached.timestamp < cacheInterval {
            lock.unlock()
            return cached.connection
        }
        lock.unlock()

        let connection = read()

        lock.lock()
        cached = (connection, ProcessInfo.processInfo.systemUptime)
        lock.unlock()
        return connection
    }

    /// 网络切换、定位授权变化后清空缓存，让下一次采样重新解析
    static func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
    }

    // MARK: - 解析

    private static func read() -> NetworkConnection {
        guard let interfaceName = primaryInterfaceName() else { return .disconnected }
        let interface = interfaceInfo()[interfaceName]
        let type = interface?.type
        let displayName = interface?.displayName

        if type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
            return NetworkConnection(
                kind: .wifi,
                interfaceName: interfaceName,
                networkName: wifiSSID(interfaceName: interfaceName),
                interfaceDisplayName: displayName
            )
        }
        if type == (kSCNetworkInterfaceTypeEthernet as String) {
            return NetworkConnection(
                kind: .wired,
                interfaceName: interfaceName,
                networkName: nil,
                interfaceDisplayName: displayName
            )
        }
        return NetworkConnection(
            kind: .other,
            interfaceName: interfaceName,
            networkName: nil,
            interfaceDisplayName: displayName
        )
    }

    /// 默认路由出口接口（如 en0）；无默认路由时返回 nil
    private static func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "OmniViewNetworkConnection" as CFString, nil, nil),
              let state = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString)
                as? [String: Any]
        else {
            return nil
        }
        return state["PrimaryInterface"] as? String
    }

    /// 接口名 → 接口类型 / 系统本地化名称
    private static func interfaceInfo() -> [String: (type: String?, displayName: String?)] {
        var result: [String: (type: String?, displayName: String?)] = [:]
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        for interface in interfaces {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            result[bsdName] = (
                type: SCNetworkInterfaceGetInterfaceType(interface) as String?,
                displayName: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            )
        }
        return result
    }

    /// 当前 SSID；未授予定位权限时系统会返回空值 → nil
    private static func wifiSSID(interfaceName: String) -> String? {
        if let interface = CWWiFiClient.shared().interfaces()?
            .first(where: { $0.interfaceName == interfaceName }),
           let ssid = interface.ssid(),
           !ssid.isEmpty {
            return ssid
        }
        // 退化路径：系统动态存储（同样受定位权限限制）中的 SSID_STR
        guard let store = SCDynamicStoreCreate(nil, "OmniViewWiFiSSID" as CFString, nil, nil),
              let state = SCDynamicStoreCopyValue(
                  store, "State:/Network/Interface/\(interfaceName)/AirPort" as CFString
              ) as? [String: Any]
        else {
            return nil
        }
        for key in ["SSID_STR", "SSID"] {
            if let value = state[key] as? String, !value.isEmpty {
                return value
            }
            if let data = state[key] as? Data,
               let decoded = String(data: data, encoding: .utf8),
               !decoded.isEmpty,
               decoded.utf8.count > 1 {
                return decoded
            }
        }
        return nil
    }
}
