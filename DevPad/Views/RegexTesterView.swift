// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  RegexTesterView.swift
//  DevPad
//
//  Live regex playground:
//    • Match mode — pattern + flags + test string, every match is painted
//      inline (real attributed NSTextView, not a SwiftUI overlay), with a
//      table below listing each match's range and capture groups.
//    • Replace mode — same pattern + flags but adds a template field, shows
//      the rewritten output and how many matches were replaced.
//    • Quick reference — popover cheatsheet of the most useful tokens.
//

import SwiftUI
import AppKit

private enum RegexMode: String, CaseIterable, Identifiable {
    case match, replace
    var id: String { rawValue }
}

private struct FlagOption: Identifiable {
    let id: String
    let flag: RegexFlags
    let titleKey: String
    let symbol: String
}

private let flagOptions: [FlagOption] = [
    FlagOption(id: "i", flag: .caseInsensitive,
               titleKey: "regex.flag.caseInsensitive", symbol: "Aa"),
    FlagOption(id: "m", flag: .multiline,
               titleKey: "regex.flag.multiline", symbol: "¶"),
    FlagOption(id: "s", flag: .dotMatchesLineEndings,
               titleKey: "regex.flag.dotAll", symbol: "."),
    FlagOption(id: "u", flag: .unicodeWordBoundaries,
               titleKey: "regex.flag.unicode", symbol: "𝓤"),
]

struct RegexTesterView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var mode: RegexMode = .match
    @State private var pattern: String = ""
    @State private var flags: RegexFlags = [.caseInsensitive]
    @State private var testText: String = ""
    @State private var replaceTemplate: String = ""

    @State private var errorMessage: String?
    @State private var matches: [RegexMatch] = []
    @State private var nsRanges: [NSRange] = []
    @State private var replaceOutput: String = ""
    @State private var replaceCount: Int = 0

    @State private var showCheatsheet = false

    var body: some View {
        VStack(spacing: 12) {
            modePicker
            patternBar
            flagBar
            if let errorMessage {
                errorBanner(errorMessage)
            }
            switch mode {
            case .match:   matchView
            case .replace: replaceView
            }
            actionBar
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if DemoMode.isOn, pattern.isEmpty, testText.isEmpty {
                pattern = DemoMode.sampleRegexPattern
                testText = DemoMode.sampleRegexText
                flags = DemoMode.sampleRegexFlags
                recompute()
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                recompute()
            } label: {
                Label(
                    mode == .match
                        ? settings.t("regex.run.match")
                        : settings.t("regex.run.apply"),
                    systemImage: mode == .match ? "magnifyingglass" : "wand.and.stars"
                )
                .frame(minWidth: 120)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(pattern.isEmpty)
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text(settings.t("regex.mode.match")).tag(RegexMode.match)
            Text(settings.t("regex.mode.replace")).tag(RegexMode.replace)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
    }

    // MARK: - Pattern + flags

    private var patternBar: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("/")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField(settings.t("regex.pattern.placeholder"), text: $pattern)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
            Text("/")
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(activeFlagsString)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, alignment: .leading)

            Button {
                showCheatsheet.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(settings.t("regex.cheatsheet"))
            .popover(isPresented: $showCheatsheet, arrowEdge: .bottom) {
                cheatsheet
                    .padding(14)
                    .frame(width: 360)
            }

            Button {
                if let s = NSPasteboard.general.string(forType: .string) {
                    pattern = s
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help(settings.t("common.paste"))

            Button(role: .destructive) {
                pattern = ""
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(settings.t("common.clear"))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
        )
    }

    private var activeFlagsString: String {
        flagOptions
            .filter { flags.contains($0.flag) }
            .map { $0.id }
            .joined()
    }

    private var flagBar: some View {
        HStack(spacing: 8) {
            ForEach(flagOptions) { opt in
                let isOn = flags.contains(opt.flag)
                Button {
                    if isOn { flags.remove(opt.flag) }
                    else    { flags.insert(opt.flag) }
                } label: {
                    HStack(spacing: 4) {
                        Text(opt.symbol)
                            .font(.system(.callout, design: .monospaced).weight(.bold))
                        Text(settings.t(opt.titleKey))
                            .font(.callout)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isOn
                                  ? Color.accentColor.opacity(0.25)
                                  : Color.secondary.opacity(0.10))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                    .foregroundStyle(isOn ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
                .help(settings.t(opt.titleKey))
            }
            Spacer()
            if !matches.isEmpty {
                Text(settings.t("regex.matchCount", matches.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Match mode

    private var matchView: some View {
        VStack(spacing: 10) {
            highlightedEditor
                .frame(minHeight: 180)
            matchList
        }
    }

    private var highlightedEditor: some View {
        HighlightedTextView(text: $testText, ranges: nsRanges,
                            placeholder: settings.t("regex.testText.placeholder"))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var matchList: some View {
        if !matches.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { idx, m in
                        matchRow(index: idx + 1, match: m)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxHeight: .infinity)
        } else if errorMessage == nil, !pattern.isEmpty, !testText.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(settings.t("regex.match.empty"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if pattern.isEmpty, testText.isEmpty {
            placeholder
        }
    }

    private func matchRow(index: Int, match: RegexMatch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(index)")
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Text(match.text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.18))
                    .cornerRadius(4)
                Text(rangeLabel(match.range))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                Button {
                    copy(match.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(settings.t("common.copy"))
            }
            ForEach(Array(match.groups.enumerated()), id: \.offset) { i, group in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(group.name)")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, alignment: .trailing)
                    if group.text.isEmpty, group.range == nil {
                        Text(settings.t("regex.group.empty"))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(group.text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(4)
                        Button {
                            copy(group.text)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(settings.t("common.copy"))
                    }
                }
                .padding(.leading, 12)
            }
            Divider().opacity(0.5)
        }
    }

    private func rangeLabel(_ range: Range<String.Index>) -> String {
        let start = testText.distance(from: testText.startIndex, to: range.lowerBound)
        let end = testText.distance(from: testText.startIndex, to: range.upperBound)
        return "[\(start)…\(end)]"
    }

    // MARK: - Replace mode

    private var replaceView: some View {
        VStack(spacing: 10) {
            highlightedEditor
                .frame(minHeight: 140)

            HStack(spacing: 8) {
                Text(settings.t("regex.replace.template"))
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .trailing)
                TextField(settings.t("regex.replace.template.placeholder"),
                          text: $replaceTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text(settings.t("regex.replace.summary", replaceCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy(replaceOutput)
                } label: {
                    Label(settings.t("regex.replace.copyResult"),
                          systemImage: "doc.on.doc")
                }
                .disabled(replaceOutput.isEmpty || matches.isEmpty)
            }

            ScrollView {
                Text(replaceOutput.isEmpty ? settings.t("regex.replace.empty") : replaceOutput)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(replaceOutput.isEmpty ? AnyShapeStyle(HierarchicalShapeStyle.tertiary)
                                                           : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Empty state

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "asterisk")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("regex.empty.title"))
                .font(.headline)
            Text(settings.t("regex.empty.hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("\(settings.t("regex.error.prefix")): \(message)")
                .font(.callout)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    // MARK: - Cheatsheet

    private var cheatsheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.t("regex.cheatsheet.title"))
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                cheatRow("^ $",           settings.t("regex.cheat.anchors"))
                cheatRow(#"\b"#,          settings.t("regex.cheat.wordBoundary"))
                cheatRow(#"\d \w \s"#,    settings.t("regex.cheat.classes"))
                cheatRow("[abc] [^abc]",  settings.t("regex.cheat.charSet"))
                cheatRow("a* a+ a?",      settings.t("regex.cheat.quantifiers"))
                cheatRow("a{2,5}",        settings.t("regex.cheat.range"))
                cheatRow("(…)",           settings.t("regex.cheat.group"))
                cheatRow("(?:…)",         settings.t("regex.cheat.nonCapture"))
                cheatRow("(?<name>…)",    settings.t("regex.cheat.named"))
                cheatRow("(?=…) (?!…)",   settings.t("regex.cheat.lookahead"))
                cheatRow("a|b",           settings.t("regex.cheat.alt"))
            }
            Divider()
            Text(settings.t("regex.cheatsheet.replace"))
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                cheatRow("$1 $2",  settings.t("regex.cheat.backref"))
                cheatRow("$&",     settings.t("regex.cheat.fullMatch"))
                cheatRow(#"\$"#,   settings.t("regex.cheat.literalDollar"))
            }
        }
    }

    private func cheatRow(_ token: String, _ desc: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(token)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private func recompute() {
        guard !pattern.isEmpty else {
            errorMessage = nil
            matches = []
            nsRanges = []
            replaceOutput = ""
            replaceCount = 0
            return
        }
        do {
            let regex = try RegexEngine.compile(pattern, flags: flags)
            errorMessage = nil
            matches = RegexEngine.matches(regex: regex, in: testText)
            nsRanges = matches.compactMap { match in
                NSRange(match.range, in: testText)
            }
            if mode == .replace {
                let r = RegexEngine.replace(regex: regex, in: testText, with: replaceTemplate)
                replaceOutput = r.output
                replaceCount = r.replacedCount
            } else {
                replaceOutput = ""
                replaceCount = 0
            }
        } catch let RegexError.invalidPattern(msg) {
            errorMessage = msg
            matches = []
            nsRanges = []
            replaceOutput = ""
            replaceCount = 0
        } catch {
            errorMessage = error.localizedDescription
            matches = []
            nsRanges = []
        }
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

// MARK: - NSTextView wrapper with attributed-range highlighting

private struct HighlightedTextView: NSViewRepresentable {
    @Binding var text: String
    var ranges: [NSRange]
    var placeholder: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        tv.allowsUndo = true
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

        // Keep user typing position intact: only replace storage if it
        // actually differs (avoids resetting the insertion point on every
        // re-render).
        if tv.string != text {
            let selected = tv.selectedRange()
            tv.string = text
            // Restore caret if still in bounds.
            let len = tv.string.utf16.count
            if selected.location <= len {
                tv.setSelectedRange(NSRange(location: min(selected.location, len), length: 0))
            }
        }

        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: fullRange)
        storage.addAttribute(.foregroundColor,
                             value: NSColor.labelColor,
                             range: fullRange)
        storage.addAttribute(
            .font,
            value: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            range: fullRange
        )
        let highlight = NSColor.systemYellow.withAlphaComponent(0.35)
        for r in ranges where r.location + r.length <= storage.length {
            storage.addAttribute(.backgroundColor, value: highlight, range: r)
        }
        storage.endEditing()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedTextView
        init(_ parent: HighlightedTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

#Preview {
    RegexTesterView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 800)
}
