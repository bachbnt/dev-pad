// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  IDGenerator.swift
//  DevPad
//
//  UUID v4, UUID v7 (RFC 9562) and ULID generation. Every format is built
//  from explicit bytes so tests can feed fixed randomness and a fixed
//  timestamp; `generate` is the only place that touches the system RNG and
//  the clock. Within one batch, IDs created in the same millisecond are not
//  guaranteed to sort in creation order.
//

import Foundation

enum IDKind: String, CaseIterable, Identifiable {
    case uuidV4, uuidV7, ulid
    var id: String { rawValue }
}

enum IDGenerator {

    static let maxCount = 100

    // MARK: - Public

    /// `count` is clamped to `1...maxCount`. `hyphens` only affects UUIDs —
    /// a ULID has no separators.
    static func generate(kind: IDKind, count: Int, uppercase: Bool, hyphens: Bool) -> [String] {
        let n = min(max(count, 1), maxCount)
        var rng = SystemRandomNumberGenerator()
        return (0..<n).map { _ in
            let raw: String
            switch kind {
            case .uuidV4:
                raw = uuidV4(randomBytes: randomBytes(16, using: &rng), hyphens: hyphens)
            case .uuidV7:
                raw = uuidV7(timestampMs: currentMs(), randomBytes: randomBytes(10, using: &rng), hyphens: hyphens)
            case .ulid:
                raw = ulid(timestampMs: currentMs(), randomBytes: randomBytes(10, using: &rng))
            }
            return uppercase ? raw.uppercased() : raw.lowercased()
        }
    }

    // MARK: - UUID

    /// `randomBytes` must hold 16 bytes; version and variant bits are
    /// overwritten.
    static func uuidV4(randomBytes: [UInt8], hyphens: Bool = true) -> String {
        var b = Array(randomBytes.prefix(16))
        while b.count < 16 { b.append(0) }
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        return formatUUID(b, hyphens: hyphens)
    }

    /// 48-bit big-endian Unix milliseconds, then 74 random bits (`randomBytes`
    /// must hold 10 bytes; version and variant bits are overwritten).
    static func uuidV7(timestampMs: UInt64, randomBytes: [UInt8], hyphens: Bool = true) -> String {
        var b = [UInt8](repeating: 0, count: 16)
        for i in 0..<6 {
            b[i] = UInt8((timestampMs >> UInt64(8 * (5 - i))) & 0xFF)
        }
        for i in 0..<10 {
            b[6 + i] = i < randomBytes.count ? randomBytes[i] : 0
        }
        b[6] = (b[6] & 0x0F) | 0x70
        b[8] = (b[8] & 0x3F) | 0x80
        return formatUUID(b, hyphens: hyphens)
    }

    private static func formatUUID(_ b: [UInt8], hyphens: Bool) -> String {
        let hex = b.map { String(format: "%02x", $0) }.joined()
        guard hyphens else { return hex }
        let chars = Array(hex)
        func part(_ r: Range<Int>) -> String { String(chars[r]) }
        return [part(0..<8), part(8..<12), part(12..<16), part(16..<20), part(20..<32)]
            .joined(separator: "-")
    }

    // MARK: - ULID

    private static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// 26 Crockford-Base32 characters: 48-bit timestamp, then 80 random bits
    /// (`randomBytes` must hold 10 bytes).
    static func ulid(timestampMs: UInt64, randomBytes: [UInt8]) -> String {
        var bytes = [UInt8]()
        for i in 0..<6 {
            bytes.append(UInt8((timestampMs >> UInt64(8 * (5 - i))) & 0xFF))
        }
        for i in 0..<10 {
            bytes.append(i < randomBytes.count ? randomBytes[i] : 0)
        }
        // 128 bits don't divide into 5-bit groups: start with two phantom
        // zero bits so the 130-bit stream yields exactly 26 characters and
        // the first one is at most 7 (the spec's overflow guard).
        var out = ""
        var acc: UInt32 = 0
        var bits = 2
        for byte in bytes {
            acc = (acc << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(crockford[Int((acc >> UInt32(bits)) & 0x1F)])
            }
            acc &= (UInt32(1) << UInt32(bits)) - 1
        }
        return out
    }

    // MARK: - System inputs

    private static func randomBytes(_ n: Int, using rng: inout SystemRandomNumberGenerator) -> [UInt8] {
        (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) }
    }

    private static func currentMs() -> UInt64 {
        UInt64(max(0, (Date().timeIntervalSince1970 * 1000).rounded()))
    }
}
