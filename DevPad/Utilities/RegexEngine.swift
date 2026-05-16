// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  RegexEngine.swift
//  DevPad
//
//  Thin wrapper around NSRegularExpression that exposes the bits the UI
//  cares about — every match with its capture groups, replace with
//  template back-references, and the column index of any pattern syntax
//  error so the user can spot the typo immediately.
//

import Foundation

struct RegexFlags: OptionSet, Hashable {
    let rawValue: Int

    static let caseInsensitive       = RegexFlags(rawValue: 1 << 0)
    static let multiline             = RegexFlags(rawValue: 1 << 1)
    static let dotMatchesLineEndings = RegexFlags(rawValue: 1 << 2)
    static let unicodeWordBoundaries = RegexFlags(rawValue: 1 << 3)

    var nsOptions: NSRegularExpression.Options {
        var opts: NSRegularExpression.Options = []
        if contains(.caseInsensitive)       { opts.insert(.caseInsensitive) }
        if contains(.dotMatchesLineEndings) { opts.insert(.dotMatchesLineSeparators) }
        if contains(.multiline)             { opts.insert(.anchorsMatchLines) }
        if contains(.unicodeWordBoundaries) { opts.insert(.useUnicodeWordBoundaries) }
        return opts
    }
}

struct RegexMatch: Identifiable {
    let id = UUID()
    /// Full-match text.
    let text: String
    /// Range of the full match in the original string.
    let range: Range<String.Index>
    /// `(name, text)` pairs for every capture group, indexed from 1.
    /// `name` is the named group's name if present, otherwise the index as a string.
    let groups: [(name: String, text: String, range: Range<String.Index>?)]
}

enum RegexError: LocalizedError {
    case invalidPattern(String)

    var errorDescription: String? {
        switch self {
        case .invalidPattern(let m): return m
        }
    }
}

enum RegexEngine {

    /// Compile `pattern` with the given `flags`. Throws `RegexError` if the
    /// pattern is malformed; the error message includes the bracketed
    /// reason from `NSRegularExpression` (e.g. "Premature end of regex").
    static func compile(_ pattern: String, flags: RegexFlags) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: flags.nsOptions)
        } catch {
            throw RegexError.invalidPattern(error.localizedDescription)
        }
    }

    /// Run `regex` against `text` and return every match plus its capture groups.
    static func matches(regex: NSRegularExpression,
                        in text: String) -> [RegexMatch] {
        let fullRange = NSRange(text.startIndex..., in: text)
        let results = regex.matches(in: text, options: [], range: fullRange)

        // Build name lookup so named groups get their name instead of the
        // numeric index. NSRegularExpression doesn't expose a public API
        // for this, so we parse the pattern with a small helper.
        let names = namedGroups(in: regex.pattern)

        return results.compactMap { result -> RegexMatch? in
            guard let fullRange = Range(result.range, in: text) else { return nil }
            let fullText = String(text[fullRange])
            var groups: [(name: String, text: String, range: Range<String.Index>?)] = []
            // result.numberOfRanges == 1 (full match) + N capture groups.
            // Skip index 0 since that's the full match itself.
            for i in 1..<result.numberOfRanges {
                let nsRange = result.range(at: i)
                let groupName = names[i] ?? String(i)
                if nsRange.location == NSNotFound {
                    groups.append((name: groupName, text: "", range: nil))
                } else if let r = Range(nsRange, in: text) {
                    groups.append((name: groupName, text: String(text[r]), range: r))
                } else {
                    groups.append((name: groupName, text: "", range: nil))
                }
            }
            return RegexMatch(text: fullText, range: fullRange, groups: groups)
        }
    }

    /// Returns (output, replacedCount). Uses NSRegularExpression's standard
    /// template language: `$1`, `$2`, `$&` for the full match, and `\$` for
    /// a literal dollar sign.
    static func replace(regex: NSRegularExpression,
                        in text: String,
                        with template: String) -> (output: String, replacedCount: Int) {
        let fullRange = NSRange(text.startIndex..., in: text)
        let count = regex.numberOfMatches(in: text, options: [], range: fullRange)
        let mutable = NSMutableString(string: text)
        regex.replaceMatches(in: mutable, options: [], range: fullRange,
                             withTemplate: template)
        return (output: mutable as String, replacedCount: count)
    }

    // MARK: - Named group parsing

    /// Returns a dictionary mapping group-index → group-name for every
    /// `(?<name>…)` or `(?P<name>…)` group in `pattern`. Indices follow the
    /// usual left-paren counting rule (non-capturing groups `(?:…)` and
    /// lookarounds don't take an index).
    private static func namedGroups(in pattern: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var index = 0
        let chars = Array(pattern)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            // Skip escaped char.
            if c == "\\" {
                i += 2
                continue
            }
            // Skip character class — `[` … `]` (which may contain `(`).
            if c == "[" {
                i += 1
                while i < chars.count, chars[i] != "]" {
                    if chars[i] == "\\" { i += 2 } else { i += 1 }
                }
                i += 1
                continue
            }
            if c == "(" {
                // Look at the next 1–3 chars to classify the group.
                let next = i + 1 < chars.count ? chars[i + 1] : Character(" ")
                if next != "?" {
                    // Plain capturing group.
                    index += 1
                } else {
                    let next2 = i + 2 < chars.count ? chars[i + 2] : Character(" ")
                    if next2 == "<" || next2 == "'" {
                        // Named group `(?<name>…)` or `(?'name'…)`.
                        index += 1
                        // Read until matching `>` / `'`.
                        let close: Character = (next2 == "<") ? ">" : "'"
                        var j = i + 3
                        var name = ""
                        while j < chars.count, chars[j] != close {
                            name.append(chars[j])
                            j += 1
                        }
                        result[index] = name
                        i = j + 1
                        continue
                    } else if next2 == "P", i + 3 < chars.count, chars[i + 3] == "<" {
                        // Python-style `(?P<name>…)`.
                        index += 1
                        var j = i + 4
                        var name = ""
                        while j < chars.count, chars[j] != ">" {
                            name.append(chars[j])
                            j += 1
                        }
                        result[index] = name
                        i = j + 1
                        continue
                    }
                    // Otherwise `(?:…)`, `(?=…)`, `(?!…)`, `(?<=…)`, `(?<!…)`,
                    // or inline flags — none take a capture index.
                }
            }
            i += 1
        }
        return result
    }
}
