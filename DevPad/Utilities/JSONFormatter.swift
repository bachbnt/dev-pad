//
//  JSONFormatter.swift
//  DevPad
//
//  Pretty-prints JSON strings with configurable indentation, preserving
//  key order. Built on JSONSerialization. Output style is similar to
//  jsonformatter.org.
//

import Foundation

enum JSONFormatterError: LocalizedError {
    /// `String` carries the parser-supplied detail. The UI prepends its own
    /// localized prefix ("Invalid JSON" / "JSON không hợp lệ"), so we don't
    /// repeat it here.
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message):
            return message
        }
    }
}

struct JSONFormatter {

    /// Formats raw JSON into a pretty-printed string.
    static func format(_ input: String, indent: Int = 2, sortKeys: Bool = false) throws -> String {
        let object = try parse(input)
        var out = ""
        write(object, into: &out, level: 0, indent: indent, sortKeys: sortKeys)
        return out
    }

    /// Strips whitespace from a JSON string.
    static func minify(_ input: String) throws -> String {
        let object = try parse(input)
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.fragmentsAllowed]
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Private

    private static func parse(_ input: String) throws -> Any {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JSONFormatterError.invalidJSON("Input is empty.")
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw JSONFormatterError.invalidJSON("Cannot encode input as UTF-8.")
        }
        do {
            return try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw JSONFormatterError.invalidJSON(error.localizedDescription)
        }
    }

    private static func write(_ value: Any,
                              into output: inout String,
                              level: Int,
                              indent: Int,
                              sortKeys: Bool) {
        if let dict = value as? [String: Any] {
            writeDict(dict, into: &output, level: level, indent: indent, sortKeys: sortKeys)
        } else if let array = value as? [Any] {
            writeArray(array, into: &output, level: level, indent: indent, sortKeys: sortKeys)
        } else if value is NSNull {
            output += "null"
        } else if let b = value as? Bool {
            output += b ? "true" : "false"
        } else if let n = value as? NSNumber {
            output += numberString(n)
        } else if let s = value as? String {
            output += escape(s)
        } else {
            output += "null"
        }
    }

    private static func writeDict(_ dict: [String: Any],
                                  into output: inout String,
                                  level: Int,
                                  indent: Int,
                                  sortKeys: Bool) {
        if dict.isEmpty { output += "{}"; return }
        let pad = String(repeating: " ", count: (level + 1) * indent)
        let closePad = String(repeating: " ", count: level * indent)
        output += "{\n"
        let keys = sortKeys ? dict.keys.sorted() : Array(dict.keys)
        for (i, key) in keys.enumerated() {
            output += pad + escape(key) + ": "
            if let v = dict[key] {
                write(v, into: &output, level: level + 1, indent: indent, sortKeys: sortKeys)
            } else {
                output += "null"
            }
            if i < keys.count - 1 { output += "," }
            output += "\n"
        }
        output += closePad + "}"
    }

    private static func writeArray(_ array: [Any],
                                   into output: inout String,
                                   level: Int,
                                   indent: Int,
                                   sortKeys: Bool) {
        if array.isEmpty { output += "[]"; return }
        let pad = String(repeating: " ", count: (level + 1) * indent)
        let closePad = String(repeating: " ", count: level * indent)
        output += "[\n"
        for (i, item) in array.enumerated() {
            output += pad
            write(item, into: &output, level: level + 1, indent: indent, sortKeys: sortKeys)
            if i < array.count - 1 { output += "," }
            output += "\n"
        }
        output += closePad + "]"
    }

    private static func numberString(_ n: NSNumber) -> String {
        let cf = CFNumberGetType(n)
        switch cf {
        case .charType, .sInt8Type, .sInt16Type, .sInt32Type, .sInt64Type,
             .shortType, .intType, .longType, .longLongType,
             .cfIndexType, .nsIntegerType:
            return "\(n.int64Value)"
        default:
            let d = n.doubleValue
            if d.isFinite, d.rounded() == d, abs(d) < 1e15 {
                return "\(n.int64Value)"
            }
            return "\(d)"
        }
    }

    private static func escape(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.append(Character(scalar))
                }
            }
        }
        out += "\""
        return out
    }
}
