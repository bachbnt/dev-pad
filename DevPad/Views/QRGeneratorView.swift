//
//  QRGeneratorView.swift
//  DevPad
//
//  Two-mode QR tool:
//    • Generate — text/URL → QR image, save as PNG, copy to clipboard.
//    • Scan     — drop or open an image → decode the embedded QR back to
//                 its original text.
//
//  Both modes share the same view; a segmented picker at the top
//  toggles between them.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum QRMode: String, CaseIterable, Identifiable {
    case generate, scan
    var id: String { rawValue }
}

struct QRGeneratorView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var mode: QRMode = .generate

    // Generate state
    @State private var text: String = ""
    @State private var qrImage: NSImage?
    @State private var errorCorrection: QRCode.ErrorCorrection = .medium
    @State private var generateError: String?
    @State private var savedPath: String?
    @State private var centerIcon: NSImage?

    // Scan state
    @State private var scanImage: NSImage?
    @State private var decoded: String = ""
    @State private var scanError: String?
    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            modePicker
            switch mode {
            case .generate: generateView
            case .scan:     scanView
            }
        }
        // Pin the mode picker to the top regardless of which tab is
        // active — without this, a tab whose content has no
        // `.frame(maxHeight: .infinity)` (like Scan) collapses to its
        // intrinsic size and SwiftUI ends up centring everything
        // vertically.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text(settings.t("qr.mode.generate")).tag(QRMode.generate)
            Text(settings.t("qr.mode.scan")).tag(QRMode.scan)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
    }

    // MARK: - Generate

    private var generateView: some View {
        VStack(spacing: 12) {
            inputEditor
            generateControls
            centerIconRow
            if let generateError {
                errorBanner(generateError)
            }
            if let savedPath {
                savedBanner(savedPath)
            }
            qrPreview
        }
    }

    /// Row letting the user attach a small logo overlay to the centre of
    /// the generated QR. Stored as `centerIcon` and passed to
    /// `QRCode.generate(...)` next time the user hits Generate.
    private var centerIconRow: some View {
        HStack(spacing: 10) {
            Text(settings.t("qr.centerIcon"))
                .foregroundStyle(.secondary)
                .font(.callout)

            if let centerIcon {
                Image(nsImage: centerIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25))
                    )

                Button(role: .destructive) {
                    self.centerIcon = nil
                } label: {
                    Label(settings.t("qr.centerIcon.remove"), systemImage: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    chooseCenterIcon()
                } label: {
                    Label(settings.t("qr.centerIcon.add"), systemImage: "photo.badge.plus")
                }
            }

            Spacer()

            if centerIcon != nil {
                Text(settings.t("qr.centerIcon.hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 320, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var inputEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
            if text.isEmpty {
                Text(settings.t("qr.placeholder"))
                    .foregroundStyle(.tertiary)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 13)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 100, maxHeight: 160)
    }

    private var generateControls: some View {
        HStack(spacing: 12) {
            Text(settings.t("qr.errorCorrection"))
                .foregroundStyle(.secondary)
            Picker(settings.t("qr.errorCorrection"), selection: $errorCorrection) {
                ForEach(QRCode.ErrorCorrection.allCases) { lvl in
                    Text(settings.t(lvl.labelKey)).tag(lvl)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 220)

            Spacer()

            Button {
                paste()
            } label: {
                Label(settings.t("common.paste"), systemImage: "doc.on.clipboard")
            }
            Button(role: .destructive) {
                clearGenerate()
            } label: {
                Label(settings.t("common.clear"), systemImage: "trash")
            }
            Button {
                generate()
            } label: {
                Label(settings.t("qr.generate"), systemImage: "qrcode")
                    .frame(minWidth: 100)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var qrPreview: some View {
        if let img = qrImage {
            VStack(spacing: 12) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 320)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.25))
                    )

                HStack(spacing: 8) {
                    Button {
                        copyImage(img)
                    } label: {
                        Label(settings.t("qr.copy"), systemImage: "doc.on.doc")
                    }
                    Button {
                        saveAsPNG(img)
                    } label: {
                        Label(settings.t("qr.save"), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "qrcode")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text(settings.t("qr.mode.generate"))
                    .font(.headline)
                Text(settings.t("qr.placeholder"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Scan

    private var scanView: some View {
        VStack(spacing: 12) {
            dropZone
            if let scanError {
                errorBanner(scanError)
            }
            decodedTextArea
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isDropTargeted
                                ? Color.accentColor.opacity(0.08)
                                : Color.secondary.opacity(0.05)
                        )
                )

            if let img = scanImage {
                VStack(spacing: 8) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .padding(8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    HStack(spacing: 8) {
                        Button {
                            chooseFile()
                        } label: {
                            Label(settings.t("qr.scan.choose"), systemImage: "folder")
                        }
                        Button(role: .destructive) {
                            scanImage = nil
                            decoded = ""
                            scanError = nil
                        } label: {
                            Label(settings.t("common.clear"), systemImage: "trash")
                        }
                    }
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                    Text(settings.t("qr.scan.dropHint"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    HStack(spacing: 8) {
                        Button {
                            chooseFile()
                        } label: {
                            Label(settings.t("qr.scan.choose"), systemImage: "folder")
                        }
                        Button {
                            pasteImageFromClipboard()
                        } label: {
                            Label(settings.t("qr.scan.paste"), systemImage: "doc.on.clipboard")
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minHeight: 220, maxHeight: 260)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    @ViewBuilder
    private var decodedTextArea: some View {
        if !decoded.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(settings.t("qr.scan.result"))
                        .font(.headline)
                    Spacer()
                    if URL(string: decoded)?.scheme != nil {
                        Button {
                            if let url = URL(string: decoded) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label(settings.t("qr.scan.openLink"), systemImage: "arrow.up.right.square")
                        }
                    }
                    Button {
                        copyText(decoded)
                    } label: {
                        Label(settings.t("qr.scan.copy"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                }
                ScrollView {
                    Text(decoded)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
                .frame(minHeight: 80, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Banners

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("\(settings.t("qr.error.prefix")): \(message)")
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

    private func savedBanner(_ path: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(settings.t("qr.saved", path))
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                savedPath = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.10))
        )
    }

    // MARK: - Generate actions

    private func generate() {
        savedPath = nil
        do {
            qrImage = try QRCode.generate(
                text,
                errorCorrection: errorCorrection,
                centerIcon: centerIcon
            )
            generateError = nil
        } catch {
            qrImage = nil
            generateError = error.localizedDescription
        }
    }

    private func chooseCenterIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK,
           let url = panel.url,
           let img = NSImage(contentsOf: url) {
            centerIcon = img
        }
    }

    private func saveAsPNG(_ image: NSImage) {
        guard let png = QRCode.pngData(from: image) else {
            generateError = settings.t("qr.error.invalidImage")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "qrcode.png"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try png.write(to: url)
                savedPath = url.path
                generateError = nil
            } catch {
                generateError = error.localizedDescription
            }
        }
    }

    private func copyImage(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    private func paste() {
        if let s = NSPasteboard.general.string(forType: .string) {
            text = s
            generateError = nil
        }
    }

    private func clearGenerate() {
        text = ""
        qrImage = nil
        centerIcon = nil
        generateError = nil
        savedPath = nil
    }

    // MARK: - Scan actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let img = NSImage(contentsOf: url) {
            decodeImage(img)
        }
    }

    private func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = imgs.first {
            decodeImage(img)
        } else {
            scanError = settings.t("qr.error.invalidImage")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // First try the file-URL representation (Finder drags).
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let img = NSImage(contentsOf: url) else { return }
                Task { @MainActor in self.decodeImage(img) }
            }
            return true
        }
        // Otherwise pull the image data directly (browser drag, etc.).
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let img = obj as? NSImage else { return }
                Task { @MainActor in self.decodeImage(img) }
            }
            return true
        }
        return false
    }

    private func decodeImage(_ image: NSImage) {
        scanImage = image
        do {
            decoded = try QRCode.decode(image)
            scanError = nil
        } catch {
            decoded = ""
            scanError = error.localizedDescription
        }
    }

    private func copyText(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

#Preview {
    QRGeneratorView()
        .environmentObject(AppSettings.shared)
        .frame(width: 900, height: 700)
}
