import XCTest
@testable import OmniView

final class BigUIntTests: XCTestCase {

    func testHexParsingAndRoundtrip() {
        let value = BigUInt(hexString: "deadbeef")
        XCTAssertNotNil(value)
        XCTAssertEqual(value!.hexString, "deadbeef")

        let zero = BigUInt(hexString: "0")
        XCTAssertNotNil(zero)
        XCTAssertTrue(zero!.isZero)
        XCTAssertEqual(zero!.hexString, "0")

        XCTAssertNil(BigUInt(hexString: "zzz"))
        XCTAssertNil(BigUInt(hexString: ""))
    }

    func testByteConstruction() {
        let value = BigUInt(bytes: [0x01, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(value.hexString, "100000000")

        let empty = BigUInt(bytes: [])
        XCTAssertTrue(empty.isZero)
    }

    func testComparison() {
        XCTAssertLessThan(BigUInt(uint64: 1), BigUInt(uint64: 2))
        XCTAssertLessThan(BigUInt(uint64: 0xFFFF_FFFF), BigUInt(uint64: 0x1_0000_0000))
        XCTAssertEqual(BigUInt(uint64: 42), BigUInt(hexString: "2a")!)
        XCTAssertGreaterThan(BigUInt(hexString: "ff")!, BigUInt(uint64: 254))
    }

    func testAddition() {
        XCTAssertEqual(
            (BigUInt(uint64: 0xFFFF_FFFF) + BigUInt(uint64: 1)).hexString,
            "100000000"
        )
        XCTAssertEqual(
            (BigUInt(hexString: "ffffffffffffffff")! + BigUInt(uint64: 1)).hexString,
            "10000000000000000"
        )
    }

    func testSubtraction() {
        XCTAssertEqual(
            (BigUInt(hexString: "100000000")! - BigUInt(uint64: 1)).hexString,
            "ffffffff"
        )
        XCTAssertEqual(
            (BigUInt(hexString: "deadbeef")! - BigUInt(uint64: 1)).hexString,
            "deadbeee"
        )
    }

    func testMultiplication() {
        XCTAssertEqual(
            (BigUInt(uint64: 0xFFFF_FFFF) * BigUInt(uint64: 0xFFFF_FFFF)).hexString,
            "fffffffe00000001"
        )
        XCTAssertEqual(
            (BigUInt(hexString: "100000000")! * BigUInt(uint64: 2)).hexString,
            "200000000"
        )
    }

    func testMod() {
        let modulus = BigUInt(uint64: 97)
        XCTAssertEqual(BigUInt(uint64: 100).mod(modulus), BigUInt(uint64: 3))
        XCTAssertEqual(BigUInt(uint64: 96).mod(modulus), BigUInt(uint64: 96))
        // 大数取模：2^64 mod 97 = 61（手工验算：2^32 ≡ 35 (mod 97)，35² = 1225 ≡ 61）
        XCTAssertEqual(BigUInt(hexString: "10000000000000000")!.mod(modulus), BigUInt(uint64: 61))
    }

    /// 与 Python 参考值逐字节一致的 modPow 测试
    /// （参考向量由 Python `pow(m, e, n)` 预计算）
    func testModPowKnownVector() {
        let modulus = BigUInt(hexString: "c4a2b3c4d5e6f708192a3b4c5d6e7f8090a1b2c3d4e5f60718293a4b5c6d7e8f900102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60")!
        let exponent = BigUInt(hexString: "10001")!
        let message = BigUInt(bytes: Array("test123".utf8))
        let expected = "316fe75233b018504a465dac2b370807a9a30944b640cdaafc1271bd56541818ad9cd89b28d78ea81cece40218a14822c8f7336799893152fb190154d3f752d8d0444b321dbd4a7a52dd2bca177d7bfd163333088192c21f050b0846c01150e7869f16d7ffb69c7f2ff70299052f25efdb369ce0d322ad33ad15e0215fff46edf3"
        XCTAssertEqual(message.modPow(exponent, modulus).hexString, expected)
    }
}
