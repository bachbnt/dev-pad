// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  QRPayload.swift
//  DevPad
//
//  Builds — and reads back — the structured text that phones recognise inside
//  a QR code: VietQR bank transfers (NAPAS / EMVCo merchant-presented QR),
//  Wi-Fi network credentials (`WIFI:…`) and vCard 3.0 contacts. A QR code is
//  only a string; everything here is pure string work so the unit-test
//  target can compile it without the app.
//

import Foundation

enum QRPayloadError: LocalizedError {
    case bankRequired
    case invalidBIN
    case invalidAccount
    case invalidAmount
    case messageTooLong(max: Int)
    case ssidRequired
    case ssidTooLong
    case passwordRequired
    case passwordLength
    case nameRequired
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .bankRequired:
            return "Choose a bank"
        case .invalidBIN:
            return "Bank code (BIN) must be exactly 6 digits"
        case .invalidAccount:
            return "Account number must be 1–19 digits"
        case .invalidAmount:
            return "Amount must be a whole number of VND greater than 0"
        case .messageTooLong(let max):
            return "Message is too long (at most \(max) characters)"
        case .ssidRequired:
            return "Network name (SSID) is required"
        case .ssidTooLong:
            return "Network name (SSID) is longer than 32 bytes"
        case .passwordRequired:
            return "A password is required for this security type"
        case .passwordLength:
            return "WPA passwords must be 8–63 characters (or 64 hex digits)"
        case .nameRequired:
            return "Enter a first or last name"
        case .invalidEmail:
            return "Email address looks invalid"
        }
    }
}

// MARK: - VietQR

struct VietQRBank: Identifiable, Hashable {
    let bin: String
    let name: String
    var id: String { bin }
}

struct VietQRInfo: Equatable {
    let bin: String
    let account: String
    /// `nil` for a static QR — the payer types the amount.
    let amount: Int?
    let message: String?
}

enum VietQR {

    /// Banks whose BIN accepts interbank transfers. Source: VietQR's public
    /// list (api.vietqr.io/v2/banks, fetched 2026-11-12, wallets removed).
    /// Anything missing can still be used through the "other" BIN field.
    static let banks: [VietQRBank] = [
        VietQRBank(bin: "970436", name: "Vietcombank"),
        VietQRBank(bin: "970407", name: "Techcombank"),
        VietQRBank(bin: "970422", name: "MB Bank"),
        VietQRBank(bin: "970418", name: "BIDV"),
        VietQRBank(bin: "970415", name: "VietinBank"),
        VietQRBank(bin: "970416", name: "ACB"),
        VietQRBank(bin: "970432", name: "VPBank"),
        VietQRBank(bin: "970423", name: "TPBank"),
        VietQRBank(bin: "970405", name: "Agribank"),
        VietQRBank(bin: "970403", name: "Sacombank"),
        VietQRBank(bin: "970425", name: "ABBank"),
        VietQRBank(bin: "970409", name: "Bac A Bank"),
        VietQRBank(bin: "970438", name: "BaoViet Bank"),
        VietQRBank(bin: "546034", name: "CAKE"),
        VietQRBank(bin: "970444", name: "CBBank"),
        VietQRBank(bin: "422589", name: "CIMB"),
        VietQRBank(bin: "970446", name: "Co-opBank"),
        VietQRBank(bin: "970431", name: "Eximbank"),
        VietQRBank(bin: "970437", name: "HDBank"),
        VietQRBank(bin: "970434", name: "Indovina Bank"),
        VietQRBank(bin: "668888", name: "KBank"),
        VietQRBank(bin: "970452", name: "Kienlongbank"),
        VietQRBank(bin: "970462", name: "Kookmin (Hà Nội)"),
        VietQRBank(bin: "970463", name: "Kookmin (TP.HCM)"),
        VietQRBank(bin: "970449", name: "LPBank"),
        VietQRBank(bin: "970414", name: "MBV"),
        VietQRBank(bin: "970426", name: "MSB"),
        VietQRBank(bin: "970428", name: "Nam A Bank"),
        VietQRBank(bin: "970419", name: "NCB"),
        VietQRBank(bin: "970448", name: "OCB"),
        VietQRBank(bin: "970430", name: "PGBank"),
        VietQRBank(bin: "970412", name: "PVcomBank"),
        VietQRBank(bin: "970400", name: "Saigon Bank"),
        VietQRBank(bin: "970429", name: "SCB"),
        VietQRBank(bin: "970440", name: "SeABank"),
        VietQRBank(bin: "970443", name: "SHB"),
        VietQRBank(bin: "970424", name: "Shinhan Bank"),
        VietQRBank(bin: "963388", name: "Timo"),
        VietQRBank(bin: "546035", name: "Ubank"),
        VietQRBank(bin: "970441", name: "VIB"),
        VietQRBank(bin: "970454", name: "Viet Capital Bank"),
        VietQRBank(bin: "970427", name: "VietABank"),
        VietQRBank(bin: "970433", name: "VietBank"),
        VietQRBank(bin: "970457", name: "Woori")
    ]

    static func bankName(forBIN bin: String) -> String? {
        banks.first { $0.bin == bin }?.name
    }

    /// Some banks cut or reject longer transfer descriptions; the UI warns
    /// above this but the engine only enforces the TLV hard limit.
    static let recommendedMessageLength = 25
    /// Tag 62 holds `08 LL <message>` and its own length is two digits.
    static let maxMessageLength = 95

    // MARK: Build

    static func build(bin: String, account: String, amount: Int? = nil, message: String = "") throws -> String {
        let bin = bin.trimmingCharacters(in: .whitespaces)
        guard bin.count == 6, bin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw QRPayloadError.invalidBIN
        }
        let account = account.filter { !$0.isWhitespace }
        guard (1...19).contains(account.count), account.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw QRPayloadError.invalidAccount
        }
        if let amount {
            guard amount > 0, String(amount).count <= 13 else { throw QRPayloadError.invalidAmount }
        }
        let note = sanitizeMessage(message)
        guard note.count <= maxMessageLength else {
            throw QRPayloadError.messageTooLong(max: maxMessageLength)
        }

        let beneficiary = tlv("00", bin) + tlv("01", account)
        let merchantInfo = tlv("00", napasGUID) + tlv("01", beneficiary) + tlv("02", serviceToAccount)

        var body = tlv("00", "01")
        body += tlv("01", amount == nil ? "11" : "12")
        body += tlv("38", merchantInfo)
        body += tlv("53", "704")
        if let amount { body += tlv("54", String(amount)) }
        body += tlv("58", "VN")
        if !note.isEmpty { body += tlv("62", tlv("08", note)) }
        body += "6304"
        return body + crc16(body)
    }

    /// Parses what a user typed into the amount field: digits, optionally with
    /// `.` `,` or spaces as thousands separators. Empty means "no amount".
    static func parseAmount(_ text: String) throws -> Int? {
        let digits = text.filter { !$0.isWhitespace && $0 != "." && $0 != "," }
        if digits.isEmpty { return nil }
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              digits.count <= 13,
              let value = Int(digits), value > 0 else { throw QRPayloadError.invalidAmount }
        return value
    }

    /// Transfer descriptions travel best as plain ASCII: banking apps differ
    /// in how they treat accents, so fold them away (đ/Đ have no Unicode
    /// decomposition and need a manual step) and drop anything unprintable.
    static func sanitizeMessage(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let ascii = folded.unicodeScalars.filter { $0.value >= 0x20 && $0.value < 0x7F }
        return String(String.UnicodeScalarView(ascii)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Parse

    /// `nil` unless `payload` is a NAPAS VietQR with a valid checksum.
    static func parse(_ payload: String) -> VietQRInfo? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("000201"), text.count > 8 else { return nil }
        let crcStart = text.index(text.endIndex, offsetBy: -4)
        let signed = String(text[..<crcStart])
        guard signed.hasSuffix("6304"), crc16(signed) == text[crcStart...].uppercased() else { return nil }

        guard let top = readTLV(String(signed.dropLast(4))) else { return nil }
        let fields = Dictionary(top.map { ($0.tag, $0.value) }, uniquingKeysWith: { first, _ in first })
        guard let merchant = fields["38"].flatMap(readTLV),
              merchant.first(where: { $0.tag == "00" })?.value == napasGUID,
              let beneficiaryRaw = merchant.first(where: { $0.tag == "01" })?.value,
              let beneficiary = readTLV(beneficiaryRaw),
              let bin = beneficiary.first(where: { $0.tag == "00" })?.value,
              let account = beneficiary.first(where: { $0.tag == "01" })?.value else { return nil }

        let message = fields["62"].flatMap(readTLV)?.first(where: { $0.tag == "08" })?.value
        return VietQRInfo(bin: bin,
                          account: account,
                          amount: fields["54"].flatMap { Int($0) },
                          message: message)
    }

    // MARK: Internals

    private static let napasGUID = "A000000727"
    /// "Quick transfer to an account", as opposed to `QRIBFTTC` (to a card).
    private static let serviceToAccount = "QRIBFTTA"

    private static func tlv(_ tag: String, _ value: String) -> String {
        tag + String(format: "%02d", value.count) + value
    }

    private static func readTLV(_ text: String) -> [(tag: String, value: String)]? {
        var result: [(String, String)] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard let tagEnd = text.index(index, offsetBy: 2, limitedBy: text.endIndex),
                  let lenEnd = text.index(tagEnd, offsetBy: 2, limitedBy: text.endIndex),
                  let length = Int(text[tagEnd..<lenEnd]),
                  let valueEnd = text.index(lenEnd, offsetBy: length, limitedBy: text.endIndex)
            else { return nil }
            result.append((String(text[index..<tagEnd]), String(text[lenEnd..<valueEnd])))
            index = valueEnd
        }
        return result
    }

    /// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF), four uppercase hex digits.
    static func crc16(_ text: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in text.utf8 {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return String(format: "%04X", crc)
    }
}

// MARK: - Wi-Fi

enum WiFiSecurity: String, CaseIterable, Identifiable {
    /// WPA, WPA2 and WPA3 personal all use `T:WPA` in the QR format.
    case wpa, wep, none
    var id: String { rawValue }

    fileprivate var token: String {
        switch self {
        case .wpa:  return "WPA"
        case .wep:  return "WEP"
        case .none: return "nopass"
        }
    }
}

struct WiFiInfo: Equatable {
    let ssid: String
    let password: String
    let security: WiFiSecurity
    let hidden: Bool
}

enum WiFiQR {

    static func build(ssid: String, password: String, security: WiFiSecurity, hidden: Bool) throws -> String {
        guard !ssid.isEmpty else { throw QRPayloadError.ssidRequired }
        guard ssid.utf8.count <= 32 else { throw QRPayloadError.ssidTooLong }
        switch security {
        case .wpa:
            let isHexKey = password.count == 64 && password.allSatisfy { $0.isHexDigit }
            guard isHexKey || (8...63).contains(password.count) else { throw QRPayloadError.passwordLength }
        case .wep:
            guard !password.isEmpty else { throw QRPayloadError.passwordRequired }
        case .none:
            break
        }

        var out = "WIFI:T:\(security.token);S:\(escape(ssid));"
        if security != .none { out += "P:\(escape(password));" }
        if hidden { out += "H:true;" }
        return out + ";"
    }

    static func parse(_ payload: String) -> WiFiInfo? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.uppercased().hasPrefix("WIFI:") else { return nil }

        var fields: [String: String] = [:]
        for part in splitUnescaped(String(text.dropFirst(5)), separator: ";") where !part.isEmpty {
            guard let colon = part.firstIndex(of: ":") else { continue }
            fields[part[..<colon].uppercased()] = unescape(String(part[part.index(after: colon)...]))
        }
        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        let type = (fields["T"] ?? "nopass").uppercased()
        let security: WiFiSecurity = type == "WEP" ? .wep : (type == "NOPASS" || type.isEmpty ? .none : .wpa)
        return WiFiInfo(ssid: ssid,
                        password: fields["P"] ?? "",
                        security: security,
                        hidden: (fields["H"] ?? "").lowercased() == "true")
    }

    /// Backslash, semicolon, comma, colon and double quote are reserved by the format.
    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\;,:\"".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    private static func unescape(_ s: String) -> String {
        var out = ""
        var escaped = false
        for ch in s {
            if escaped { out.append(ch); escaped = false }
            else if ch == "\\" { escaped = true }
            else { out.append(ch) }
        }
        return out
    }

    private static func splitUnescaped(_ s: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaped = false
        for ch in s {
            if escaped { current.append(ch); escaped = false }
            else if ch == "\\" { current.append(ch); escaped = true }
            else if ch == separator { parts.append(current); current = "" }
            else { current.append(ch) }
        }
        parts.append(current)
        return parts
    }
}

// MARK: - vCard

struct ContactCard: Equatable {
    var firstName = ""
    var lastName = ""
    var organization = ""
    var title = ""
    var mobile = ""
    var email = ""
    var website = ""
}

struct VCardInfo: Equatable {
    let name: String
    let organization: String
    let title: String
    let phones: [String]
    let emails: [String]
    let urls: [String]
}

enum VCardQR {

    static func build(_ card: ContactCard) throws -> String {
        let first = card.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = card.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty || !last.isEmpty else { throw QRPayloadError.nameRequired }

        let email = card.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            // Deliberately loose: one "@" with something on each side and a dot after it.
            let parts = email.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."),
                  !email.contains(where: { $0.isWhitespace }) else { throw QRPayloadError.invalidEmail }
        }

        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        lines.append("N:\(escape(last));\(escape(first));;;")
        lines.append("FN:\(escape([first, last].filter { !$0.isEmpty }.joined(separator: " ")))")
        add("ORG", card.organization, to: &lines)
        add("TITLE", card.title, to: &lines)
        add("TEL;TYPE=CELL", card.mobile, to: &lines)
        add("EMAIL", email, to: &lines)
        add("URL", card.website, to: &lines)
        lines.append("END:VCARD")
        // The vCard spec ends lines with CRLF.
        return lines.joined(separator: "\r\n")
    }

    static func parse(_ payload: String) -> VCardInfo? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.uppercased().hasPrefix("BEGIN:VCARD") else { return nil }

        // Unfold continuation lines (a line starting with space / tab continues the previous one).
        var lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }

        var formattedName = "", structuredName = "", org = "", title = ""
        var phones: [String] = [], emails: [String] = [], urls: [String] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let property = line[..<colon].split(separator: ";").first.map { $0.uppercased() } ?? ""
            let value = unescape(String(line[line.index(after: colon)...]))
            switch property {
            case "FN":    formattedName = value
            case "N":
                let p = value.components(separatedBy: ";")
                structuredName = [p.count > 1 ? p[1] : "", p.first ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            case "ORG":   org = value.components(separatedBy: ";").first ?? value
            case "TITLE": title = value
            case "TEL":   phones.append(value)
            case "EMAIL": emails.append(value)
            case "URL":   urls.append(value)
            default:      break
            }
        }
        let name = formattedName.isEmpty ? structuredName : formattedName
        guard !name.isEmpty || !org.isEmpty || !phones.isEmpty || !emails.isEmpty else { return nil }
        return VCardInfo(name: name, organization: org, title: title, phones: phones, emails: emails, urls: urls)
    }

    private static func add(_ property: String, _ value: String, to lines: inout [String]) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty { lines.append("\(property):\(escape(v))") }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func unescape(_ s: String) -> String {
        var out = ""
        var escaped = false
        for ch in s {
            if escaped { out.append(ch == "n" || ch == "N" ? "\n" : ch); escaped = false }
            else if ch == "\\" { escaped = true }
            else { out.append(ch) }
        }
        return out
    }
}

// MARK: - Classification

enum QRPayloadKind: Equatable {
    case vietQR(VietQRInfo)
    case wifi(WiFiInfo)
    case vcard(VCardInfo)
    case text
}

enum QRPayload {
    /// Recognises the structured formats DevPad can generate; everything
    /// else (including plain URLs) is `.text`.
    static func classify(_ payload: String) -> QRPayloadKind {
        if let info = VietQR.parse(payload) { return .vietQR(info) }
        if let info = WiFiQR.parse(payload) { return .wifi(info) }
        if let info = VCardQR.parse(payload) { return .vcard(info) }
        return .text
    }
}
