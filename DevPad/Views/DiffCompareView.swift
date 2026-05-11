//
//  DiffCompareView.swift
//  DevPad
//
//  Two text editors side-by-side, then a git-style diff renderer below.
//  Supports Split (two-column) and Unified (single column with +/− prefixes)
//  view modes, configurable context size, and ignore-whitespace / ignore-case
//  toggles — matching the behaviour you'd get from `git diff -U<n> [--ignore-…]`.
//

import SwiftUI
import AppKit

private enum DiffViewMode: String, CaseIterable, Identifiable {
    case split, unified
    var id: String { rawValue }
}

private enum DiffSide { case left, right }

struct DiffCompareView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var leftText: String = ""
    @State private var rightText: String = ""
    @State private var rows: [DiffRow] = []
    @State private var segments: [DiffSegment] = []
    @State private var summary: (additions: Int, deletions: Int, modifications: Int) = (0, 0, 0)
    @State private var hasRun: Bool = false

    // Display options — persisted across re-runs of the comparison.
    @State private var viewMode: DiffViewMode = .split
    @State private var contextLines: Int = 3
    @State private var ignoreWhitespace: Bool = false
    @State private var ignoreCase: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            inputs
            actionBar
            optionsBar
            if hasRun {
                summaryBar
                if rows.isEmpty || summary.additions + summary.deletions + summary.modifications == 0 {
                    identicalPlaceholder
                } else {
                    diffOutput
                }
            } else {
                placeholder
            }
        }
        .padding(16)
    }

    // MARK: - Subviews

    private var inputs: some View {
        HStack(spacing: 12) {
            editorPane(
                title: settings.t("diff.original"),
                text: $leftText,
                placeholder: settings.t("diff.placeholder.left")
            )
            editorPane(
                title: settings.t("diff.changed"),
                text: $rightText,
                placeholder: settings.t("diff.placeholder.right")
            )
        }
        // Editors stay reasonably tall to remain comfortable to type in
        // but never grow past `inputsMaxHeight` once a diff has run, so the
        // diff output gets the lion's share of vertical space.
        .frame(minHeight: 140, maxHeight: hasRun ? 200 : .infinity)
    }

    private func editorPane(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        text.wrappedValue = s
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help(settings.t("common.paste"))
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(settings.t("common.clear"))
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25))
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                TextEditor(text: text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .font(.system(.body, design: .monospaced))
                        .padding(.leading, 13)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(role: .destructive) {
                leftText = ""; rightText = ""
                rows = []; segments = []
                summary = (0, 0, 0)
                hasRun = false
            } label: {
                Label(settings.t("common.clearAll"), systemImage: "trash")
            }
            Spacer()
            Button {
                runDiff()
            } label: {
                Label(settings.t("common.compare"), systemImage: "arrow.left.arrow.right")
                    .frame(minWidth: 100)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
    }

    private var optionsBar: some View {
        HStack(spacing: 16) {
            // View mode toggle — Split vs Unified.
            HStack(spacing: 6) {
                Text(settings.t("diff.viewMode") + ":")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Picker("", selection: $viewMode) {
                    Text(settings.t("diff.viewMode.split")).tag(DiffViewMode.split)
                    Text(settings.t("diff.viewMode.unified")).tag(DiffViewMode.unified)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }

            // Context size stepper (git -U<n>).
            HStack(spacing: 6) {
                Text(settings.t("diff.context") + ":")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Stepper(value: $contextLines, in: 0...20) {
                    Text("\(contextLines)")
                        .font(.callout.monospacedDigit())
                        .frame(minWidth: 18)
                }
                // Single-closure form of onChange is the macOS 13-compatible
                // signature; the two-parameter form requires macOS 14+.
                .onChange(of: contextLines) { _ in regroupOnly() }
            }

            Toggle(settings.t("diff.options.whitespace"), isOn: $ignoreWhitespace)
                .toggleStyle(.checkbox)
                .onChange(of: ignoreWhitespace) { _ in if hasRun { runDiff() } }

            Toggle(settings.t("diff.options.case"), isOn: $ignoreCase)
                .toggleStyle(.checkbox)
                .onChange(of: ignoreCase) { _ in if hasRun { runDiff() } }

            Spacer()
        }
        .font(.callout)
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            Label(settings.t("diff.summary.added", summary.additions),
                  systemImage: "plus.circle.fill")
                .foregroundStyle(.green)
            Label(settings.t("diff.summary.removed", summary.deletions),
                  systemImage: "minus.circle.fill")
                .foregroundStyle(.red)
            Label(settings.t("diff.summary.modified", summary.modifications),
                  systemImage: "pencil.circle.fill")
                .foregroundStyle(.orange)
            Spacer()
        }
        .font(.callout)
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(settings.t("diff.placeholder.empty"))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var identicalPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "equal.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text(settings.t("diff.identical"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.05))
        )
    }

    private var diffOutput: some View {
        // Vertical-only scroll: long lines wrap via FlowLayout inside each
        // row, so no horizontal scroll is needed.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(segments) { seg in
                    switch seg.kind {
                    case .gap(let n):
                        GapMarker(lines: n,
                                  text: settings.t("diff.hunk.gap", n))
                    case .hunk(let hunk):
                        HunkHeader(text: hunk.header)
                        ForEach(hunk.rows) { row in
                            if viewMode == .split {
                                SplitDiffRowView(row: row)
                            } else {
                                UnifiedDiffRowView(row: row)
                            }
                        }
                    }
                }
            }
            // .topLeading instead of .leading — without specifying vertical
            // alignment the frame defaults to .center, which left the rows
            // floating in the middle of the (now tall) diff frame instead
            // of pinned to the top.
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        // Clip content to the rounded rectangle so row backgrounds (red /
        // green stripes) don't poke into the sharp corners of the parent
        // rectangle. The stroked outline is drawn as an overlay so the
        // border stays sharp on top of the clipped content.
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
        // Diff result is the focus once a comparison has been run, so let
        // it take whatever vertical space the window has to spare.
        .frame(minHeight: 200, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func runDiff() {
        rows = DiffEngine.diff(
            left: leftText,
            right: rightText,
            ignoreWhitespace: ignoreWhitespace,
            ignoreCase: ignoreCase
        )
        summary = DiffEngine.summary(rows: rows)
        segments = DiffEngine.segment(rows: rows, context: contextLines)
        hasRun = true
    }

    /// Re-runs only the hunk grouping (when the user nudges context size,
    /// no need to recompute the entire LCS diff).
    private func regroupOnly() {
        guard hasRun else { return }
        segments = DiffEngine.segment(rows: rows, context: contextLines)
    }
}

// MARK: - Hunk header & gap marker

private struct HunkHeader: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.purple)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.purple.opacity(0.08))
    }
}

private struct GapMarker: View {
    let lines: Int
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
    }
}

// MARK: - Split-mode row (two columns)

private struct SplitDiffRowView: View {
    let row: DiffRow

    var body: some View {
        // `.alignment: .top` keeps line numbers and content of both cells
        // pinned to the same top edge — otherwise, when one side wraps and
        // the other doesn't, HStack's default centre alignment misaligns
        // them. The `.frame(maxHeight: .infinity)` + `.fixedSize` pair
        // makes each cell's background fill the row's full height so the
        // shorter side doesn't show an awkward uncoloured gap.
        HStack(alignment: .top, spacing: 0) {
            cell(
                lineNumber: row.leftLineNumber,
                text: row.leftText,
                background: leftBackground,
                marker: leftMarker,
                side: .left
            )
            .frame(maxHeight: .infinity)
            Divider()
            cell(
                lineNumber: row.rightLineNumber,
                text: row.rightText,
                background: rightBackground,
                marker: rightMarker,
                side: .right
            )
            .frame(maxHeight: .infinity)
        }
        .frame(minHeight: 22)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func cell(lineNumber: Int?,
                      text: String?,
                      background: Color,
                      marker: String,
                      side: DiffSide) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(lineNumber.map(String.init) ?? "")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 6)
            Text(marker)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)
            renderedRow(row: row, side: side, text: text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 2)
                .padding(.trailing, 6)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        // Background applied AFTER `.frame(maxHeight: .infinity)` so that
        // when the row gets stretched (because the sibling cell wrapped),
        // the colour fills the entire row height instead of leaving an
        // uncoloured gap below this cell's content.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
    }

    private var leftBackground: Color {
        switch row.op {
        case .removed, .modified: return Color.red.opacity(0.18)
        case .equal: return .clear
        case .added: return Color.secondary.opacity(0.06)
        }
    }

    private var rightBackground: Color {
        switch row.op {
        case .added, .modified: return Color.green.opacity(0.18)
        case .equal: return .clear
        case .removed: return Color.secondary.opacity(0.06)
        }
    }

    private var leftMarker: String {
        switch row.op {
        case .removed, .modified: return "−"
        default: return " "
        }
    }

    private var rightMarker: String {
        switch row.op {
        case .added, .modified: return "+"
        default: return " "
        }
    }
}

// MARK: - Unified-mode row (single column with +/− prefix)

private struct UnifiedDiffRowView: View {
    let row: DiffRow

    var body: some View {
        switch row.op {
        case .equal:
            unifiedLine(
                marker: " ",
                leftNum: row.leftLineNumber,
                rightNum: row.rightLineNumber,
                text: row.leftText ?? row.rightText ?? "",
                background: .clear,
                side: nil
            )
        case .removed:
            unifiedLine(
                marker: "−",
                leftNum: row.leftLineNumber,
                rightNum: nil,
                text: row.leftText ?? "",
                background: Color.red.opacity(0.18),
                side: .left
            )
        case .added:
            unifiedLine(
                marker: "+",
                leftNum: nil,
                rightNum: row.rightLineNumber,
                text: row.rightText ?? "",
                background: Color.green.opacity(0.18),
                side: .right
            )
        case .modified:
            VStack(spacing: 0) {
                unifiedLine(
                    marker: "−",
                    leftNum: row.leftLineNumber,
                    rightNum: nil,
                    text: row.leftText ?? "",
                    background: Color.red.opacity(0.18),
                    side: .left
                )
                unifiedLine(
                    marker: "+",
                    leftNum: nil,
                    rightNum: row.rightLineNumber,
                    text: row.rightText ?? "",
                    background: Color.green.opacity(0.18),
                    side: .right
                )
            }
        }
    }

    private func unifiedLine(marker: String,
                             leftNum: Int?,
                             rightNum: Int?,
                             text: String,
                             background: Color,
                             side: DiffSide?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(leftNum.map(String.init) ?? "")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 4)
            Text(rightNum.map(String.init) ?? "")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 6)
            Text(marker)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)

            unifiedContent(side: side, text: text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.trailing, 6)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .background(background)
    }

    /// In unified mode, inline highlights still apply for modified rows —
    /// passing `side` lets us pull the correct half of the inline diff.
    @ViewBuilder
    private func unifiedContent(side: DiffSide?, text: String) -> some View {
        if let side, row.op == .modified,
           row.leftText != nil, row.rightText != nil {
            renderedRow(row: row, side: side, text: text)
        } else {
            Text(text)
        }
    }
}

// MARK: - Shared inline-highlight renderer

/// Renders one diff row's text with character/word-level highlights for
/// modified rows. Each diff segment becomes its own `Text` view laid out
/// by a custom `FlowLayout` so we can keep per-segment `.background()`
/// (the only reliable way to get a deep red/green character highlight on
/// macOS — AttributedString.backgroundColor isn't honoured) while still
/// wrapping naturally when the row exceeds available width.
///
/// Whitespace tokens with a non-equal kind get a `\u{00A0}` (no-break
/// space) substitute so their background actually paints (a regular
/// space's bounding box can collapse to zero width in some layouts).
@ViewBuilder
private func renderedRow(row: DiffRow, side: DiffSide, text: String?) -> some View {
    let plain = text ?? ""
    if row.op == .modified,
       let l = row.leftText,
       let r = row.rightText {
        let (leftSegs, rightSegs) = DiffEngine.inlineDiff(l, r)
        let segs = side == .left ? leftSegs : rightSegs
        FlowLayout {
            ForEach(segs) { seg in
                Text(displayText(for: seg))
                    .foregroundStyle(.primary)
                    .background(
                        Rectangle().fill(inlineBackground(for: seg.kind))
                    )
            }
        }
    } else {
        Text(plain)
    }
}

private func displayText(for seg: InlineSegment) -> String {
    guard seg.kind != .equal else { return seg.text }
    // Preserve whitespace visually so highlighted whitespace still shows.
    return seg.text.replacingOccurrences(of: " ", with: "\u{00A0}")
}

private func inlineBackground(for kind: InlineSegment.Kind) -> Color {
    switch kind {
    case .equal:   return .clear
    // Deeper saturation than the row tint so the changed characters
    // visibly "pop" against the lighter row background.
    case .removed: return Color.red.opacity(0.55)
    case .added:   return Color.green.opacity(0.55)
    }
}

// MARK: - FlowLayout

/// Minimal left-to-right, top-to-bottom flow layout. Places its subviews
/// next to each other and starts a new row when the proposed width would
/// be exceeded. Used to wrap the per-segment Text views inside a diff
/// row while preserving each segment's `.background()` for character-
/// level highlighting.
private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 0
    var verticalSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height }
            + (rows.isEmpty ? 0 : CGFloat(rows.count - 1) * verticalSpacing)
        // Use the widest row, capped at the proposal — avoids the layout
        // claiming infinity width when proposal.width is nil.
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout Void) {
        let maxWidth = bounds.width
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for idxPos in row.indices.indices {
                let index = row.indices[idxPos]
                let subview = subviews[index]
                let proposed = row.proposals[idxPos]
                let size = subview.sizeThatFits(proposed)
                subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: proposed
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var proposals: [ProposedViewSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (idx, subview) in subviews.enumerated() {
            let natural = subview.sizeThatFits(.unspecified)

            // If a single subview is wider than the row, propose the full
            // row width so it can wrap internally (Text wraps when given
            // a bounded width). Place it on its own row.
            if natural.width > maxWidth {
                if !rows[rows.count - 1].indices.isEmpty {
                    rows.append(Row())
                }
                let proposal = ProposedViewSize(width: maxWidth, height: nil)
                let wrappedSize = subview.sizeThatFits(proposal)
                var newRow = Row()
                newRow.indices = [idx]
                newRow.proposals = [proposal]
                newRow.width = wrappedSize.width
                newRow.height = wrappedSize.height
                rows[rows.count - 1] = newRow
                rows.append(Row())
                continue
            }

            var last = rows[rows.count - 1]
            let leadingSpace = last.indices.isEmpty ? 0 : horizontalSpacing
            if last.width + leadingSpace + natural.width > maxWidth, !last.indices.isEmpty {
                rows.append(Row())
                last = rows[rows.count - 1]
            }
            let spacing = last.indices.isEmpty ? 0 : horizontalSpacing
            last.indices.append(idx)
            last.proposals.append(ProposedViewSize(natural))
            last.width += spacing + natural.width
            last.height = max(last.height, natural.height)
            rows[rows.count - 1] = last
        }
        // Strip a trailing empty row created when the last "single wide
        // subview" branch was hit.
        if let last = rows.last, last.indices.isEmpty, rows.count > 1 {
            rows.removeLast()
        }
        return rows
    }
}

#Preview {
    DiffCompareView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1100, height: 800)
}
