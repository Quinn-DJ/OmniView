import XCTest
@testable import OmniView

final class NetworkConnectionTests: XCTestCase {

    func testWiFiWithSSIDUsesNetworkName() {
        let connection = NetworkConnection(
            kind: .wifi,
            interfaceName: "en0",
            networkName: "ZJUWLAN-Secure",
            interfaceDisplayName: "Wi-Fi"
        )
        XCTAssertEqual(connection.label, "ZJUWLAN-Secure")
        XCTAssertEqual(connection.symbolName, "wifi")
        XCTAssertTrue(connection.helpText.contains("ZJUWLAN-Secure"))
        XCTAssertTrue(connection.helpText.contains("en0"))
    }

    /// 未授予定位权限时系统不返回 SSID，退化为接口名，并提示授权方法
    func testWiFiWithoutSSIDFallsBackAndHintsPermission() {
        let connection = NetworkConnection(
            kind: .wifi,
            interfaceName: "en0",
            networkName: nil,
            interfaceDisplayName: "Wi-Fi"
        )
        XCTAssertEqual(connection.label, "Wi-Fi")
        XCTAssertTrue(connection.helpText.contains("定位服务"))
    }

    func testWiredConnectionLabel() {
        let connection = NetworkConnection(
            kind: .wired,
            interfaceName: "en3",
            networkName: nil,
            interfaceDisplayName: "USB 10/100/1000 LAN"
        )
        XCTAssertEqual(connection.label, "有线连接")
        XCTAssertEqual(connection.symbolName, "cable.connector")
        XCTAssertTrue(connection.helpText.contains("en3"))
    }

    func testDisconnectedLabel() {
        XCTAssertEqual(NetworkConnection.disconnected.label, "未连接")
    }
}
