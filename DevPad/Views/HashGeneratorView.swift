//
//  HashGeneratorView.swift
//  DevPad
//
//  Three-mode tool that produces digests for the five most common hash
//  algorithms (MD5 / SHA-1 / SHA-256 / SHA-384 / SHA-512):
//    • Text — type or paste a string, see every algorithm's hash live.
//    • File — drop a file (or pick one) and have each hash streamed off
//             the main thread.
//    • HMAC — message + secret key + SHA-family algorithm → one HMAC.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum HashMode: String, CaseIterable, Identifiable {
    case text, file, hmac
    var id: String { rawValue }
}

struct HashGeneratorView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var mode: HashMode = .text

    // Shared
    @State private var format: HashFormat = .hex
    @State private var compareWith: String = ""

    // Text mode
    @State private var inputText: String = ""
    @State private var textDigests: [HashAlgorithm: Data] = [:]

    // File mode
    @State private var droppedURL: URL?
    @State private var fileSize: Int64 = 0
    @State private var fileDigests: [HashAlgorithm: Data] = [:]
    @State private var fileHashing = false
    @State private var fileError: String?
    @State private var isDropTargeted = false

    // HMAC mode
    @State private var hmacMessage: String = ""
    @State private var hmacKey: String = ""
    @State private var hmacAlgorithm: HashAlgorithm = .sha256
    @State private var hmacDigest: Data?

    var body: some View {
        VStack(spacing: 12) {
            modePicker
            switch mode {
            case .text: textView
            case .file: fileView
            case .hmac: hmacView
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if DemoMode.isOn, inputText.isEmpty, mode == .text {
                inputText = DemoMode.sampleHashText
                recompute()
            }
        }
        // Clear stale digests when the user switches modes so the new mode's
        // output doesn't look out-of-date with the new input.
        .onChange(of: mode) { _ in
            textDigests = [:]
            hmacDigest = nil
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text(settings.t("hash.mode.text")).tag(HashMode.text)
            Text(settings.t("hash.mode.file")).tag(HashMode.file)
            Text(settings.t("hash.mode.hmac")).tag(HashMode.hmac)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 380)
    }

    // MARK: - Format + compare bar (shared by Text / File modes)

    private var sharedActionBar: some View {
        HStack(spacing: 12) {
            Text(settings.t("hash.format"))
                .foregroundStyle(.secondary)
            Picker("", selection: $format) {
                ForEach(HashFormat.allCases) { f in
                    Text(settings.t(f.labelKey)).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            Spacer()
            Button {
                copy(copyAllString)
            } label: {
                Label(settings.t("hash.copyAll"), systemImage: "doc.on.doc")
            }
            .disabled(currentDigests.isEmpty)
        }
    }

    private var compareBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.secondary)
            Text(settings.t("hash.compare"))
                .foregroundStyle(.secondary)
            TextField(settings.t("hash.compare.placeholder"), text: $compareWith)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced))
            if !compareWith.isEmpty {
                Button {
                    compareWith = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(settings.t("common.clear"))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
        )
    }

    // MARK: - Text mode

    private var textView: some View {
        VStack(spacing: 10) {
            inputEditor
            sharedActionBar
            digestTable(digests: textDigests)
            compareBar
            textRunBar
        }
    }

    private var textRunBar: some View {
        HStack {
            Spacer()
            Button {
                recompute()
            } label: {
                Label(settings.t("hash.run.text"), systemImage: "number")
                    .frame(minWidth: 120)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(inputText.isEmpty)
        }
    }

    private var inputEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            TextEditor(text: $inputText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
            if inputText.isEmpty {
                Text(settings.t("hash.input.placeholder"))
                    .foregroundStyle(.tertiary)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 13)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 120, maxHeight: 200)
    }

    // MARK: - File mode

    private var fileView: some View {
        VStack(spacing: 10) {
            dropZone
            if let error = fileError {
                errorBanner(error)
            }
            if droppedURL != nil {
                sharedActionBar
                digestTable(digests: fileDigests, busy: fileHashing)
                compareBar
            }
        }
    }

    private var dropZone: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                if let url = droppedURL {
                    Text(url.lastPathComponent)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(fileSizeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(settings.t("hash.file.dropHint"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(settings.t("hash.file.dropSub"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                chooseFile()
            } label: {
                Label(settings.t("hash.file.choose"), systemImage: "folder")
            }
            if droppedURL != nil {
                Button(role: .destructive) {
                    clearFile()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(settings.t("common.clear"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDropTargeted
                      ? Color.accentColor.opacity(0.08)
                      : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                              style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1,
                                                 dash: droppedURL == nil ? [6] : []))
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { setFile(url) }
            }
            return true
        }
    }

    private var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    // MARK: - HMAC mode

    private var hmacView: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                hmacEditor(title: settings.t("hash.hmac.message"), text: $hmacMessage)
                hmacEditor(title: settings.t("hash.hmac.key"), text: $hmacKey, secure: true)
            }
            .frame(minHeight: 140, maxHeight: 200)

            HStack(spacing: 12) {
                Text(settings.t("hash.hmac.algorithm"))
                    .foregroundStyle(.secondary)
                Picker("", selection: $hmacAlgorithm) {
                    ForEach(HashAlgorithm.hmacAlgorithms) { a in
                        Text(a.rawValue).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)

                Text(settings.t("hash.format"))
                    .foregroundStyle(.secondary)
                Picker("", selection: $format) {
                    ForEach(HashFormat.allCases) { f in
                        Text(settings.t(f.labelKey)).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)

                Spacer()
                Button {
                    if let digest = hmacDigest {
                        copy(Hashing.encode(digest, format: format))
                    }
                } label: {
                    Label(settings.t("common.copy"), systemImage: "doc.on.doc")
                }
                .disabled(hmacDigest == nil)
            }

            hmacOutputView
            compareBar
            hmacRunBar
        }
    }

    private var hmacRunBar: some View {
        HStack {
            Spacer()
            Button {
                recompute()
            } label: {
                Label(settings.t("hash.run.hmac"), systemImage: "signature")
                    .frame(minWidth: 120)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(hmacMessage.isEmpty || hmacKey.isEmpty)
        }
    }

    private func hmacEditor(title: String,
                            text: Binding<String>,
                            secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            if secure {
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
                        Text(settings.t("hash.hmac.key.placeholder"))
                            .foregroundStyle(.tertiary)
                            .font(.system(.body, design: .monospaced))
                            .padding(.leading, 13)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            } else {
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
                        Text(settings.t("hash.hmac.message.placeholder"))
                            .foregroundStyle(.tertiary)
                            .font(.system(.body, design: .monospaced))
                            .padding(.leading, 13)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var hmacOutputView: some View {
        let raw = hmacDigest.map { Hashing.encode($0, format: format) } ?? ""
        let matches = !compareWith.isEmpty && Hashing.looselyEqual(compareWith, raw)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(settings.t("hash.hmac.output"))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if matches {
                    Label(settings.t("hash.compare.match"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                Spacer()
            }
            Text(raw.isEmpty ? settings.t("hash.hmac.empty") : raw)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
                .foregroundStyle(raw.isEmpty
                                 ? AnyShapeStyle(HierarchicalShapeStyle.tertiary)
                                 : AnyShapeStyle(.primary))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(matches
                              ? Color.green.opacity(0.10)
                              : Color.secondary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(matches ? Color.green.opacity(0.4) : Color.clear)
                )
        }
    }

    // MARK: - Digest table (Text + File modes)

    private func digestTable(digests: [HashAlgorithm: Data],
                             busy: Bool = false) -> some View {
        VStack(spacing: 0) {
            ForEach(HashAlgorithm.allCases) { algo in
                digestRow(algorithm: algo, digest: digests[algo], busy: busy)
                if algo != HashAlgorithm.allCases.last {
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func digestRow(algorithm: HashAlgorithm,
                           digest: Data?,
                           busy: Bool) -> some View {
        let encoded = digest.map { Hashing.encode($0, format: format) } ?? ""
        let matches = !compareWith.isEmpty && Hashing.looselyEqual(compareWith, encoded)

        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(algorithm.rawValue)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Group {
                if busy, digest == nil {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(settings.t("hash.hashing"))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if encoded.isEmpty {
                    Text("—")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(encoded)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if matches {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .help(settings.t("hash.compare.match"))
            }

            Button {
                copy(encoded)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(encoded.isEmpty)
            .help(settings.t("common.copy"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(matches ? Color.green.opacity(0.10) : Color.clear)
    }

    // MARK: - Banners

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("\(settings.t("hash.error.prefix")): \(message)")
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

    // MARK: - Computed helpers

    private var currentDigests: [HashAlgorithm: Data] {
        switch mode {
        case .text: return textDigests
        case .file: return fileDigests
        case .hmac: return hmacDigest.map { [hmacAlgorithm: $0] } ?? [:]
        }
    }

    private var copyAllString: String {
        HashAlgorithm.allCases.compactMap { algo in
            guard let d = currentDigests[algo] else { return nil }
            return "\(algo.rawValue): \(Hashing.encode(d, format: format))"
        }.joined(separator: "\n")
    }

    // MARK: - Actions

    private func recompute() {
        switch mode {
        case .text:
            let data = Data(inputText.utf8)
            if inputText.isEmpty {
                textDigests = [:]
            } else {
                var out: [HashAlgorithm: Data] = [:]
                for algo in HashAlgorithm.allCases {
                    out[algo] = Hashing.hash(data, algorithm: algo)
                }
                textDigests = out
            }
        case .hmac:
            guard !hmacMessage.isEmpty else {
                hmacDigest = nil
                return
            }
            let msg = Data(hmacMessage.utf8)
            let key = Data(hmacKey.utf8)
            hmacDigest = Hashing.hmac(msg, key: key, algorithm: hmacAlgorithm)
        case .file:
            break  // file mode hashes immediately on drop / pick.
        }
    }

    private func setFile(_ url: URL) {
        droppedURL = url
        fileDigests = [:]
        fileError = nil
        if let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? NSNumber {
            fileSize = size.int64Value
        } else {
            fileSize = 0
        }
        fileHashing = true
        Task.detached {
            do {
                var out: [HashAlgorithm: Data] = [:]
                for algo in HashAlgorithm.allCases {
                    let d = try Hashing.hashFile(at: url, algorithm: algo)
                    out[algo] = d
                }
                // Freeze the dictionary into an immutable `let` before
                // crossing the actor boundary; Swift 6 forbids capturing
                // mutable `var` state in concurrent closures.
                let finalDigests = out
                await MainActor.run {
                    self.fileDigests = finalDigests
                    self.fileHashing = false
                }
            } catch {
                let message = error.localizedDescription
                await MainActor.run {
                    self.fileError = message
                    self.fileHashing = false
                }
            }
        }
    }

    private func clearFile() {
        droppedURL = nil
        fileDigests = [:]
        fileSize = 0
        fileError = nil
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            setFile(url)
        }
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

#Preview {
    HashGeneratorView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 800)
}
