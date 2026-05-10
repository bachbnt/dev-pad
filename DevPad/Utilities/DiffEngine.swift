//
//  DiffEngine.swift
//  DevPad
//
//  Computes a line-by-line diff between two strings using LCS, plus an
//  in-line word-level diff (used to highlight just the changed substring
//  inside a modified line — e.g. "đoạn văn A" vs "đoạn văn B" should
//  highlight only "A" / "B", like diffchecker.com).
//

import Foundation

enum DiffOp {
    case equal       // both sides identical
    case modified    // both sides present but different
    case removed     // present only on left  (deletion)
    case added       // present only on right (insertion)
}

struct DiffRow: Identifiable {
    let id = UUID()
    let leftLineNumber: Int?    // nil if this row has no left line
    let rightLineNumber: Int?   // nil if this row has no right line
    let leftText: String?
    let rightText: String?
    let op: DiffOp
}

struct InlineSegment: Identifiable {
    enum Kind { case equal, removed, added }
    let id = UUID()
    let text: String
    let kind: Kind
}

struct DiffEngine {

    // MARK: - Line-level diff

    /// Compares two texts line-by-line and returns rows aligned for side-by-side display.
    /// Adjacent removed/added rows are merged into a single `.modified` row when possible.
    static func diff(left: String, right: String) -> [DiffRow] {
        let leftLines = left.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let rightLines = right.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let lcs = lcsTable(leftLines, rightLines)

        var ops: [(DiffOp, Int?, Int?)] = []
        var i = leftLines.count
        var j = rightLines.count
        while i > 0 && j > 0 {
            if leftLines[i - 1] == rightLines[j - 1] {
                ops.append((.equal, i - 1, j - 1))
                i -= 1; j -= 1
            } else if lcs[i - 1][j] >= lcs[i][j - 1] {
                ops.append((.removed, i - 1, nil))
                i -= 1
            } else {
                ops.append((.added, nil, j - 1))
                j -= 1
            }
        }
        while i > 0 { ops.append((.removed, i - 1, nil)); i -= 1 }
        while j > 0 { ops.append((.added, nil, j - 1)); j -= 1 }
        ops.reverse()

        var rows: [DiffRow] = []
        var k = 0
        while k < ops.count {
            let (op, li, ri) = ops[k]
            switch op {
            case .equal:
                let lIdx = li ?? 0
                let rIdx = ri ?? 0
                rows.append(DiffRow(
                    leftLineNumber: lIdx + 1,
                    rightLineNumber: rIdx + 1,
                    leftText: leftLines[lIdx],
                    rightText: rightLines[rIdx],
                    op: .equal
                ))
                k += 1
            case .removed:
                var removedIdxs: [Int] = []
                while k < ops.count, case .removed = ops[k].0 {
                    if let l = ops[k].1 { removedIdxs.append(l) }
                    k += 1
                }
                var addedIdxs: [Int] = []
                while k < ops.count, case .added = ops[k].0 {
                    if let r = ops[k].2 { addedIdxs.append(r) }
                    k += 1
                }
                let pairCount = min(removedIdxs.count, addedIdxs.count)
                for p in 0..<pairCount {
                    let lIdx = removedIdxs[p]
                    let rIdx = addedIdxs[p]
                    rows.append(DiffRow(
                        leftLineNumber: lIdx + 1,
                        rightLineNumber: rIdx + 1,
                        leftText: leftLines[lIdx],
                        rightText: rightLines[rIdx],
                        op: .modified
                    ))
                }
                for p in pairCount..<removedIdxs.count {
                    let lIdx = removedIdxs[p]
                    rows.append(DiffRow(
                        leftLineNumber: lIdx + 1,
                        rightLineNumber: nil,
                        leftText: leftLines[lIdx],
                        rightText: nil,
                        op: .removed
                    ))
                }
                for p in pairCount..<addedIdxs.count {
                    let rIdx = addedIdxs[p]
                    rows.append(DiffRow(
                        leftLineNumber: nil,
                        rightLineNumber: rIdx + 1,
                        leftText: nil,
                        rightText: rightLines[rIdx],
                        op: .added
                    ))
                }
            case .added:
                let rIdx = ri ?? 0
                rows.append(DiffRow(
                    leftLineNumber: nil,
                    rightLineNumber: rIdx + 1,
                    leftText: nil,
                    rightText: rightLines[rIdx],
                    op: .added
                ))
                k += 1
            case .modified:
                k += 1
            }
        }

        return rows
    }

    // MARK: - Inline (word/char) diff inside a modified row

    /// Returns segmented arrays for the left and right strings so that the UI
    /// can highlight only the parts that actually changed within a modified line.
    /// Tokenization keeps runs of letters/digits as one token and emits each
    /// punctuation/whitespace character as its own token, so a one-character
    /// edit produces a single-character highlight (matching diffchecker.com).
    static func inlineDiff(_ left: String, _ right: String) -> (left: [InlineSegment], right: [InlineSegment]) {
        let l = tokenizeForInlineDiff(left)
        let r = tokenizeForInlineDiff(right)

        // Fast-path: if either side is empty, the whole other side is the diff.
        if l.isEmpty || r.isEmpty {
            return (
                left:  l.map { InlineSegment(text: $0, kind: .removed) },
                right: r.map { InlineSegment(text: $0, kind: .added) }
            )
        }

        let table = lcsTable(l, r)

        var ops: [(InlineSegment.Kind, String?, String?)] = []
        var i = l.count, j = r.count
        while i > 0 && j > 0 {
            if l[i - 1] == r[j - 1] {
                ops.append((.equal, l[i - 1], r[j - 1]))
                i -= 1; j -= 1
            } else if table[i - 1][j] >= table[i][j - 1] {
                ops.append((.removed, l[i - 1], nil))
                i -= 1
            } else {
                ops.append((.added, nil, r[j - 1]))
                j -= 1
            }
        }
        while i > 0 { ops.append((.removed, l[i - 1], nil)); i -= 1 }
        while j > 0 { ops.append((.added, nil, r[j - 1])); j -= 1 }
        ops.reverse()

        // Coalesce consecutive same-kind tokens into a single segment so we
        // emit fewer Text views and avoid mid-word splitting in the UI.
        var leftSegs: [InlineSegment] = []
        var rightSegs: [InlineSegment] = []

        func appendLeft(_ kind: InlineSegment.Kind, _ s: String) {
            if let last = leftSegs.last, last.kind == kind {
                leftSegs[leftSegs.count - 1] = InlineSegment(text: last.text + s, kind: kind)
            } else {
                leftSegs.append(InlineSegment(text: s, kind: kind))
            }
        }

        func appendRight(_ kind: InlineSegment.Kind, _ s: String) {
            if let last = rightSegs.last, last.kind == kind {
                rightSegs[rightSegs.count - 1] = InlineSegment(text: last.text + s, kind: kind)
            } else {
                rightSegs.append(InlineSegment(text: s, kind: kind))
            }
        }

        for (kind, lTok, rTok) in ops {
            switch kind {
            case .equal:
                if let s = lTok { appendLeft(.equal, s) }
                if let s = rTok { appendRight(.equal, s) }
            case .removed:
                if let s = lTok { appendLeft(.removed, s) }
            case .added:
                if let s = rTok { appendRight(.added, s) }
            }
        }

        return (leftSegs, rightSegs)
    }

    /// Splits a string into tokens for inline diffing.
    /// Letter/digit runs become one token, every other character is its own token.
    private static func tokenizeForInlineDiff(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for c in s {
            if c.isLetter || c.isNumber {
                current.append(c)
            } else {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(c))
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - LCS table (used by both line and inline diffs)

    private static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
        let m = a.count
        let n = b.count
        guard m > 0 && n > 0 else {
            return Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        }
        var t = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    t[i][j] = t[i - 1][j - 1] + 1
                } else {
                    t[i][j] = max(t[i - 1][j], t[i][j - 1])
                }
            }
        }
        return t
    }

    // MARK: - Summary

    static func summary(rows: [DiffRow]) -> (additions: Int, deletions: Int, modifications: Int) {
        var a = 0, d = 0, m = 0
        for r in rows {
            switch r.op {
            case .added: a += 1
            case .removed: d += 1
            case .modified: m += 1
            case .equal: break
            }
        }
        return (a, d, m)
    }
}
