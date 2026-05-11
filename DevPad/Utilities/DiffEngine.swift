//
//  DiffEngine.swift
//  DevPad
//
//  Computes a line-by-line diff between two strings using LCS, plus
//  inline word/char-level diff, and groups the line-level diff into
//  git-style hunks (changes + context, gaps elided) for display.
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

/// A git-style hunk: a contiguous block of rows including context, with
/// a `@@ -leftStart,leftCount +rightStart,rightCount @@` header.
struct DiffHunk: Identifiable {
    let id = UUID()
    let rows: [DiffRow]
    let leftStart: Int
    let leftCount: Int
    let rightStart: Int
    let rightCount: Int

    var header: String {
        "@@ -\(leftStart),\(leftCount) +\(rightStart),\(rightCount) @@"
    }
}

/// Either a hunk to render or a "@@ N lines hidden @@" gap marker.
struct DiffSegment: Identifiable {
    enum Kind {
        case hunk(DiffHunk)
        case gap(unchangedLines: Int)
    }
    let id = UUID()
    let kind: Kind
}

struct DiffEngine {

    // MARK: - Line-level diff

    /// Compares two texts line-by-line and returns aligned rows.
    /// Adjacent removed/added rows are merged into `.modified` row pairs.
    ///
    /// `ignoreWhitespace` and `ignoreCase` only affect the *comparison*;
    /// the original text is preserved in each `DiffRow`.
    static func diff(left: String,
                     right: String,
                     ignoreWhitespace: Bool = false,
                     ignoreCase: Bool = false) -> [DiffRow] {
        let leftLines = left.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let rightLines = right.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Build "canonical" versions for comparison (without losing the original text).
        let leftCanon = leftLines.map { canonicalize($0, ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase) }
        let rightCanon = rightLines.map { canonicalize($0, ignoreWhitespace: ignoreWhitespace, ignoreCase: ignoreCase) }

        let lcs = lcsTable(leftCanon, rightCanon)

        var ops: [(DiffOp, Int?, Int?)] = []
        var i = leftCanon.count
        var j = rightCanon.count
        while i > 0 && j > 0 {
            if leftCanon[i - 1] == rightCanon[j - 1] {
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

    // MARK: - Hunk grouping (git-style)

    /// Groups rows into hunks separated by gap markers, mimicking
    /// `git diff -U<context>`. Long runs of unchanged lines collapse into
    /// "… N unchanged line(s) hidden …" rows; changes are surrounded by
    /// up to `context` context lines on each side.
    static func segment(rows: [DiffRow], context: Int = 3) -> [DiffSegment] {
        guard !rows.isEmpty else { return [] }

        // Locate indices of any non-equal row.
        let changedIdxs = rows.enumerated()
            .filter { $0.element.op != .equal }
            .map { $0.offset }

        guard !changedIdxs.isEmpty else { return [] }

        // Build hunk ranges by expanding each change cluster with `context`
        // lines on either side, then merging overlapping ranges.
        var ranges: [(Int, Int)] = []
        var curStart = max(0, changedIdxs[0] - context)
        var curEnd = min(rows.count - 1, changedIdxs[0] + context)

        for idx in changedIdxs.dropFirst() {
            let propStart = max(0, idx - context)
            let propEnd = min(rows.count - 1, idx + context)
            if propStart <= curEnd + 1 {
                curEnd = max(curEnd, propEnd)
            } else {
                ranges.append((curStart, curEnd))
                curStart = propStart
                curEnd = propEnd
            }
        }
        ranges.append((curStart, curEnd))

        // Emit segments — gap, hunk, gap, hunk, …
        var segments: [DiffSegment] = []
        var prevEnd = -1
        for (s, e) in ranges {
            let gap = s - (prevEnd + 1)
            if gap > 0 {
                segments.append(DiffSegment(kind: .gap(unchangedLines: gap)))
            }
            let slice = Array(rows[s...e])
            segments.append(DiffSegment(kind: .hunk(makeHunk(rows: slice))))
            prevEnd = e
        }
        let trailing = rows.count - 1 - prevEnd
        if trailing > 0 {
            segments.append(DiffSegment(kind: .gap(unchangedLines: trailing)))
        }
        return segments
    }

    private static func makeHunk(rows: [DiffRow]) -> DiffHunk {
        var lMin = Int.max, lCount = 0
        var rMin = Int.max, rCount = 0
        for row in rows {
            if let l = row.leftLineNumber {
                lMin = min(lMin, l)
                lCount += 1
            }
            if let r = row.rightLineNumber {
                rMin = min(rMin, r)
                rCount += 1
            }
        }
        return DiffHunk(
            rows: rows,
            leftStart: lMin == .max ? 0 : lMin,
            leftCount: lCount,
            rightStart: rMin == .max ? 0 : rMin,
            rightCount: rCount
        )
    }

    // MARK: - Inline (word/char) diff inside a modified row

    /// Returns segmented arrays for the left and right strings so that the UI
    /// can highlight only the parts that actually changed within a modified line.
    static func inlineDiff(_ left: String, _ right: String) -> (left: [InlineSegment], right: [InlineSegment]) {
        let l = tokenizeForInlineDiff(left)
        let r = tokenizeForInlineDiff(right)

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

    // MARK: - Canonicalization for ignoreWhitespace / ignoreCase

    private static func canonicalize(_ s: String, ignoreWhitespace: Bool, ignoreCase: Bool) -> String {
        var t = s
        if ignoreWhitespace {
            // Trim ends and collapse internal whitespace runs to a single space.
            t = t.trimmingCharacters(in: .whitespaces)
            var collapsed = ""
            var lastWasSpace = false
            for c in t {
                if c.isWhitespace {
                    if !lastWasSpace { collapsed.append(" ") }
                    lastWasSpace = true
                } else {
                    collapsed.append(c)
                    lastWasSpace = false
                }
            }
            t = collapsed
        }
        if ignoreCase {
            t = t.lowercased()
        }
        return t
    }

    // MARK: - LCS

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
