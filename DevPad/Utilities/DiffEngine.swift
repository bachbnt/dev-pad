// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  DiffEngine.swift
//  DevPad
//
//  Computes a line-by-line diff between two strings, plus inline
//  word/char-level diff, and groups the line-level diff into git-style hunks
//  (changes + context, gaps elided) for display.
//
//  The core is Myers' O(ND) shortest-edit-script over interned Int ids,
//  after trimming the common prefix/suffix. The old full LCS table needed
//  O(lines²) memory — two 10k-line files meant ~800 MB.
//

import Foundation

enum DiffOp: Sendable {
    case equal       // both sides identical
    case modified    // both sides present but different
    case removed     // present only on left  (deletion)
    case added       // present only on right (insertion)
}

/// Ids are positions in the sequence they belong to (row index, segment index,
/// …) rather than `UUID()`s: SwiftUI sees the same identity when a view
/// re-renders the same diff instead of tearing every row down.
struct DiffRow: Identifiable, Sendable {
    let id: Int
    let leftLineNumber: Int?    // nil if this row has no left line
    let rightLineNumber: Int?   // nil if this row has no right line
    let leftText: String?
    let rightText: String?
    let op: DiffOp
}

struct InlineSegment: Identifiable, Sendable {
    enum Kind: Sendable { case equal, removed, added }
    let id: Int
    let text: String
    let kind: Kind
}

/// A git-style hunk: a contiguous block of rows including context, with
/// a `@@ -leftStart,leftCount +rightStart,rightCount @@` header.
struct DiffHunk: Identifiable, Sendable {
    let id: Int
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
struct DiffSegment: Identifiable, Sendable {
    enum Kind: Sendable {
        case hunk(DiffHunk)
        case gap(unchangedLines: Int)
    }
    let id: Int
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

        // Intern each distinct (canonicalized) line as an Int so the edit-script
        // search compares integers instead of Strings.
        var ids: [String: Int] = [:]
        func intern(_ line: String) -> Int {
            if let id = ids[line] { return id }
            let id = ids.count
            ids[line] = id
            return id
        }
        let leftIds = leftCanon.map(intern)
        let rightIds = rightCanon.map(intern)

        let ops: [(DiffOp, Int?, Int?)] = editScript(leftIds, rightIds).map { edit in
            switch edit {
            case .equal(let a, let b): return (.equal, a, b)
            case .delete(let a):       return (.removed, a, nil)
            case .insert(let b):       return (.added, nil, b)
            }
        }

        var rows: [DiffRow] = []
        var k = 0
        while k < ops.count {
            let (op, li, ri) = ops[k]
            if case .equal = op {
                let lIdx = li ?? 0
                let rIdx = ri ?? 0
                rows.append(DiffRow(
                    id: rows.count,
                    leftLineNumber: lIdx + 1,
                    rightLineNumber: rIdx + 1,
                    leftText: leftLines[lIdx],
                    rightText: rightLines[rIdx],
                    op: .equal
                ))
                k += 1
                continue
            }

            // Collect every consecutive non-equal op into a single change
            // block, regardless of whether LCS emitted .added or .removed
            // first. (Without this, a swap like "side" → "sid" comes out as
            // one standalone .added + one standalone .removed instead of a
            // single .modified pair — and inline highlighting only runs on
            // .modified rows.)
            var removedIdxs: [Int] = []
            var addedIdxs: [Int] = []
            collect: while k < ops.count {
                switch ops[k].0 {
                case .removed:
                    if let l = ops[k].1 { removedIdxs.append(l) }
                    k += 1
                case .added:
                    if let r = ops[k].2 { addedIdxs.append(r) }
                    k += 1
                case .equal, .modified:
                    break collect
                }
            }

            let pairCount = min(removedIdxs.count, addedIdxs.count)
            for p in 0..<pairCount {
                let lIdx = removedIdxs[p]
                let rIdx = addedIdxs[p]
                rows.append(DiffRow(
                    id: rows.count,
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
                    id: rows.count,
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
                    id: rows.count,
                    leftLineNumber: nil,
                    rightLineNumber: rIdx + 1,
                    leftText: nil,
                    rightText: rightLines[rIdx],
                    op: .added
                ))
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
                segments.append(DiffSegment(id: segments.count, kind: .gap(unchangedLines: gap)))
            }
            let slice = Array(rows[s...e])
            segments.append(DiffSegment(id: segments.count, kind: .hunk(makeHunk(id: s, rows: slice))))
            prevEnd = e
        }
        let trailing = rows.count - 1 - prevEnd
        if trailing > 0 {
            segments.append(DiffSegment(id: segments.count, kind: .gap(unchangedLines: trailing)))
        }
        return segments
    }

    private static func makeHunk(id: Int, rows: [DiffRow]) -> DiffHunk {
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
            id: id,
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
                left:  l.enumerated().map { InlineSegment(id: $0.offset, text: $0.element, kind: .removed) },
                right: r.enumerated().map { InlineSegment(id: $0.offset, text: $0.element, kind: .added) }
            )
        }

        var ids: [String: Int] = [:]
        func intern(_ token: String) -> Int {
            if let id = ids[token] { return id }
            let id = ids.count
            ids[token] = id
            return id
        }
        let ops = editScript(l.map(intern), r.map(intern))

        var leftSegs: [InlineSegment] = []
        var rightSegs: [InlineSegment] = []

        func appendLeft(_ kind: InlineSegment.Kind, _ s: String) {
            if let last = leftSegs.last, last.kind == kind {
                leftSegs[leftSegs.count - 1] = InlineSegment(id: last.id, text: last.text + s, kind: kind)
            } else {
                leftSegs.append(InlineSegment(id: leftSegs.count, text: s, kind: kind))
            }
        }

        func appendRight(_ kind: InlineSegment.Kind, _ s: String) {
            if let last = rightSegs.last, last.kind == kind {
                rightSegs[rightSegs.count - 1] = InlineSegment(id: last.id, text: last.text + s, kind: kind)
            } else {
                rightSegs.append(InlineSegment(id: rightSegs.count, text: s, kind: kind))
            }
        }

        for edit in ops {
            switch edit {
            case .equal(let i, let j):
                appendLeft(.equal, l[i])
                appendRight(.equal, r[j])
            case .delete(let i):
                appendLeft(.removed, l[i])
            case .insert(let j):
                appendRight(.added, r[j])
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

    // MARK: - Edit script (Myers O(ND))

    /// One step of the shortest edit script turning `a` into `b`; indices
    /// point into the original sequences.
    enum Edit: Equatable, Sendable {
        case equal(a: Int, b: Int)
        case delete(a: Int)
        case insert(b: Int)
    }

    /// Largest edit distance searched. Memory for the backtrack trace grows
    /// with D² (~64 MB at 4 000), so beyond it the middle section is reported
    /// as wholly deleted + inserted — still a valid diff, just not minimal.
    static let maxEditDistance = 4_000

    /// Shortest edit script from `a` to `b`, in order. Trims the common
    /// prefix and suffix first, which is what makes "small change in a big
    /// file" cost almost nothing.
    static func editScript(_ a: [Int], _ b: [Int], maxEditDistance: Int = DiffEngine.maxEditDistance) -> [Edit] {
        let minLen = min(a.count, b.count)
        var prefix = 0
        while prefix < minLen && a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < minLen - prefix && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }

        var script: [Edit] = []
        script.reserveCapacity(max(a.count, b.count))
        for i in 0..<prefix { script.append(.equal(a: i, b: i)) }

        let aMid = Array(a[prefix..<(a.count - suffix)])
        let bMid = Array(b[prefix..<(b.count - suffix)])
        for edit in middleScript(aMid, bMid, maxEditDistance: maxEditDistance) {
            switch edit {
            case .equal(let i, let j): script.append(.equal(a: i + prefix, b: j + prefix))
            case .delete(let i):       script.append(.delete(a: i + prefix))
            case .insert(let j):       script.append(.insert(b: j + prefix))
            }
        }

        for s in 0..<suffix {
            script.append(.equal(a: a.count - suffix + s, b: b.count - suffix + s))
        }
        return script
    }

    private static func middleScript(_ a: [Int], _ b: [Int], maxEditDistance: Int) -> [Edit] {
        if a.isEmpty { return b.indices.map { .insert(b: $0) } }
        if b.isEmpty { return a.indices.map { .delete(a: $0) } }
        if let script = myers(a, b, maxEditDistance: maxEditDistance) { return script }
        return a.indices.map { .delete(a: $0) } + b.indices.map { .insert(b: $0) }
    }

    /// Myers' greedy forward algorithm. Returns nil if the edit distance
    /// exceeds `maxEditDistance`.
    private static func myers(_ a: [Int], _ b: [Int], maxEditDistance: Int) -> [Edit]? {
        let n = a.count
        let m = b.count
        let dLimit = min(n + m, maxEditDistance)
        let off = dLimit + 1
        // v[off + k] = furthest x reached on diagonal k (k = x - y).
        var v = [Int](repeating: 0, count: 2 * dLimit + 3)
        // trace[d][k + d] = v[off + k] as it was *before* round d.
        var trace: [[Int32]] = []

        for d in 0...dLimit {
            trace.append(v[(off - d)...(off + d)].map { Int32(truncatingIfNeeded: $0) })

            // Clamp to diagonals that intersect the n×m grid.
            let kMin = -(d - 2 * max(0, d - m))
            let kMax = d - 2 * max(0, d - n)
            var k = kMin
            while k <= kMax {
                var x: Int
                if k == kMin || (k != kMax && v[off + k - 1] < v[off + k + 1]) {
                    x = v[off + k + 1]            // step down  → insertion
                } else {
                    x = v[off + k - 1] + 1        // step right → deletion
                }
                var y = x - k
                while x < n && y < m && a[x] == b[y] { x += 1; y += 1 }
                v[off + k] = x
                if x >= n && y >= m {
                    return backtrack(trace: trace, lastD: d, n: n, m: m)
                }
                k += 2
            }
        }
        return nil
    }

    private static func backtrack(trace: [[Int32]], lastD: Int, n: Int, m: Int) -> [Edit] {
        var x = n
        var y = m
        var reversed: [Edit] = []

        var d = lastD
        while d > 0 {
            let tv = trace[d]
            let kMin = -(d - 2 * max(0, d - m))
            let kMax = d - 2 * max(0, d - n)
            let k = x - y
            let cameFromInsert = k == kMin || (k != kMax && tv[k - 1 + d] < tv[k + 1 + d])
            let prevK = cameFromInsert ? k + 1 : k - 1
            let prevX = Int(tv[prevK + d])
            let prevY = prevX - prevK

            // Diagonal run after the single insert/delete of this round.
            let midX = cameFromInsert ? prevX : prevX + 1
            let midY = midX - k
            while x > midX && y > midY {
                x -= 1; y -= 1
                reversed.append(.equal(a: x, b: y))
            }
            reversed.append(cameFromInsert ? .insert(b: prevY) : .delete(a: prevX))
            x = prevX
            y = prevY
            d -= 1
        }
        // Round 0 is only the leading diagonal.
        while x > 0 && y > 0 {
            x -= 1; y -= 1
            reversed.append(.equal(a: x, b: y))
        }
        return reversed.reversed()
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
