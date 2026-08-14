import XCTest
@testable import OmniView

final class RawRSATests: XCTestCase {

    /// 裸 RSA 加密：与 Python 参考值一致（ZJU CAS 登录加密）
    func testEncryptKnownVector() {
        let modulus = "c4a2b3c4d5e6f708192a3b4c5d6e7f8090a1b2c3d4e5f60718293a4b5c6d7e8f900102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60"
        let encrypted = RawRSA.encrypt("test123", modulusHex: modulus, exponentHex: "10001")
        XCTAssertEqual(
            encrypted,
            "316fe75233b018504a465dac2b370807a9a30944b640cdaafc1271bd56541818ad9cd89b28d78ea81cece40218a14822c8f7336799893152fb190154d3f752d8d0444b321dbd4a7a52dd2bca177d7bfd163333088192c21f050b0846c01150e7869f16d7ffb69c7f2ff70299052f25efdb369ce0d322ad33ad15e0215fff46edf3"
        )
    }

    /// 空密码与非法参数应返回 nil
    func testEncryptInvalidInputs() {
        XCTAssertNil(RawRSA.encrypt("", modulusHex: "10", exponentHex: "10001"))
        XCTAssertNil(RawRSA.encrypt("secret", modulusHex: "zz", exponentHex: "10001"))
        XCTAssertNil(RawRSA.encrypt("secret", modulusHex: "10", exponentHex: "zz"))
    }

    /// 明文超过模数长度应返回 nil
    func testEncryptMessageTooLong() {
        let modulus = "ff"
        XCTAssertNil(RawRSA.encrypt("longer than modulus", modulusHex: modulus, exponentHex: "3"))
    }
}
