//
//  DiffCompareView.swift
//  DevPad
//
//  Two text editors side-by-side with a diff view below that paints
//  added (green), removed (red), and modified (yellow) lines, similar to
//  diffchecker.com — and inline word/char highlights inside modified lines.
//

import SwiftUI
import AppKit

struct DiffCompareView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var leftText: String = ""
    @State private var rightText: String = ""
    @State private var rows: [DiffRow] = []
    @State private var summary: (additions: Int, deletions: Int, modifications: Int) = (0, 0, 0)

    var body: some View {
        VStack(spacing: 12) {
            inputs
            actionBar
            if !rows.isEmpty {
                summaryBar
                diffOutput
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
                leftText = ""; rightText = ""; rows = []; summary = (0, 0, 0)
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

    private var diffOutput: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    DiffRowView(row: row)
                }
            }
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
        rows = DiffEngine.diff(left: leftText, right: rightText)
        summary = DiffEngine.summary(rows: rows)
    }
}

private struct DiffRowView: View {
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
                      side: Side) -> some View {
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
            renderedText(side: side, text: text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.trailing, 6)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .background(background)
    }

    private enum Side { case left, right }

    /// For modified rows, render the text with inline word/char-level highlights
    /// using AttributedString so we can apply per-segment background color.
    /// For other ops, render plain text.
    private func renderedText(side: Side, text: String?) -> Text {
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
        case .equal: return " "
        case .added: return " "
        }
    }

    private var rightMarker: String {
        switch row.op {
        case .added, .modified: return "+"
        case .equal: return " "
        case .removed: return " "
        }
    }
}

#Preview {
    DiffCompareView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 700)
}
