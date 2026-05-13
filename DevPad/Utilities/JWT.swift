//
//  JWT.swift
//  DevPad
//
//  JWT (RFC 7519) decoder, signer (HMAC), and verifier (HMAC + RSA + ECDSA).
//
//  Design choices:
//    • Decode never throws on bad signature — we always return whatever
//      we can parse so the user can still inspect the header/payload of
//      a malformed-but-recognisable token.
//    • Sign is only implemented for HMAC algorithms. Asymmetric signing
//      needs private-key (PKCS#8) parsing which is significantly more
//      involved and easy to misuse; users who need that should reach for
//      a CLI tool.
//    • Verify supports HS256/384/512 (CryptoKit), RS256/384/512
//      (SecKey + SPKI parse), and ES256/384/512 (SecKey + JOSE→DER
//      signature conversion).
//

import Foundation
import CryptoKit
import Security

// MARK: - Errors

enum JWTError: LocalizedError {
    case empty
    case malformed
    case base64Decoding
    case jsonDecoding
    case unsupportedAlgorithm(String)
    case invalidKey
    case signFailed
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .empty:                       return "Input is empty."
        case .malformed:                   return "Not a valid JWT — expected three dot-separated parts."
        case .base64Decoding:              return "A segment is not valid base64url."
        case .jsonDecoding:                return "Header or payload is not valid JSON."
        case .unsupportedAlgorithm(let a): return "Algorithm \"\(a)\" is not supported."
        case .invalidKey:                  return "Key could not be parsed."
        case .signFailed:                  return "Could not sign the token."
        case .verifyFailed(let m):         return m
        }
    }
}

// MARK: - JWT value

struct JWT {

    enum Status {
        case valid
        case expired(at: Date)
        case notYetActive(until: Date)
        case noExpiration
    }

    /// Raw header JSON object.
    let headerJSON: [String: Any]
    /// Raw payload JSON object.
    let payloadJSON: [String: Any]
    /// Decoded signature bytes.
    let signature: Data

    /// The exact base64url segments — preserved verbatim so verify uses
    /// the *original* bytes (canonicalising the JSON would change the
    /// signing input and break verification).
    let rawHeader: String
    let rawPayload: String
    let rawSignature: String

    /// `"<rawHeader>.<rawPayload>"`. Verification recomputes the signature
    /// over these UTF-8 bytes.
    var signingInput: String { "\(rawHeader).\(rawPayload)" }

    // MARK: Header

    var algorithm: String? { headerJSON["alg"] as? String }
    var type: String?      { headerJSON["typ"] as? String }
    var keyID: String?     { headerJSON["kid"] as? String }

    // MARK: Standard claims

    var issuer: String?       { payloadJSON["iss"] as? String }
    var subject: String?      { payloadJSON["sub"] as? String }
    var jwtID: String?        { payloadJSON["jti"] as? String }

    var audience: [String] {
        if let arr = payloadJSON["aud"] as? [String] { return arr }
        if let one = payloadJSON["aud"] as? String   { return [one] }
        return []
    }

    var issuedAt: Date?   { Self.date(from: payloadJSON["iat"]) }
    var expiresAt: Date?  { Self.date(from: payloadJSON["exp"]) }
    var notBefore: Date?  { Self.date(from: payloadJSON["nbf"]) }

    var status: Status {
        let now = Date()
        if let nbf = notBefore, now < nbf {
            return .notYetActive(until: nbf)
        }
        if let exp = expiresAt {
            return now < exp ? .valid : .expired(at: exp)
        }
        return .noExpiration
    }

    private static func date(from value: Any?) -> Date? {
        if let n = value as? Double { return Date(timeIntervalSince1970: n) }
        if let n = value as? Int    { return Date(timeIntervalSince1970: TimeInterval(n)) }
        if let s = value as? String, let n = TimeInterval(s) {
            return Date(timeIntervalSince1970: n)
        }
        return nil
    }
}

// MARK: - Decoder / signer

enum JWTCoder {

    // MARK: Decode

    static func decode(_ token: String) throws -> JWT {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JWTError.empty }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw JWTError.malformed }

        let h = String(parts[0])
        let p = String(parts[1])
        let s = String(parts[2])

        guard let headerData = Self.base64URLDecode(h),
              let payloadData = Self.base64URLDecode(p) else {
            throw JWTError.base64Decoding
        }
        let signatureData = Self.base64URLDecode(s) ?? Data()

        guard let header = (try? JSONSerialization.jsonObject(with: headerData))
                as? [String: Any],
              let payload = (try? JSONSerialization.jsonObject(with: payloadData))
                as? [String: Any] else {
            throw JWTError.jsonDecoding
        }

        return JWT(
            headerJSON: header,
            payloadJSON: payload,
            signature: signatureData,
            rawHeader: h,
            rawPayload: p,
            rawSignature: s
        )
    }

    // MARK: Sign (HMAC only)

    /// Produces a JWT string by signing `header` + `payload` with `secret`
    /// using the algorithm declared inside `header`. Only HS256/HS384/HS512
    /// are supported.
    static func sign(headerJSON: String, payloadJSON: String, secret: String) throws -> String {
        let headerBytes = try canonicaliseJSON(headerJSON)
        let payloadBytes = try canonicaliseJSON(payloadJSON)

        let h = Self.base64URLEncode(headerBytes)
        let p = Self.base64URLEncode(payloadBytes)
        let signingInput = "\(h).\(p)".data(using: .utf8) ?? Data()

        // Determine algorithm from header.
        guard let header = (try? JSONSerialization.jsonObject(with: headerBytes))
                as? [String: Any],
              let alg = header["alg"] as? String else {
            throw JWTError.unsupportedAlgorithm("missing")
        }

        let signature: Data
        switch alg {
        case "HS256": signature = hmac(SHA256.self, message: signingInput, secret: secret)
        case "HS384": signature = hmac(SHA384.self, message: signingInput, secret: secret)
        case "HS512": signature = hmac(SHA512.self, message: signingInput, secret: secret)
        default:
            throw JWTError.unsupportedAlgorithm(alg)
        }

        return "\(h).\(p).\(Self.base64URLEncode(signature))"
    }

    // MARK: Verify

    /// Verifies the token's signature. `key` is either the HMAC secret
    /// (string) for HS*, or a PEM-encoded public key for RS*/ES*.
    static func verify(_ jwt: JWT, key: String) throws -> Bool {
        guard let alg = jwt.algorithm else {
            throw JWTError.unsupportedAlgorithm("missing")
        }
        guard !jwt.signature.isEmpty else {
            // "alg":"none" tokens have an empty signature; verifying them
            // is meaningless — fail loudly rather than silently accept.
            if alg.lowercased() == "none" {
                throw JWTError.verifyFailed("Refusing to verify an \"alg\":\"none\" token.")
            }
            throw JWTError.verifyFailed("Signature is empty.")
        }

        let input = Data(jwt.signingInput.utf8)

        switch alg {
        case "HS256": return verifyHMAC(SHA256.self, jwt: jwt, input: input, secret: key)
        case "HS384": return verifyHMAC(SHA384.self, jwt: jwt, input: input, secret: key)
        case "HS512": return verifyHMAC(SHA512.self, jwt: jwt, input: input, secret: key)
        case "RS256", "RS384", "RS512",
             "ES256", "ES384", "ES512":
            return try verifyAsymmetric(jwt: jwt, alg: alg, input: input, publicKeyPEM: key)
        default:
            throw JWTError.unsupportedAlgorithm(alg)
        }
    }

    // MARK: - HMAC helpers

    private static func hmac<H: HashFunction>(_ hashType: H.Type, message: Data, secret: String) -> Data {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<H>.authenticationCode(for: message, using: key)
        return Data(mac)
    }

    private static func verifyHMAC<H: HashFunction>(
        _ hashType: H.Type, jwt: JWT, input: Data, secret: String
    ) -> Bool {
        let key = SymmetricKey(data: Data(secret.utf8))
        return HMAC<H>.isValidAuthenticationCode(
            jwt.signature, authenticating: input, using: key
        )
    }

    // MARK: - Asymmetric verify

    private static func verifyAsymmetric(
        jwt: JWT, alg: String, input: Data, publicKeyPEM: String
    ) throws -> Bool {
        let isRSA = alg.hasPrefix("RS")
        let keyType: CFString = isRSA
            ? kSecAttrKeyTypeRSA
            : kSecAttrKeyTypeECSECPrimeRandom

        let pemBody = stripPEM(publicKeyPEM)
        guard let der = Data(base64Encoded: pemBody) else {
            throw JWTError.invalidKey
        }
        let rawKey = isRSA
            ? (stripRSASPKI(der) ?? der)
            : (stripECSPKI(der) ?? der)

        let attrs: [String: Any] = [
            kSecAttrKeyType as String:  keyType,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var keyError: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(
            rawKey as CFData, attrs as CFDictionary, &keyError
        ) else {
            throw JWTError.invalidKey
        }

        // Map JWT alg → SecKey algorithm constant.
        let secAlg: SecKeyAlgorithm
        switch alg {
        case "RS256": secAlg = .rsaSignatureMessagePKCS1v15SHA256
        case "RS384": secAlg = .rsaSignatureMessagePKCS1v15SHA384
        case "RS512": secAlg = .rsaSignatureMessagePKCS1v15SHA512
        case "ES256": secAlg = .ecdsaSignatureMessageX962SHA256
        case "ES384": secAlg = .ecdsaSignatureMessageX962SHA384
        case "ES512": secAlg = .ecdsaSignatureMessageX962SHA512
        default:
            throw JWTError.unsupportedAlgorithm(alg)
        }

        // ECDSA JWT signature is concatenated R||S (JOSE format); SecKey
        // wants ASN.1 DER. Convert before verifying.
        let signature = alg.hasPrefix("ES")
            ? joseToDERSignature(jwt.signature)
            : jwt.signature

        var verifyError: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(
            secKey, secAlg, input as CFData, signature as CFData, &verifyError
        )
        return ok
    }

    // MARK: - Base64URL

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-add stripped `=` padding.
        let pad = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: s)
    }

    // MARK: - JSON canonicalisation

    private static func canonicaliseJSON(_ raw: String) throws -> Data {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JWTError.empty }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw JWTError.jsonDecoding
        }
        // Re-serialise without spaces and in stable key order.
        let opts: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        return try JSONSerialization.data(withJSONObject: obj, options: opts)
    }

    // MARK: - PEM / SPKI helpers

    private static func stripPEM(_ pem: String) -> String {
        pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN EC PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END EC PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Walks an `RSA SubjectPublicKeyInfo` and returns just the inner
    /// `RSAPublicKey` PKCS#1 DER bytes, which is what `SecKeyCreateWithData`
    /// wants for `kSecAttrKeyTypeRSA`. Returns nil if the input doesn't
    /// look like SPKI (caller will then fall back to the unstripped data).
    private static func stripRSASPKI(_ data: Data) -> Data? {
        // SPKI: SEQUENCE { SEQUENCE { OID rsaEncryption, NULL }, BIT STRING { RSAPublicKey } }
        // Easiest: find the BIT STRING (0x03) tag, parse its length, skip
        // the mandatory 0x00 padding byte, return the rest.
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0x03 {
                let lengthIdx = i + 1
                guard lengthIdx < bytes.count else { return nil }
                let lengthOctet = bytes[lengthIdx]
                let lengthByteCount: Int
                if lengthOctet & 0x80 != 0 {
                    lengthByteCount = Int(lengthOctet & 0x7F)
                } else {
                    lengthByteCount = 0
                }
                // Content starts after: tag(1) + length-header(1 + lengthByteCount) + padding(1).
                let contentStart = i + 2 + lengthByteCount + 1
                guard contentStart < bytes.count else { return nil }
                return Data(bytes[contentStart...])
            }
            i += 1
        }
        return nil
    }

    /// EC SPKI: SecKeyCreateWithData expects the X9.63 uncompressed point
    /// (0x04 || X || Y) for the public key. Inside SPKI that's the body
    /// of the BIT STRING.
    private static func stripECSPKI(_ data: Data) -> Data? {
        // Reuse the BIT-STRING logic — for EC SPKI the BIT STRING body
        // *is* the X9.63 encoded point (no inner PKCS#1 wrapper).
        return stripRSASPKI(data)
    }

    // MARK: - JOSE → DER signature

    /// Converts a JWT ECDSA signature (R||S concatenation, JOSE format)
    /// into an ASN.1 DER `ECDSA-Sig-Value` so `SecKeyVerifySignature` can
    /// accept it.
    private static func joseToDERSignature(_ raw: Data) -> Data {
        let half = raw.count / 2
        guard half > 0 else { return raw }
        let r = raw.prefix(half)
        let s = raw.suffix(half)

        func encodeInteger(_ bytes: Data) -> Data {
            // ASN.1 INTEGER must be in two's complement. If the high bit
            // is set, prepend a 0x00 byte so the value isn't read as
            // negative.
            var b = Array(bytes)
            // Strip leading zeros (ASN.1 disallows them unless required
            // by the high-bit rule above).
            while b.count > 1, b.first == 0x00, (b[1] & 0x80) == 0 {
                b.removeFirst()
            }
            if (b.first ?? 0) & 0x80 != 0 {
                b.insert(0x00, at: 0)
            }
            var out = Data([0x02, UInt8(b.count)])
            out.append(contentsOf: b)
            return out
        }

        let ri = encodeInteger(r)
        let si = encodeInteger(s)
        let body = ri + si
        var out = Data([0x30])
        if body.count < 0x80 {
            out.append(UInt8(body.count))
        } else if body.count < 0x100 {
            out.append(contentsOf: [0x81, UInt8(body.count)])
        } else {
            out.append(contentsOf: [0x82,
                                    UInt8((body.count >> 8) & 0xFF),
                                    UInt8(body.count & 0xFF)])
        }
        out.append(body)
        return out
    }
}
