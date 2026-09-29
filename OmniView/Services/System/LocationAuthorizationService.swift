import CoreLocation
import Foundation

/// 定位授权管理：macOS 14+ 只有拿到「定位服务」授权，系统才会返回 Wi-Fi 名称（SSID）
@MainActor
final class LocationAuthorizationService: NSObject, ObservableObject {
    static let shared = LocationAuthorizationService()

    @Published private(set) var status: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override private init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        status == .authorizedAlways || status == .authorized
    }

    /// 仅在用户尚未表态时弹出系统授权对话框（已拒绝则不再打扰）
    func requestIfNeeded() {
        guard status == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }
}

extension LocationAuthorizationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.status = status
            // 授权状态变化后丢掉 SSID 缓存，下一次采样即可拿到网络名称
            NetworkConnectionService.invalidate()
        }
    }
}
