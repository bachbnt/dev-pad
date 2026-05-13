//
//  Hashing.swift
//  DevPad
//
//  Thin wrapper that produces hex / base64 digests for the eight
//  algorithms users actually reach for in day-to-day work:
//    • MD2, MD4 — CommonCrypto (legacy, kept for compatibility testing
//      with old systems). Deprecated by Apple but still functional.
//    • MD5, SHA-1 — CryptoKit's `Insecure` namespace.
//    • SHA-224 — CommonCrypto (completes the SHA-2 family).
//    • SHA-256, SHA-384, SHA-512 — top-level CryptoKit types.
//  Plus HMAC variants of the modern SHA family (CryptoKit).
//
//  None of these algorithms require entitlements. MD2/MD4/MD5/SHA-1 are
//  cryptographically broken — they're here for *inspecting* hashes from
//  old systems, not for new security-sensitive work.
//

import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Algorithm

enum HashAlgorithm: String, CaseIterable, Identifiable {
    case md2     = "MD2"
    case md4     = "MD4"
    case md5     = "MD5"
    case sha1    = "SHA-1"
    case sha224  = "SHA-224"
    case sha256  = "SHA-256"
    case sha384  = "SHA-384"
    case sha512  = "SHA-512"

    var id: String { rawValue }

    /// Subset that's usable for HMAC. HMAC-SHA1 is included because it's
    /// still the default for TOTP (RFC 6238, Google Authenticator), AWS
    /// Signature v2, and a fair number of legacy webhook signers. We omit
    /// HMAC-MD2 / HMAC-MD4 / HMAC-MD5 (cryptographically broken with no
    /// active standard still requiring them) and HMAC-SHA224 (rarely
    /// shipped — every modern spec jumps to SHA-256 instead).
    static let hmacAlgorithms: [HashAlgorithm] = [.sha1, .sha256, .sha384, .sha512]
}

// MARK: - Output format

enum HashFormat: String, CaseIterable, Identifiable {
    case hex
    case base64

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .hex:    return "hash.format.hex"
        case .base64: return "hash.format.base64"
        }
    }
}

// MARK: - Engine

enum Hashing {

    /// Hash arbitrary bytes with the given algorithm.
    static func hash(_ data: Data, algorithm: HashAlgorithm) -> Data {
        switch algorithm {
        case .md2:    return ccOneShot(data, length: Int(CC_MD2_DIGEST_LENGTH))    { _CC_MD2($0, $1, $2) }
        case .md4:    return ccOneShot(data, length: Int(CC_MD4_DIGEST_LENGTH))    { _CC_MD4($0, $1, $2) }
        case .md5:    return Data(Insecure.MD5.hash(data: data))
        case .sha1:   return Data(Insecure.SHA1.hash(data: data))
        case .sha224: return ccOneShot(data, length: Int(CC_SHA224_DIGEST_LENGTH)) { CC_SHA224($0, $1, $2) }
        case .sha256: return Data(SHA256.hash(data: data))
        case .sha384: return Data(SHA384.hash(data: data))
        case .sha512: return Data(SHA512.hash(data: data))
        }
    }

    /// Generic helper for CommonCrypto's one-shot digest functions —
    /// takes the data buffer, output length, and a closure that calls
    /// `CC_xxx(data, len, md)`.
    private static func ccOneShot(
        _ data: Data,
        length: Int,
        body: (UnsafeRawPointer?, CC_LONG, UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>?
    ) -> Data {
        var out = [UInt8](repeating: 0, count: length)
        data.withUnsafeBytes { buf in
            _ = body(buf.baseAddress, CC_LONG(buf.count), &out)
        }
        return Data(out)
    }

    /// HMAC over `data` using `key` and the given algorithm.
    /// Returns `nil` if the algorithm isn't in `HashAlgorithm.hmacAlgorithms`
    /// — callers should rely on that list to gate the UI rather than
    /// expecting this to handle every case.
    static func hmac(_ data: Data, key: Data, algorithm: HashAlgorithm) -> Data? {
        let symmetric = SymmetricKey(data: key)
        switch algorithm {
        case .sha1:
            // HMAC-SHA1 is still the workhorse for TOTP / RFC 6238,
            // AWS Signature v2, and various legacy webhook signers.
            let mac = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetric)
            return Data(mac)
        case .sha256:
            let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetric)
            return Data(mac)
        case .sha384:
            let mac = HMAC<SHA384>.authenticationCode(for: data, using: symmetric)
            return Data(mac)
        case .sha512:
            let mac = HMAC<SHA512>.authenticationCode(for: data, using: symmetric)
            return Data(mac)
        case .md2, .md4, .md5, .sha224:
            return nil
        }
    }

    /// Hash an arbitrary-size file by streaming 1 MB chunks through the
    /// algorithm. Runs synchronously and on the caller's queue; callers
    /// should dispatch off the main thread for large files.
    static func hashFile(at url: URL, algorithm: HashAlgorithm) throws -> Data {
        // CryptoKit's `Hash.update(data:)` (and CommonCrypto's CC_xxx_Update)
        // let us feed the file in chunks so memory stays bounded regardless
        // of file size.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let chunkSize = 1 << 20  // 1 MB

        switch algorithm {
        case .md2:
            var ctx = CC_MD2_CTX()
            _ = _CC_MD2_Init(&ctx)
            try streamHandle(handle, chunkSize: chunkSize) { chunk in
                chunk.withUnsafeBytes { _ = _CC_MD2_Update(&ctx, $0.baseAddress, CC_LONG(chunk.count)) }
            }
            var out = [UInt8](repeating: 0, count: Int(CC_MD2_DIGEST_LENGTH))
            _ = _CC_MD2_Final(&out, &ctx)
            return Data(out)
        case .md4:
            var ctx = CC_MD4_CTX()
            _ = _CC_MD4_Init(&ctx)
            try streamHandle(handle, chunkSize: chunkSize) { chunk in
                chunk.withUnsafeBytes { _ = _CC_MD4_Update(&ctx, $0.baseAddress, CC_LONG(chunk.count)) }
            }
            var out = [UInt8](repeating: 0, count: Int(CC_MD4_DIGEST_LENGTH))
            _ = _CC_MD4_Final(&out, &ctx)
            return Data(out)
        case .md5:
            var h = Insecure.MD5()
            try streamHandle(handle, chunkSize: chunkSize) { h.update(data: $0) }
            return Data(h.finalize())
        case .sha1:
            var h = Insecure.SHA1()
            try streamHandle(handle, chunkSize: chunkSize) { h.update(data: $0) }
            return Data(h.finalize())
        case .sha224:
            // SHA-224 reuses the SHA-256 context type with a different init.
            var ctx = CC_SHA256_CTX()
            _ = CC_SHA224_Init(&ctx)
            try streamHandle(handle, chunkSize: chunkSize) { chunk in
                chunk.withUnsafeBytes { _ = CC_SHA224_Update(&ctx, $0.baseAddress, CC_LONG(chunk.count)) }
            }
            var out = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
            _ = CC_SHA224_Final(&out, &ctx)
            return Data(out)
        case .sha256:
            var h = SHA256()
            try streamHandle(handle, chunkSize: chunkSize) { h.update(data: $0) }
            return Data(h.finalize())
        case .sha384:
            var h = SHA384()
            try streamHandle(handle, chunkSize: chunkSize) { h.update(data: $0) }
            return Data(h.finalize())
        case .sha512:
            var h = SHA512()
            try streamHandle(handle, chunkSize: chunkSize) { h.update(data: $0) }
            return Data(h.finalize())
        }
    }

    // MARK: - Deprecation-free symbol aliases for MD2 / MD4
    //
    // CommonCrypto marks CC_MD2 / CC_MD4 (and their _Init/_Update/_Final
    // variants) as `API_DEPRECATED`. The deprecation is documentation —
    // the symbols still link and run on every supported macOS. To call
    // them without flooding the build log with deprecation warnings we
    // re-import the C symbols under aliased names using `@_silgen_name`,
    // which skips the SDK's availability attributes.

    @_silgen_name("CC_MD2")
    private static func _CC_MD2(_ data: UnsafeRawPointer?,
                                _ len: CC_LONG,
                                _ md: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>?
    @_silgen_name("CC_MD2_Init")
    private static func _CC_MD2_Init(_ ctx: UnsafeMutablePointer<CC_MD2_CTX>) -> Int32
    @_silgen_name("CC_MD2_Update")
    private static func _CC_MD2_Update(_ ctx: UnsafeMutablePointer<CC_MD2_CTX>,
                                       _ data: UnsafeRawPointer?,
                                       _ len: CC_LONG) -> Int32
    @_silgen_name("CC_MD2_Final")
    private static func _CC_MD2_Final(_ md: UnsafeMutablePointer<UInt8>,
                                      _ ctx: UnsafeMutablePointer<CC_MD2_CTX>) -> Int32

    @_silgen_name("CC_MD4")
    private static func _CC_MD4(_ data: UnsafeRawPointer?,
                                _ len: CC_LONG,
                                _ md: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>?
    @_silgen_name("CC_MD4_Init")
    private static func _CC_MD4_Init(_ ctx: UnsafeMutablePointer<CC_MD4_CTX>) -> Int32
    @_silgen_name("CC_MD4_Update")
    private static func _CC_MD4_Update(_ ctx: UnsafeMutablePointer<CC_MD4_CTX>,
                                       _ data: UnsafeRawPointer?,
                                       _ len: CC_LONG) -> Int32
    @_silgen_name("CC_MD4_Final")
    private static func _CC_MD4_Final(_ md: UnsafeMutablePointer<UInt8>,
                                      _ ctx: UnsafeMutablePointer<CC_MD4_CTX>) -> Int32

    private static func streamHandle(_ handle: FileHandle,
                                     chunkSize: Int,
                                     feed: (Data) -> Void) throws {
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { return }
            feed(chunk)
        }
    }

    // MARK: - Encoding

    /// Returns the digest as lowercase hex.
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func base64(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func encode(_ data: Data, format: HashFormat) -> String {
        switch format {
        case .hex:    return hex(data)
        case .base64: return base64(data)
        }
    }

    /// Loose comparison used by the "Compare with" field: trims whitespace,
    /// strips common separators and is case-insensitive.
    static func looselyEqual(_ a: String, _ b: String) -> Bool {
        func normalize(_ s: String) -> String {
            s.unicodeScalars
                .filter { !CharacterSet.whitespacesAndNewlines.contains($0)
                       && $0 != ":" && $0 != "-" }
                .map { Character($0) }
                .reduce(into: "") { $0.append($1) }
                .lowercased()
        }
        return !a.isEmpty && normalize(a) == normalize(b)
    }
}
