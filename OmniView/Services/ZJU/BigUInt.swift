import Foundation

/// 大整数（无符号，小端 limb，基 2^32）
/// 用于实现 ZJU CAS 登录所需的裸 RSA (m^e mod n) 加密
struct BigUInt: Comparable, CustomStringConvertible {
    /// 小端序 limb 数组，无前导零
    private(set) var limbs: [UInt32]

    static let zero = BigUInt(limbs: [])

    init(limbs: [UInt32]) {
        var result = limbs
        while result.count > 0 && result.last == 0 {
            result.removeLast()
        }
        self.limbs = result
    }

    /// 从大端字节构造
    init(bytes: [UInt8]) {
        var limbs: [UInt32] = []
        var index = bytes.count
        while index > 0 {
            let start = max(0, index - 4)
            var value: UInt32 = 0
            for byte in bytes[start..<index] {
                value = (value << 8) | UInt32(byte)
            }
            limbs.append(value)
            index = start
        }
        self.init(limbs: limbs)
    }

    init(uint64 value: UInt64) {
        if value == 0 {
            self.init(limbs: [])
        } else {
            self.init(limbs: [UInt32(value & 0xFFFF_FFFF), UInt32(value >> 32)])
        }
    }

    var isZero: Bool { limbs.isEmpty }

    /// 二进制位宽
    var bitWidth: Int {
        guard let top = limbs.last else { return 0 }
        return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }

    func bit(at index: Int) -> Bool {
        let limbIndex = index / 32
        guard limbIndex < limbs.count else { return false }
        return (limbs[limbIndex] >> UInt32(index % 32)) & 1 == 1
    }

    /// 左移 1 位
    func shiftedLeftOne() -> BigUInt {
        if isZero { return self }
        var result = limbs
        var carry: UInt32 = 0
        for i in 0..<result.count {
            let newCarry = result[i] >> 31
            result[i] = (result[i] << 1) | carry
            carry = newCarry
        }
        if carry != 0 { result.append(carry) }
        return BigUInt(limbs: result)
    }

    /// 加法
    static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        var result: [UInt32] = []
        var carry: UInt64 = 0
        let count = max(lhs.limbs.count, rhs.limbs.count)
        for i in 0..<count {
            let a = i < lhs.limbs.count ? UInt64(lhs.limbs[i]) : 0
            let b = i < rhs.limbs.count ? UInt64(rhs.limbs[i]) : 0
            let sum = a + b + carry
            result.append(UInt32(sum & 0xFFFF_FFFF))
            carry = sum >> 32
        }
        if carry > 0 { result.append(UInt32(carry)) }
        return BigUInt(limbs: result)
    }

    /// 减法（要求 lhs >= rhs）
    static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        var result: [UInt32] = []
        var borrow: UInt64 = 0
        for i in 0..<max(lhs.limbs.count, rhs.limbs.count) {
            let a = i < lhs.limbs.count ? UInt64(lhs.limbs[i]) : 0
            let b = i < rhs.limbs.count ? UInt64(rhs.limbs[i]) : 0
            var diff = a &- b &- borrow
            if a < b + borrow {
                diff = (a &+ (1 << 32)) &- b &- borrow
                borrow = 1
            } else {
                borrow = 0
            }
            result.append(UInt32(diff & 0xFFFF_FFFF))
        }
        return BigUInt(limbs: result)
    }

    /// 乘法（教科书式）
    static func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        if lhs.isZero || rhs.isZero { return .zero }
        var result = [UInt32](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
        for i in 0..<lhs.limbs.count {
            var carry: UInt64 = 0
            for j in 0..<rhs.limbs.count {
                let index = i + j
                let product = UInt64(lhs.limbs[i]) * UInt64(rhs.limbs[j])
                    + UInt64(result[index]) + carry
                result[index] = UInt32(product & 0xFFFF_FFFF)
                carry = product >> 32
            }
            var index = i + rhs.limbs.count
            while carry > 0 {
                let sum = UInt64(result[index]) + carry
                result[index] = UInt32(sum & 0xFFFF_FFFF)
                carry = sum >> 32
                index += 1
            }
        }
        return BigUInt(limbs: result)
    }

    static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.limbs.count != rhs.limbs.count {
            return lhs.limbs.count < rhs.limbs.count
        }
        for i in stride(from: lhs.limbs.count - 1, through: 0, by: -1) where lhs.limbs[i] != rhs.limbs[i] {
            return lhs.limbs[i] < rhs.limbs[i]
        }
        return false
    }

    static func == (lhs: BigUInt, rhs: BigUInt) -> Bool {
        lhs.limbs == rhs.limbs
    }

    /// 模运算（二进制长除法）
    func mod(_ modulus: BigUInt) -> BigUInt {
        precondition(!modulus.isZero, "modulus 不能为零")
        if self < modulus { return self }
        var remainder = BigUInt.zero
        for i in stride(from: bitWidth - 1, through: 0, by: -1) {
            remainder = remainder.shiftedLeftOne()
            if bit(at: i) {
                if remainder.limbs.isEmpty {
                    remainder.limbs = [1]
                } else {
                    remainder.limbs[0] |= 1
                }
            }
            if remainder >= modulus {
                remainder = remainder - modulus
            }
        }
        return remainder
    }

    /// 模幂：self^exponent mod modulus
    func modPow(_ exponent: BigUInt, _ modulus: BigUInt) -> BigUInt {
        var base = self.mod(modulus)
        var exp = exponent
        var result = BigUInt(uint64: 1)
        while !exp.isZero {
            if exp.bit(at: 0) {
                result = (result * base).mod(modulus)
            }
            exp = exp >> 1
            base = (base * base).mod(modulus)
        }
        return result
    }

    /// 右移 1 位
    static func >> (lhs: BigUInt, rhs: Int) -> BigUInt {
        guard rhs > 0, !lhs.isZero else { return lhs }
        var result: [UInt32] = []
        var carry: UInt32 = 0
        for i in stride(from: lhs.limbs.count - 1, through: 0, by: -1) {
            let value = (carry << 31) | (lhs.limbs[i] >> 1)
            result.append(value)
            carry = lhs.limbs[i] & 1
        }
        return BigUInt(limbs: result.reversed())
    }

    /// 大端十六进制字符串
    var hexString: String {
        guard !isZero else { return "0" }
        var bytes: [UInt8] = []
        for limb in limbs.reversed() {
            bytes.append(UInt8((limb >> 24) & 0xFF))
            bytes.append(UInt8((limb >> 16) & 0xFF))
            bytes.append(UInt8((limb >> 8) & 0xFF))
            bytes.append(UInt8(limb & 0xFF))
        }
        // 去掉前导零字节
        while bytes.count > 1 && bytes[0] == 0 {
            bytes.removeFirst()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    var description: String { hexString }
}

// MARK: - 裸 RSA 加密

enum RawRSA {
    /// ZJU CAS 的裸 RSA：将明文字节作为大整数，计算 m^e mod n，输出十六进制
    static func encrypt(_ plaintext: String, modulusHex: String, exponentHex: String) -> String? {
        guard let modulus = BigUInt(hexString: modulusHex),
              let exponent = BigUInt(hexString: exponentHex),
              !modulus.isZero, !exponent.isZero
        else {
            return nil
        }
        let message = BigUInt(bytes: Array(plaintext.utf8))
        if message >= modulus { return nil }
        return message.modPow(exponent, modulus).hexString
    }
}

extension BigUInt {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        if cleaned.count % 2 != 0 {
            guard let first = UInt8(String(cleaned[index]), radix: 16) else { return nil }
            bytes.append(first)
            index = cleaned.index(after: index)
        }
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(String(cleaned[index..<next]), radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes: bytes)
    }
}
