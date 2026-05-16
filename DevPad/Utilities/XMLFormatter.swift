// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  XMLFormatter.swift
//  DevPad
//
//  Lightweight pretty-printer for XML strings. Tokenizes the input into
//  declarations, comments, CDATA, processing instructions, tags, and text,
//  then re-emits with proper indentation.
//
//  The intent is to behave like xmlformatter.org / jsonformatter.org for
//  the vast majority of well-formed inputs. It does NOT validate XML.
//

import Foundation

enum XMLFormatterError: LocalizedError {
    /// Detail only — the UI adds its own localized prefix
    /// ("Invalid XML" / "XML không hợp lệ").
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let m): return m
        }
    }
}

struct XMLFormatter {

    static func format(_ input: String, indent: Int = 2) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw XMLFormatterError.invalid("Input is empty.")
        }

        let tokens = try tokenize(trimmed)
        guard !tokens.isEmpty else {
            throw XMLFormatterError.invalid("No tokens parsed.")
        }

        var output = ""
        var level = 0
        let unit = String(repeating: " ", count: indent)

        // Track previous token to decide newlines around mixed content.
        var previous: Token?

        func pad(_ lvl: Int) -> String { String(repeating: unit, count: max(0, lvl)) }

        for (i, token) in tokens.enumerated() {
            switch token {
            case .declaration(let s),
                 .processingInstruction(let s),
                 .comment(let s),
                 .doctype(let s),
                 .cdata(let s):
                if !output.isEmpty, !output.hasSuffix("\n") { output += "\n" }
                output += pad(level) + s

            case .openTag(let s, let isSelfClosing):
                if !output.isEmpty, !output.hasSuffix("\n") { output += "\n" }
                output += pad(level) + s
                if !isSelfClosing { level += 1 }

            case .closeTag(let s):
                level = max(0, level - 1)
                // If previous was inline text (single text token between matching open and close),
                // append on the same line.
                if case .text? = previous,
                   i >= 2,
                   case .openTag(_, let selfClosing) = tokens[i - 2],
                   selfClosing == false {
                    output += s
                } else {
                    if !output.hasSuffix("\n") { output += "\n" }
                    output += pad(level) + s
                }

            case .text(let s):
                let textTrim = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !textTrim.isEmpty else { continue }
                // If the previous token was an openTag, keep text on the same line
                // (inline content like <tag>value</tag>).
                if case .openTag? = previous {
                    output += textTrim
                } else {
                    if !output.hasSuffix("\n") { output += "\n" }
                    output += pad(level) + textTrim
                }
            }
            previous = token
        }

        return output
    }

    // MARK: - Tokenization

    private enum Token {
        case declaration(String)         // <?xml ... ?>
        case processingInstruction(String) // <?... ?>
        case comment(String)             // <!-- ... -->
        case cdata(String)               // <![CDATA[...]]>
        case doctype(String)             // <!DOCTYPE ...>
        case openTag(String, Bool)       // <tag ...>  or  <tag .../>  (Bool = isSelfClosing)
        case closeTag(String)            // </tag>
        case text(String)
    }

    private static func tokenize(_ input: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        let n = chars.count

        while i < n {
            if chars[i] == "<" {
                // Find matching close character `>`, accounting for quoted attributes.
                if i + 3 < n, chars[i+1] == "!", chars[i+2] == "-", chars[i+3] == "-" {
                    // Comment.
                    let end = findRange(chars, "-->", from: i + 4) ?? n
                    let s = String(chars[i..<min(end + 3, n)])
                    tokens.append(.comment(s))
                    i = min(end + 3, n)
                } else if i + 8 < n,
                          String(chars[i..<i+9]) == "<![CDATA[" {
                    // CDATA.
                    let end = findRange(chars, "]]>", from: i + 9) ?? n
                    let s = String(chars[i..<min(end + 3, n)])
                    tokens.append(.cdata(s))
                    i = min(end + 3, n)
                } else if i + 1 < n, chars[i+1] == "?" {
                    // Declaration / processing instruction.
                    let end = findRange(chars, "?>", from: i + 2) ?? n
                    let s = String(chars[i..<min(end + 2, n)])
                    if s.lowercased().hasPrefix("<?xml") {
                        tokens.append(.declaration(s))
                    } else {
                        tokens.append(.processingInstruction(s))
                    }
                    i = min(end + 2, n)
                } else if i + 1 < n, chars[i+1] == "!" {
                    // DOCTYPE or other ! declaration. Find first `>` not in quotes, accounting for nested [].
                    let end = findEndOfDoctype(chars, from: i + 2) ?? n
                    let s = String(chars[i...min(end, n - 1)])
                    tokens.append(.doctype(s))
                    i = min(end + 1, n)
                } else {
                    // Regular tag — find `>` that is not inside quotes.
                    var j = i + 1
                    var inQuote: Character? = nil
                    while j < n {
                        let c = chars[j]
                        if let q = inQuote {
                            if c == q { inQuote = nil }
                        } else if c == "\"" || c == "'" {
                            inQuote = c
                        } else if c == ">" {
                            break
                        }
                        j += 1
                    }
                    if j >= n {
                        throw XMLFormatterError.invalid("Unclosed tag.")
                    }
                    let raw = String(chars[i...j])
                    if raw.hasPrefix("</") {
                        tokens.append(.closeTag(raw))
                    } else {
                        let isSelfClosing = raw.hasSuffix("/>")
                        tokens.append(.openTag(raw, isSelfClosing))
                    }
                    i = j + 1
                }
            } else {
                // Text up to next `<`.
                var j = i
                while j < n, chars[j] != "<" { j += 1 }
                let s = String(chars[i..<j])
                tokens.append(.text(s))
                i = j
            }
        }

        return tokens
    }

    private static func findRange(_ chars: [Character], _ needle: String, from start: Int) -> Int? {
        let needleChars = Array(needle)
        let n = chars.count
        let m = needleChars.count
        guard m > 0, start <= n - m else { return nil }
        var i = start
        while i <= n - m {
            var ok = true
            for k in 0..<m {
                if chars[i + k] != needleChars[k] { ok = false; break }
            }
            if ok { return i }
            i += 1
        }
        return nil
    }

    private static func findEndOfDoctype(_ chars: [Character], from start: Int) -> Int? {
        var i = start
        var bracketDepth = 0
        var inQuote: Character? = nil
        while i < chars.count {
            let c = chars[i]
            if let q = inQuote {
                if c == q { inQuote = nil }
            } else if c == "\"" || c == "'" {
                inQuote = c
            } else if c == "[" {
                bracketDepth += 1
            } else if c == "]" {
                bracketDepth = max(0, bracketDepth - 1)
            } else if c == ">", bracketDepth == 0 {
                return i
            }
            i += 1
        }
        return nil
    }
}
