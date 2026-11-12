// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  EncodeEngine.swift
//  DevPad
//
//  Text ↔ Base64 / Base64URL / percent-encoding. Pure Foundation so the
//  unit-test target can compile it without the app. Decoding is forgiving
//  about whitespace and missing `=` padding (both are routine in pasted
//  tokens) but strict about everything else, so a typo is reported instead
//  of being silently decoded to garbage.
//

import Foundation

enum EncodeMode: String, CaseIterable, Identifiable {
    case base64, base64url, url
    var id: String { rawValue }
}

enum EncodeError: LocalizedError {
    case invalidBase64
    case notUTF8
    case invalidPercentEncoding

    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            return "Input is not valid Base64"
        case .notUTF8:
            return "Decoded bytes are not valid UTF-8 text"
        case .invalidPercentEncoding:
            return "Input contains an invalid percent escape (%XX)"
        }
    }
}

enum EncodeEngine {

    // MARK: - Public

    static func encode(_ text: String, mode: EncodeMode) -> String {
        switch mode {
        case .base64:
            return Data(text.utf8).base64EncodedString()
        case .base64url:
            return base64URLString(from: Data(text.utf8))
        case .url:
            return percentEncode(text)
        }
    }

    static func decode(_ text: String, mode: EncodeMode) throws -> String {
        switch mode {
        case .base64:
            return try utf8String(from: try base64Data(from: text, urlSafe: false))
        case .base64url:
            return try utf8String(from: try base64Data(from: text, urlSafe: true))
        case .url:
            // `+` is left alone on purpose: it only means "space" in
            // form-encoded bodies, not in a URL component.
            guard let decoded = text.removingPercentEncoding else {
                throw EncodeError.invalidPercentEncoding
            }
            return decoded
        }
    }

    // MARK: - Base64

    private static func base64URLString(from data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64Data(from text: String, urlSafe: Bool) throws -> Data {
        var s = String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        if urlSafe {
            s = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        }
        // Re-pad. A remainder of 1 can never be produced by a Base64 encoder.
        switch s.count % 4 {
        case 0: break
        case 2: s += "=="
        case 3: s += "="
        default: throw EncodeError.invalidBase64
        }
        guard let data = Data(base64Encoded: s) else { throw EncodeError.invalidBase64 }
        return data
    }

    private static func utf8String(from data: Data) throws -> String {
        guard let s = String(data: data, encoding: .utf8) else { throw EncodeError.notUTF8 }
        return s
    }

    // MARK: - Percent-encoding

    /// RFC 3986 "unreserved" characters stay as they are; everything else is
    /// escaped, including `/ ? & = #` — this is `encodeURIComponent`'s job,
    /// not `encodeURI`'s.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.formUnion(CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
        set.formUnion(CharacterSet(charactersIn: "0123456789-._~"))
        return set
    }()

    private static func percentEncode(_ text: String) -> String {
        // Never nil for a CharacterSet-based call on a valid String.
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}
