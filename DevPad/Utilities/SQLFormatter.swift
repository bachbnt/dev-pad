// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  SQLFormatter.swift
//  DevPad
//
//  Lightweight SQL pretty printer.
//
//  Strategy:
//    1. Tokenize the input into keywords, identifiers, literals,
//       comments, operators and punctuation.
//    2. Re-emit the tokens with:
//       - Keywords uppercased.
//       - A line break before each major clause (SELECT, FROM, WHERE,
//         JOIN, GROUP BY, ORDER BY, HAVING, LIMIT, UNION, …).
//       - The contents of a SELECT-list comma-separated on their own
//         line, indented one level beyond the clause.
//       - Indented inner blocks after `(`.
//       - String literals and comments preserved verbatim.
//
//  This is intentionally a "good enough" implementation — it covers the
//  common queries you'd paste into a developer scratchpad. It does not
//  attempt to validate SQL or handle every dialect's quirks.
//

import Foundation

enum SQLFormatterError: LocalizedError {
    case empty
    var errorDescription: String? {
        switch self {
        case .empty: return "Input is empty."
        }
    }
}

struct SQLFormatter {

    /// Reserved words we recognise. Matched case-insensitively; emitted in
    /// upper case. (Function names like COUNT/SUM/AVG are also listed so
    /// they end up uppercase even when used as identifiers.)
    static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AS", "AND", "OR", "NOT", "IN", "EXISTS",
        "BETWEEN", "LIKE", "ILIKE", "IS", "NULL", "TRUE", "FALSE",
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "ON", "USING",
        "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "FETCH", "FIRST", "NEXT", "ROWS", "ONLY",
        "UNION", "ALL", "INTERSECT", "EXCEPT", "DISTINCT",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "CREATE", "TABLE", "ALTER", "ADD", "DROP", "INDEX",
        "VIEW", "WITH", "RETURNING", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
        "CONSTRAINT", "UNIQUE", "CHECK", "DEFAULT", "CASCADE", "RESTRICT",
        "CASE", "WHEN", "THEN", "ELSE", "END",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF",
        "ASC", "DESC", "OVER", "PARTITION", "ROW_NUMBER", "RANK", "DENSE_RANK",
        "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
        "IF", "EXISTS", "INT", "INTEGER", "BIGINT", "SMALLINT", "VARCHAR",
        "TEXT", "BOOLEAN", "BOOL", "DATE", "TIME", "TIMESTAMP", "JSON", "JSONB", "UUID"
    ]

    /// Keywords that start a top-level clause and should be preceded by a
    /// newline at the current indent level.
    private static let clauseStarters: Set<String> = [
        "SELECT", "FROM", "WHERE", "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET",
        "UNION", "INTERSECT", "EXCEPT", "VALUES", "SET", "RETURNING",
        "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "DROP",
        "WITH", "ON"
    ]

    /// Keywords that introduce a JOIN — also force a newline.
    private static let joinStarters: Set<String> = [
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS"
    ]

    /// Boolean glue. Goes on its own line at +1 indent inside WHERE.
    private static let boolGlue: Set<String> = ["AND", "OR"]

    // MARK: - Public API

    static func format(_ input: String, indent: Int = 2) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SQLFormatterError.empty }
        let tokens = tokenize(trimmed)
        return emit(tokens, indentSpaces: max(1, indent))
    }

    static func minify(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SQLFormatterError.empty }
        let tokens = tokenize(trimmed)

        var out = ""
        for (i, tok) in tokens.enumerated() {
            switch tok.kind {
            case .lineComment, .blockComment:
                continue
            case .punctuation where tok.text == "," || tok.text == ";":
                out += tok.text
            case .punctuation:
                out += tok.text
            default:
                if !out.isEmpty {
                    let last = out.last!
                    let needSpace = !"( ".contains(last)
                        && tok.text.first.map { !"),;".contains($0) } ?? true
                    if needSpace { out += " " }
                }
                out += tok.kind == .keyword ? tok.text.uppercased() : tok.text
            }
            _ = i
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tokenization

    private enum TokenKind {
        case keyword
        case identifier
        case number
        case string
        case lineComment
        case blockComment
        case punctuation   // ( ) , ;
        case op            // = < > <= >= <> ! + - * / %
    }

    private struct Token {
        let kind: TokenKind
        let text: String
    }

    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        let n = chars.count

        while i < n {
            let c = chars[i]

            // skip whitespace
            if c.isWhitespace { i += 1; continue } // skip whitespace

            // line comment: -- ... \n
            if c == "-" && i + 1 < n && chars[i + 1] == "-" {
                var end = i + 2
                while end < n && chars[end] != "\n" { end += 1 }
                tokens.append(Token(kind: .lineComment, text: String(chars[i..<end])))
                i = end
                continue
            }

            // block comment: /* ... */
            if c == "/" && i + 1 < n && chars[i + 1] == "*" {
                var end = i + 2
                while end + 1 < n && !(chars[end] == "*" && chars[end + 1] == "/") { end += 1 }
                end = min(end + 2, n)
                tokens.append(Token(kind: .blockComment, text: String(chars[i..<end])))
                i = end
                continue
            }

            // string literal
            if c == "'" || c == "\"" {
                let quote = c
                var end = i + 1
                while end < n {
                    if chars[end] == quote {
                        // SQL escaped quote ('' or "")
                        if end + 1 < n && chars[end + 1] == quote {
                            end += 2
                            continue
                        }
                        end += 1
                        break
                    }
                    end += 1
                }
                tokens.append(Token(kind: .string, text: String(chars[i..<end])))
                i = end
                continue
            }

            // number
            if c.isNumber || (c == "." && i + 1 < n && chars[i + 1].isNumber) {
                var end = i + 1
                while end < n && (chars[end].isNumber || chars[end] == ".") { end += 1 }
                tokens.append(Token(kind: .number, text: String(chars[i..<end])))
                i = end
                continue
            }

            // identifier / keyword (also handles $-prefixed parameters)
            if c.isLetter || c == "_" || c == "$" || c == "@" || c == "`" {
                var end = i + 1
                while end < n && (chars[end].isLetter || chars[end].isNumber
                        || chars[end] == "_" || chars[end] == "$" || chars[end] == ".") {
                    end += 1
                }
                let text = String(chars[i..<end])
                if keywords.contains(text.uppercased()) {
                    tokens.append(Token(kind: .keyword, text: text.uppercased()))
                } else {
                    tokens.append(Token(kind: .identifier, text: text))
                }
                i = end
                continue
            }

            // punctuation
            if "(),;".contains(c) {
                tokens.append(Token(kind: .punctuation, text: String(c)))
                i += 1
                continue
            }

            // multi-char operators: <=, >=, <>, !=, ||
            if "=<>!+-*/%|".contains(c) {
                var end = i + 1
                while end < n && "=<>!+-*/%|".contains(chars[end]) { end += 1 }
                tokens.append(Token(kind: .op, text: String(chars[i..<end])))
                i = end
                continue
            }

            // unknown — skip
            i += 1
        }

        return tokens
    }

    // MARK: - Emission

    private static func emit(_ tokens: [Token], indentSpaces: Int) -> String {
        let pad = String(repeating: " ", count: indentSpaces)
        var output = ""
        var indentLevel = 0
        var parenStack: [Int] = []           // indent level pushed at each "("
        var inSelectList = false
        var afterClauseKeyword: Bool = false

        func indent(_ extra: Int = 0) -> String {
            String(repeating: pad, count: max(0, indentLevel + extra))
        }

        func appendNewlineIndent(_ extra: Int = 0) {
            if !output.isEmpty, !output.hasSuffix("\n") {
                // Trim trailing space then newline.
                while output.hasSuffix(" ") { output.removeLast() }
                output += "\n"
            }
            output += indent(extra)
        }

        func appendSpaceIfNeeded() {
            if output.isEmpty { return }
            if output.hasSuffix(" ") || output.hasSuffix("\n") || output.hasSuffix("(") { return }
            output += " "
        }

        for token in tokens {
            switch token.kind {

            case .lineComment, .blockComment:
                appendNewlineIndent()
                output += token.text
                output += "\n"
                output += indent()

            case .keyword:
                let kw = token.text
                if clauseStarters.contains(kw) {
                    appendNewlineIndent()
                    output += kw
                    afterClauseKeyword = true
                    inSelectList = (kw == "SELECT" || kw == "VALUES" || kw == "SET" || kw == "RETURNING")
                } else if joinStarters.contains(kw) {
                    appendNewlineIndent()
                    output += kw
                    afterClauseKeyword = false
                    inSelectList = false
                } else if boolGlue.contains(kw) {
                    appendNewlineIndent(1)
                    output += kw
                    afterClauseKeyword = false
                } else {
                    appendSpaceIfNeeded()
                    output += kw
                    afterClauseKeyword = false
                }

            case .identifier, .number, .string:
                appendSpaceIfNeeded()
                output += token.text
                afterClauseKeyword = false

            case .op:
                appendSpaceIfNeeded()
                output += token.text
                afterClauseKeyword = false

            case .punctuation:
                switch token.text {
                case "(":
                    // Stick to previous token (function call / subquery start).
                    while output.hasSuffix(" ") { output.removeLast() }
                    output += "("
                    parenStack.append(indentLevel)
                    indentLevel += 1
                    afterClauseKeyword = false
                case ")":
                    indentLevel = parenStack.popLast() ?? max(0, indentLevel - 1)
                    while output.hasSuffix(" ") { output.removeLast() }
                    output += ")"
                    afterClauseKeyword = false
                case ",":
                    while output.hasSuffix(" ") { output.removeLast() }
                    output += ","
                    // In a SELECT/VALUES/SET list, break to the next column.
                    // Inside function arguments (parenStack non-empty *and*
                    // we're not currently a top-level select list), keep
                    // commas inline.
                    if inSelectList, parenStack.isEmpty {
                        output += "\n" + indent(1)
                    } else if parenStack.isEmpty {
                        output += "\n" + indent()
                    } else {
                        output += " "
                    }
                case ";":
                    while output.hasSuffix(" ") { output.removeLast() }
                    output += ";\n"
                    indentLevel = 0
                    parenStack.removeAll()
                    inSelectList = false
                default:
                    output += token.text
                }
            }
        }

        // After a clause keyword like SELECT, push the first column to its
        // own indented line so list items align.
        // (We handle this lazily here: trim trailing whitespace and add a
        // newline + indent if the next non-keyword is going to be the first
        // column. But that requires lookahead, which we skip — most queries
        // still read fine because columns then continue with `,` breaks.)

        _ = afterClauseKeyword

        return output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " \n", with: "\n")
    }
}
