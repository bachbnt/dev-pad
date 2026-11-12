// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  DiffEngineTests.swift
//  DevPadTests
//
//  Checks the Myers edit script against a brute-force LCS on random
//  sequences (valid script + minimal length), then the line/inline diff
//  built on top of it.
//

import XCTest

final class DiffEngineTests: XCTestCase {

    // MARK: - Edit script

    /// Classic O(n·m) DP, used only as the oracle.
    private func lcsLength(_ a: [Int], _ b: [Int]) -> Int {
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0..<a.count {
            for j in 0..<b.count {
                t[i + 1][j + 1] = a[i] == b[j] ? t[i][j] + 1 : max(t[i][j + 1], t[i + 1][j])
            }
        }
        return t[a.count][b.count]
    }

    /// Replays the script on `a` and returns what it produces; also checks
    /// that every index is used exactly once and in order.
    private func apply(_ script: [DiffEngine.Edit], to a: [Int], target b: [Int], file: StaticString = #filePath, line: UInt = #line) -> [Int] {
        var out: [Int] = []
        var ai = 0, bi = 0
        for edit in script {
            switch edit {
            case .equal(let i, let j):
                XCTAssertEqual(i, ai, file: file, line: line)
                XCTAssertEqual(j, bi, file: file, line: line)
                XCTAssertEqual(a[i], b[j], file: file, line: line)
                out.append(a[i]); ai += 1; bi += 1
            case .delete(let i):
                XCTAssertEqual(i, ai, file: file, line: line)
                ai += 1
            case .insert(let j):
                XCTAssertEqual(j, bi, file: file, line: line)
                out.append(b[j]); bi += 1
            }
        }
        XCTAssertEqual(ai, a.count, file: file, line: line)
        XCTAssertEqual(bi, b.count, file: file, line: line)
        return out
    }

    func testEditScriptMatchesBruteForceLCSOnRandomInputs() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let alphabet = Int.random(in: 1...5, using: &rng)
            let a = (0..<Int.random(in: 0...25, using: &rng)).map { _ in Int.random(in: 0..<alphabet, using: &rng) }
            let b = (0..<Int.random(in: 0...25, using: &rng)).map { _ in Int.random(in: 0..<alphabet, using: &rng) }

            let script = DiffEngine.editScript(a, b)
            XCTAssertEqual(apply(script, to: a, target: b), b, "a=\(a) b=\(b)")

            let equals = script.filter { if case .equal = $0 { return true } else { return false } }.count
            XCTAssertEqual(equals, lcsLength(a, b), "script is not minimal for a=\(a) b=\(b)")
        }
    }

    func testEditScriptEdgeCases() {
        XCTAssertEqual(DiffEngine.editScript([], []), [])
        XCTAssertEqual(DiffEngine.editScript([1, 2], []), [.delete(a: 0), .delete(a: 1)])
        XCTAssertEqual(DiffEngine.editScript([], [7]), [.insert(b: 0)])
        XCTAssertEqual(DiffEngine.editScript([1, 2, 3], [1, 2, 3]),
                       [.equal(a: 0, b: 0), .equal(a: 1, b: 1), .equal(a: 2, b: 2)])
    }

    func testEditScriptFallsBackToValidScriptWhenDistanceExceedsCap() {
        let a = Array(0..<50)
        let b = Array(100..<150)
        let script = DiffEngine.editScript(a, b, maxEditDistance: 10)
        XCTAssertEqual(apply(script, to: a, target: b), b)
        XCTAssertFalse(script.contains { if case .equal = $0 { return true } else { return false } })
    }

    func testLargeFilesWithOneChangeStayCheap() {
        let a = (0..<50_000).map { "line \($0)" }.joined(separator: "\n")
        var lines = (0..<50_000).map { "line \($0)" }
        lines[25_000] = "changed"
        let b = lines.joined(separator: "\n")

        let rows = DiffEngine.diff(left: a, right: b)
        let summary = DiffEngine.summary(rows: rows)
        XCTAssertEqual(rows.count, 50_000)
        XCTAssertEqual(summary.modifications, 1)
        XCTAssertEqual(summary.additions, 0)
        XCTAssertEqual(summary.deletions, 0)
    }

    /// Worst case for Myers: nothing in common, so D = n + m. Must hit the
    /// distance cap, fall back, and still produce a correct (if not minimal)
    /// result without a giant table.
    func testCompletelyDifferentLargeFilesFallBackQuickly() {
        let a = (0..<3_000).map { "left \($0)" }.joined(separator: "\n")
        let b = (0..<3_000).map { "right \($0)" }.joined(separator: "\n")
        let start = Date()
        let rows = DiffEngine.diff(left: a, right: b)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertEqual(rows.count, 3_000)
        XCTAssertTrue(rows.allSatisfy { $0.op == .modified })
    }

    // MARK: - Line diff

    func testIdenticalTextHasNoChanges() {
        let rows = DiffEngine.diff(left: "a\nb\nc", right: "a\nb\nc")
        XCTAssertEqual(DiffEngine.summary(rows: rows).additions, 0)
        XCTAssertEqual(DiffEngine.summary(rows: rows).deletions, 0)
        XCTAssertEqual(DiffEngine.summary(rows: rows).modifications, 0)
        XCTAssertTrue(DiffEngine.segment(rows: rows).isEmpty)
    }

    func testReplacedLineBecomesOneModifiedRow() {
        let rows = DiffEngine.diff(left: "a\nb\nc", right: "a\nB\nc")
        XCTAssertEqual(rows.map(\.op), [.equal, .modified, .equal])
        XCTAssertEqual(rows[1].leftText, "b")
        XCTAssertEqual(rows[1].rightText, "B")
        XCTAssertEqual(rows[1].leftLineNumber, 2)
        XCTAssertEqual(rows[1].rightLineNumber, 2)
    }

    func testPureInsertionAndDeletion() {
        let added = DiffEngine.diff(left: "a\nc", right: "a\nb\nc")
        XCTAssertEqual(added.map(\.op), [.equal, .added, .equal])
        XCTAssertNil(added[1].leftLineNumber)
        XCTAssertEqual(added[1].rightLineNumber, 2)

        let removed = DiffEngine.diff(left: "a\nb\nc", right: "a\nc")
        XCTAssertEqual(removed.map(\.op), [.equal, .removed, .equal])
        XCTAssertEqual(removed[1].leftLineNumber, 2)
        XCTAssertNil(removed[1].rightLineNumber)
    }

    func testIgnoreWhitespaceAndCase() {
        XCTAssertEqual(DiffEngine.summary(rows: DiffEngine.diff(left: "a  b", right: "a b", ignoreWhitespace: true)).modifications, 0)
        XCTAssertEqual(DiffEngine.summary(rows: DiffEngine.diff(left: "a  b", right: "a b")).modifications, 1)
        XCTAssertEqual(DiffEngine.summary(rows: DiffEngine.diff(left: "Hello", right: "hello", ignoreCase: true)).modifications, 0)
        XCTAssertEqual(DiffEngine.summary(rows: DiffEngine.diff(left: "Hello", right: "hello")).modifications, 1)
    }

    func testRowIdsAreStableAndUnique() {
        let a = "1\n2\n3\n4"
        let b = "1\nx\n3\ny\nz"
        let first = DiffEngine.diff(left: a, right: b).map(\.id)
        let second = DiffEngine.diff(left: a, right: b).map(\.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first).count, first.count)
    }

    // MARK: - Hunks

    func testSegmentsAddContextAndGapMarkers() {
        let left = (1...20).map(String.init).joined(separator: "\n")
        let right = left.replacingOccurrences(of: "10", with: "ten")
        let segments = DiffEngine.segment(rows: DiffEngine.diff(left: left, right: right), context: 2)

        guard segments.count == 3,
              case .gap(let before) = segments[0].kind,
              case .hunk(let hunk) = segments[1].kind,
              case .gap(let after) = segments[2].kind else {
            return XCTFail("expected gap, hunk, gap; got \(segments.count) segments")
        }
        XCTAssertEqual(before, 7)       // lines 1…7 hidden
        XCTAssertEqual(hunk.rows.count, 5)   // 2 context + change + 2 context
        XCTAssertEqual(hunk.header, "@@ -8,5 +8,5 @@")
        XCTAssertEqual(after, 8)        // lines 13…20 hidden
        XCTAssertEqual(Set(segments.map(\.id)).count, 3)
    }

    // MARK: - Inline diff

    func testInlineDiffHighlightsOnlyChangedToken() {
        let (l, r) = DiffEngine.inlineDiff("let x = 1", "let x = 2")
        XCTAssertEqual(l.map(\.kind), [.equal, .removed])
        XCTAssertEqual(l.map(\.text), ["let x = ", "1"])
        XCTAssertEqual(r.map(\.kind), [.equal, .added])
        XCTAssertEqual(r.map(\.text), ["let x = ", "2"])
        XCTAssertEqual(l.map(\.id), [0, 1])
    }

    func testInlineDiffWithEmptySide() {
        let (l, r) = DiffEngine.inlineDiff("", "abc")
        XCTAssertTrue(l.isEmpty)
        XCTAssertEqual(r.map(\.kind), [.added])
    }
}
