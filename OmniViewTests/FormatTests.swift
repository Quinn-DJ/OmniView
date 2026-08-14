import XCTest
@testable import OmniView

final class FormatTests: XCTestCase {

    func testBytes() {
        // 与 ByteCountFormatter(.file) 的输出保持一致
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        XCTAssertEqual(Format.bytes(0), formatter.string(fromByteCount: 0))
        XCTAssertEqual(Format.bytes(1_048_576), formatter.string(fromByteCount: 1_048_576))
        XCTAssertEqual(Format.bytes(1_073_741_824), formatter.string(fromByteCount: 1_073_741_824))
        // 语义检查：不同量级应包含对应单位
        XCTAssertTrue(Format.bytes(1_000).contains("KB"))
        XCTAssertTrue(Format.bytes(1_000_000).contains("MB"))
        XCTAssertTrue(Format.bytes(1_000_000_000).contains("GB"))
    }

    func testRate() {
        XCTAssertEqual(Format.rate(-1), "—")
        XCTAssertTrue(Format.rate(0).hasSuffix("/s"))
        XCTAssertTrue(Format.rate(5_242_880).contains("MB"))
    }

    func testPercent() {
        XCTAssertEqual(Format.percent(42), "42%")
        XCTAssertEqual(Format.percent(42.5, fractionDigits: 1), "42.5%")
    }

    func testWatts() {
        XCTAssertEqual(Format.watts(12.345), "12.3 W")
        XCTAssertEqual(Format.watts(nil), "—")
    }

    func testCelsius() {
        XCTAssertEqual(Format.celsius(36.5), "36.5°C")
        XCTAssertEqual(Format.celsius(nil), "—")
    }

    func testRPM() {
        XCTAssertEqual(Format.rpm(1500), "1500 RPM")
        XCTAssertEqual(Format.rpm(nil), "—")
    }

    func testTime() {
        XCTAssertEqual(Format.time(90), "1分钟")
        XCTAssertEqual(Format.time(7_200), "2小时 0分钟")
        XCTAssertEqual(Format.time(172_800), "2天 0小时")
    }
}
