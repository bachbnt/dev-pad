// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  JSONFormatter.swift
//  DevPad
//
//  Pretty-prints and minifies JSON with configurable indentation. Uses its
//  own strict (RFC 8259) parser instead of JSONSerialization because that
//  one returns an unordered dictionary: output key order changed from run to
//  run, duplicate keys were silently collapsed, and numbers went through
//  Double (so 12345678901234567890 and 1.0 didn't survive). Here objects keep
//  their key order and numbers keep their exact source text. Output style is
//  similar to jsonformatter.org.
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

    /// Formats raw JSON into a pretty-printed string. Keys keep their input
    /// order unless `sortKeys` is true. `useTabs` indents with one tab per
    /// level (`indent` is then ignored).
    static func format(_ input: String,
                       indent: Int = 2,
                       useTabs: Bool = false,
                       sortKeys: Bool = false) throws -> String {
        let value = try parse(input)
        let unit = useTabs ? "\t" : String(repeating: " ", count: max(0, indent))
        var out = ""
        write(value, into: &out, level: 0, unit: unit, sortKeys: sortKeys)
        return out
    }

    /// Strips insignificant whitespace from a JSON string; key order is kept.
    static func minify(_ input: String) throws -> String {
        let value = try parse(input)
        var out = ""
        writeCompact(value, into: &out)
        return out
    }

    // MARK: - Model

    /// Order-preserving JSON tree. Numbers stay as their source text.
    private indirect enum Value {
        case object([(key: String, value: Value)])
        case array([Value])
        case string(String)
        case number(String)
        case bool(Bool)
        case null
    }

    // MARK: - Parser

    private static func parse(_ input: String) throws -> Value {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw JSONFormatterError.invalidJSON("Input is empty.")
        }
        var parser = Parser(bytes: Array(trimmed.utf8))
        parser.skipBOM()
        return try parser.parseDocument()
    }

    private struct Parser {
        let bytes: [UInt8]
        var pos = 0

        /// Matches JSONSerialization's own nesting limit; also keeps a stray
        /// `[[[[…` paste from overflowing the stack.
        private static let maxDepth = 512

        init(bytes: [UInt8]) { self.bytes = bytes }

        mutating func skipBOM() {
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { pos = 3 }
        }

        mutating func parseDocument() throws -> Value {
            skipWhitespace()
            let value = try parseValue(depth: 0)
            skipWhitespace()
            if pos < bytes.count { throw unexpected("after the end of the JSON value") }
            return value
        }

        // MARK: Values

        private mutating func parseValue(depth: Int) throws -> Value {
            guard depth <= Parser.maxDepth else {
                throw fail("Nesting is deeper than \(Parser.maxDepth) levels")
            }
            guard pos < bytes.count else { throw fail("Unexpected end of input, expected a value") }
            switch bytes[pos] {
            case UInt8(ascii: "{"): return try parseObject(depth: depth)
            case UInt8(ascii: "["): return try parseArray(depth: depth)
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
            default: throw unexpected("where a value is expected")
            }
        }

        private mutating func parseObject(depth: Int) throws -> Value {
            pos += 1 // {
            var members: [(key: String, value: Value)] = []
            skipWhitespace()
            if peek() == UInt8(ascii: "}") { pos += 1; return .object(members) }
            while true {
                skipWhitespace()
                guard peek() == UInt8(ascii: "\"") else { throw unexpected("where an object key (a string) is expected") }
                let key = try parseString()
                skipWhitespace()
                guard peek() == UInt8(ascii: ":") else { throw unexpected("where ':' is expected after an object key") }
                pos += 1
                skipWhitespace()
                members.append((key, try parseValue(depth: depth + 1)))
                skipWhitespace()
                switch peek() {
                case UInt8(ascii: ","): pos += 1
                case UInt8(ascii: "}"): pos += 1; return .object(members)
                default: throw unexpected("where ',' or '}' is expected")
                }
            }
        }

        private mutating func parseArray(depth: Int) throws -> Value {
            pos += 1 // [
            var items: [Value] = []
            skipWhitespace()
            if peek() == UInt8(ascii: "]") { pos += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                switch peek() {
                case UInt8(ascii: ","): pos += 1
                case UInt8(ascii: "]"): pos += 1; return .array(items)
                default: throw unexpected("where ',' or ']' is expected")
                }
            }
        }

        // MARK: Strings

        private mutating func parseString() throws -> String {
            pos += 1 // opening quote
            var scalars = String.UnicodeScalarView()
            var runStart = pos

            func flushRun(_ p: inout Parser, upTo end: Int) {
                if end > runStart {
                    scalars.append(contentsOf: String(decoding: p.bytes[runStart..<end], as: UTF8.self).unicodeScalars)
                }
            }

            while pos < bytes.count {
                let b = bytes[pos]
                if b == UInt8(ascii: "\"") {
                    flushRun(&self, upTo: pos)
                    pos += 1
                    return String(scalars)
                }
                if b < 0x20 { throw fail("Unescaped control character in string at \(location())") }
                if b == UInt8(ascii: "\\") {
                    flushRun(&self, upTo: pos)
                    pos += 1
                    guard pos < bytes.count else { break }
                    switch bytes[pos] {
                    case UInt8(ascii: "\""): scalars.append("\""); pos += 1
                    case UInt8(ascii: "\\"): scalars.append("\\"); pos += 1
                    case UInt8(ascii: "/"):  scalars.append("/");  pos += 1
                    case UInt8(ascii: "b"):  scalars.append("\u{08}"); pos += 1
                    case UInt8(ascii: "f"):  scalars.append("\u{0C}"); pos += 1
                    case UInt8(ascii: "n"):  scalars.append("\n"); pos += 1
                    case UInt8(ascii: "r"):  scalars.append("\r"); pos += 1
                    case UInt8(ascii: "t"):  scalars.append("\t"); pos += 1
                    case UInt8(ascii: "u"):
                        pos += 1
                        scalars.append(try parseUnicodeEscape())
                    default: throw unexpected("in an escape sequence")
                    }
                    runStart = pos
                    continue
                }
                pos += 1
            }
            throw fail("Unterminated string")
        }

        /// After `\u`: four hex digits, combining a surrogate pair when needed.
        private mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
            let first = try readHex4()
            if (0xD800...0xDBFF).contains(first) {
                guard pos + 1 < bytes.count, bytes[pos] == UInt8(ascii: "\\"), bytes[pos + 1] == UInt8(ascii: "u") else {
                    throw fail("Unpaired high surrogate \\u\(String(first, radix: 16)) at \(location())")
                }
                pos += 2
                let second = try readHex4()
                guard (0xDC00...0xDFFF).contains(second) else {
                    throw fail("Invalid low surrogate \\u\(String(second, radix: 16)) at \(location())")
                }
                let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                guard let scalar = Unicode.Scalar(combined) else { throw fail("Invalid surrogate pair at \(location())") }
                return scalar
            }
            if (0xDC00...0xDFFF).contains(first) {
                throw fail("Unpaired low surrogate \\u\(String(first, radix: 16)) at \(location())")
            }
            guard let scalar = Unicode.Scalar(first) else { throw fail("Invalid unicode escape at \(location())") }
            return scalar
        }

        private mutating func readHex4() throws -> UInt32 {
            guard pos + 4 <= bytes.count else { throw fail("Truncated \\u escape") }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let b = bytes[pos]
                let digit: UInt32
                switch b {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(b - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(b - UInt8(ascii: "a")) + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(b - UInt8(ascii: "A")) + 10
                default: throw unexpected("in a \\u escape (expected a hex digit)")
                }
                value = value << 4 | digit
                pos += 1
            }
            return value
        }

        // MARK: Numbers / literals

        /// Validates `-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?` and returns the
        /// source text untouched.
        private mutating func parseNumber() throws -> String {
            let start = pos
            if peek() == UInt8(ascii: "-") { pos += 1 }
            guard let first = peek(), isDigit(first) else { throw unexpected("in a number (expected a digit)") }
            if first == UInt8(ascii: "0") {
                pos += 1
                if let next = peek(), isDigit(next) { throw fail("Leading zeros are not allowed in numbers, at \(location())") }
            } else {
                while let d = peek(), isDigit(d) { pos += 1 }
            }
            if peek() == UInt8(ascii: ".") {
                pos += 1
                guard let d = peek(), isDigit(d) else { throw unexpected("in a number (expected digits after '.')") }
                while let d = peek(), isDigit(d) { pos += 1 }
            }
            if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
                pos += 1
                if peek() == UInt8(ascii: "+") || peek() == UInt8(ascii: "-") { pos += 1 }
                guard let d = peek(), isDigit(d) else { throw unexpected("in a number (expected exponent digits)") }
                while let d = peek(), isDigit(d) { pos += 1 }
            }
            return String(decoding: bytes[start..<pos], as: UTF8.self)
        }

        private mutating func expect(_ literal: String) throws {
            let lit = Array(literal.utf8)
            guard pos + lit.count <= bytes.count, Array(bytes[pos..<(pos + lit.count)]) == lit else {
                throw unexpected("(expected '\(literal)')")
            }
            pos += lit.count
        }

        // MARK: Helpers

        private func peek() -> UInt8? { pos < bytes.count ? bytes[pos] : nil }

        private func isDigit(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") }

        private mutating func skipWhitespace() {
            while pos < bytes.count {
                switch bytes[pos] {
                case 0x20, 0x09, 0x0A, 0x0D: pos += 1
                default: return
                }
            }
        }

        private func fail(_ message: String) -> JSONFormatterError {
            .invalidJSON(message)
        }

        private func unexpected(_ context: String) -> JSONFormatterError {
            guard pos < bytes.count else {
                return .invalidJSON("Unexpected end of input \(context)")
            }
            let scalar = String(decoding: bytes[pos..<min(bytes.count, pos + 4)], as: UTF8.self).first.map(String.init) ?? "?"
            return .invalidJSON("Unexpected character '\(scalar)' \(context), at \(location())")
        }

        /// 1-based "line L, column C" of the current position.
        private func location() -> String {
            var line = 1, column = 1
            for b in bytes[0..<min(pos, bytes.count)] {
                if b == 0x0A { line += 1; column = 1 } else if b & 0xC0 != 0x80 { column += 1 }
            }
            return "line \(line), column \(column)"
        }
    }

    // MARK: - Writer

    private static func write(_ value: Value,
                              into output: inout String,
                              level: Int,
                              unit: String,
                              sortKeys: Bool) {
        switch value {
        case .object(let members):
            if members.isEmpty { output += "{}"; return }
            let pad = String(repeating: unit, count: level + 1)
            let closePad = String(repeating: unit, count: level)
            let ordered = sortKeys ? members.sorted { $0.key < $1.key } : members
            output += "{\n"
            for (i, member) in ordered.enumerated() {
                output += pad + escape(member.key) + ": "
                write(member.value, into: &output, level: level + 1, unit: unit, sortKeys: sortKeys)
                if i < ordered.count - 1 { output += "," }
                output += "\n"
            }
            output += closePad + "}"
        case .array(let items):
            if items.isEmpty { output += "[]"; return }
            let pad = String(repeating: unit, count: level + 1)
            let closePad = String(repeating: unit, count: level)
            output += "[\n"
            for (i, item) in items.enumerated() {
                output += pad
                write(item, into: &output, level: level + 1, unit: unit, sortKeys: sortKeys)
                if i < items.count - 1 { output += "," }
                output += "\n"
            }
            output += closePad + "]"
        default:
            writeScalar(value, into: &output)
        }
    }

    private static func writeCompact(_ value: Value, into output: inout String) {
        switch value {
        case .object(let members):
            output += "{"
            for (i, member) in members.enumerated() {
                if i > 0 { output += "," }
                output += escape(member.key) + ":"
                writeCompact(member.value, into: &output)
            }
            output += "}"
        case .array(let items):
            output += "["
            for (i, item) in items.enumerated() {
                if i > 0 { output += "," }
                writeCompact(item, into: &output)
            }
            output += "]"
        default:
            writeScalar(value, into: &output)
        }
    }

    private static func writeScalar(_ value: Value, into output: inout String) {
        switch value {
        case .string(let s): output += escape(s)
        case .number(let n): output += n
        case .bool(let b):   output += b ? "true" : "false"
        case .null:          output += "null"
        case .object, .array: break // handled by the callers
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
