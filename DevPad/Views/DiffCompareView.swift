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
        .frame(minHeight: 220)
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
        ScrollView([.vertical, .horizontal]) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
        )
        .frame(minHeight: 200)
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
        HStack(spacing: 0) {
            cell(
                lineNumber: row.leftLineNumber,
                text: row.leftText,
                background: leftBackground,
                marker: leftMarker,
                side: .left
            )
            Divider()
            cell(
                lineNumber: row.rightLineNumber,
                text: row.rightText,
                background: rightBackground,
                marker: rightMarker,
                side: .right
            )
        }
        .frame(minHeight: 22)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.trailing, 6)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
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

            unifiedText(side: side, text: text)
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
    private func unifiedText(side: DiffSide?, text: String) -> Text {
        // We just need to know both sides exist (so inlineDiff has both
        // strings to compare); `renderedRow` reads them again via `row`.
        guard let side, row.op == .modified,
              row.leftText != nil, row.rightText != nil else {
            return Text(text)
        }
        return renderedRow(row: row, side: side, text: text)
    }
}

// MARK: - Shared inline-highlight renderer

/// For modified rows, render text with inline word/char-level highlights
/// using AttributedString so we can apply per-segment background color.
/// For other ops, render plain text.
private func renderedRow(row: DiffRow, side: DiffSide, text: String?) -> Text {
    let plain = text ?? ""
    guard row.op == .modified,
          let l = row.leftText,
          let r = row.rightText else {
        return Text(plain)
    }
    let (leftSegs, rightSegs) = DiffEngine.inlineDiff(l, r)
    let segs = side == .left ? leftSegs : rightSegs

    var attr = AttributedString("")
    for seg in segs {
        var part = AttributedString(seg.text)
        switch seg.kind {
        case .equal:
            break
        case .removed:
            part.backgroundColor = Color.red.opacity(0.45)
            part.foregroundColor = .primary
        case .added:
            part.backgroundColor = Color.green.opacity(0.45)
            part.foregroundColor = .primary
        }
        attr.append(part)
    }
    return Text(attr)
}

#Preview {
    DiffCompareView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1100, height: 800)
}
