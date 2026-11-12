// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  QRGeneratorView.swift
//  DevPad
//
//  Two-mode QR tool:
//    • Generate — text/URL, VietQR bank transfer, Wi-Fi network or vCard
//                 contact → QR image, save as PNG, copy to clipboard. The
//                 structured types are built by `QRPayload.swift`.
//    • Scan     — drop, paste or point a camera at a QR → decode it back to
//                 its text; VietQR / Wi-Fi / vCard payloads are also shown
//                 as labelled fields with one-click copy.
//
//  Both modes share the same view; a segmented picker at the top
//  toggles between them.
//

import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

private enum QRMode: String, CaseIterable, Identifiable {
    case generate, scan
    var id: String { rawValue }
}

private enum PayloadKind: String, CaseIterable, Identifiable {
    case text, vietqr, wifi, vcard
    var id: String { rawValue }
}

private enum ScanSource: String, CaseIterable, Identifiable {
    case image, camera
    var id: String { rawValue }
}

struct QRGeneratorView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.isToolActive) private var isToolActive

    @State private var mode: QRMode = .generate

    // Generate state
    @State private var text: String = ""
    @State private var qrImage: NSImage?
    @State private var errorCorrection: QRCode.ErrorCorrection = .medium
    @State private var generateError: String?
    @State private var savedPath: String?
    @State private var centerIcon: NSImage?
    @State private var payloadKind: PayloadKind = .text

    // VietQR. Bank and account number are remembered on this Mac so a
    // recurring "pay me here" code is two clicks; Clear forgets them.
    @AppStorage("qr.vietqr.bin") private var vietBIN: String = ""
    @AppStorage("qr.vietqr.customBIN") private var vietCustomBIN: String = ""
    @AppStorage("qr.vietqr.account") private var vietAccount: String = ""
    @State private var vietAmount: String = ""
    @State private var vietMessage: String = ""

    // Wi-Fi. The password is never persisted.
    @State private var wifiSSID: String = ""
    @State private var wifiPassword: String = ""
    @State private var wifiSecurity: WiFiSecurity = .wpa
    @State private var wifiHidden = false

    // vCard
    @State private var card = ContactCard()

    private static let otherBIN = "other"

    // Scan state
    @State private var scanSource: ScanSource = .image
    @State private var scanImage: NSImage?
    @State private var decoded: String = ""
    @State private var showRawPayload = false
    @State private var scanError: String?
    @State private var isDropTargeted: Bool = false
    @StateObject private var camera = QRCamera()

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
        .onAppear {
            if DemoMode.isOn, text.isEmpty {
                switch DemoMode.qrKind {
                case "vietqr":
                    payloadKind = .vietqr
                    vietBIN = DemoMode.sampleVietQRBIN
                    vietAccount = DemoMode.sampleVietQRAccount
                    vietAmount = DemoMode.sampleVietQRAmount
                    vietMessage = DemoMode.sampleVietQRMessage
                case "wifi":
                    payloadKind = .wifi
                    wifiSSID = DemoMode.sampleWiFiSSID
                    wifiPassword = DemoMode.sampleWiFiPassword
                case "vcard":
                    payloadKind = .vcard
                    card = DemoMode.sampleCard
                default:
                    text = DemoMode.sampleQRText
                }
                generate()
                if DemoMode.qrScan, let payload = try? currentPayload() {
                    mode = .scan
                    decoded = payload
                }
            }
            camera.refreshPermission()
        }
        .onDisappear {
            // Always release the camera when the user leaves the QR tab —
            // no point keeping the webcam LED on otherwise.
            camera.stop()
        }
        // The tab stays mounted while another tool is showing, so onDisappear
        // doesn't fire on a tab switch; same release, keyed off visibility.
        .onChange(of: isToolActive) { active in
            if active {
                camera.refreshPermission()
            } else {
                camera.stop()
            }
        }
        .onChange(of: mode) { newValue in
            if newValue != .scan {
                camera.stop()
            } else if scanSource == .camera {
                camera.start()
            }
        }
        .onChange(of: scanSource) { newValue in
            if newValue == .camera {
                camera.start()
            } else {
                camera.stop()
            }
        }
        .onChange(of: camera.decoded) { newValue in
            if let value = newValue, !value.isEmpty {
                decoded = value
                scanError = nil
            }
        }
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
            payloadKindPicker
            payloadInput
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

    /// Switching type drops the preview: a QR made for another type would
    /// look like it belongs to the form that is now showing.
    private var payloadKindPicker: some View {
        let binding = Binding<PayloadKind>(
            get: { payloadKind },
            set: { newKind in
                payloadKind = newKind
                qrImage = nil
                generateError = nil
                savedPath = nil
            }
        )
        return Picker("", selection: binding) {
            Text(settings.t("qr.kind.text")).tag(PayloadKind.text)
            Text(settings.t("qr.kind.vietqr")).tag(PayloadKind.vietqr)
            Text(settings.t("qr.kind.wifi")).tag(PayloadKind.wifi)
            Text(settings.t("qr.kind.vcard")).tag(PayloadKind.vcard)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var payloadInput: some View {
        switch payloadKind {
        case .text:   inputEditor
        case .vietqr: vietQRForm
        case .wifi:   wifiForm
        case .vcard:  vcardForm
        }
    }

    // MARK: Structured forms

    private func fieldTitle(_ key: String) -> some View {
        Text(settings.t(key))
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func formField(_ text: Binding<String>, monospaced: Bool = false) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .frame(maxWidth: .infinity)
    }

    private func formPanel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var vietQRForm: some View {
        let note = VietQR.sanitizeMessage(vietMessage)
        let trimmed = vietMessage.trimmingCharacters(in: .whitespaces)
        return formPanel {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    fieldTitle("qr.vietqr.bank")
                    Picker("", selection: $vietBIN) {
                        Text(settings.t("qr.vietqr.bank.choose")).tag("")
                        ForEach(VietQR.banks) { bank in
                            Text(bank.name).tag(bank.bin)
                        }
                        Divider()
                        Text(settings.t("qr.vietqr.bank.other")).tag(Self.otherBIN)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    fieldTitle("qr.vietqr.account")
                    formField($vietAccount, monospaced: true)
                }
                if vietBIN == Self.otherBIN {
                    GridRow {
                        fieldTitle("qr.vietqr.bin")
                        formField($vietCustomBIN, monospaced: true)
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
                GridRow {
                    fieldTitle("qr.vietqr.amount")
                    formField($vietAmount, monospaced: true)
                    fieldTitle("qr.vietqr.message")
                    formField($vietMessage)
                }
            }
            HStack(spacing: 8) {
                Text(settings.t("qr.vietqr.hint"))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                if !vietMessage.isEmpty {
                    Text(settings.t("qr.vietqr.messageCountFmt", note.count, VietQR.recommendedMessageLength))
                        .foregroundStyle(note.count > VietQR.recommendedMessageLength ? Color.orange : Color.secondary)
                        .monospacedDigit()
                }
            }
            .font(.caption)
            if !trimmed.isEmpty, note != trimmed {
                Text(settings.t("qr.vietqr.accentsRemoved", note))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if note.count > VietQR.recommendedMessageLength {
                Text(settings.t("qr.vietqr.messageLong", VietQR.recommendedMessageLength))
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private var wifiForm: some View {
        formPanel {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    fieldTitle("qr.wifi.ssid")
                    formField($wifiSSID)
                    fieldTitle("qr.wifi.security")
                    Picker("", selection: $wifiSecurity) {
                        Text(settings.t("qr.wifi.security.wpa")).tag(WiFiSecurity.wpa)
                        Text(settings.t("qr.wifi.security.wep")).tag(WiFiSecurity.wep)
                        Text(settings.t("qr.wifi.security.none")).tag(WiFiSecurity.none)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    fieldTitle("qr.wifi.password")
                    formField($wifiPassword, monospaced: true)
                        .disabled(wifiSecurity == .none)
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle(settings.t("qr.wifi.hidden"), isOn: $wifiHidden)
                        .toggleStyle(.checkbox)
                }
            }
            Text(settings.t("qr.wifi.hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var vcardForm: some View {
        formPanel {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    fieldTitle("qr.vcard.firstName")
                    formField($card.firstName)
                    fieldTitle("qr.vcard.lastName")
                    formField($card.lastName)
                }
                GridRow {
                    fieldTitle("qr.vcard.organization")
                    formField($card.organization)
                    fieldTitle("qr.vcard.title")
                    formField($card.title)
                }
                GridRow {
                    fieldTitle("qr.vcard.phone")
                    formField($card.mobile, monospaced: true)
                    fieldTitle("qr.vcard.email")
                    formField($card.email)
                }
                GridRow {
                    fieldTitle("qr.vcard.website")
                    formField($card.website)
                        .gridCellColumns(3)
                }
            }
        }
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

            if payloadKind == .text {
                Button {
                    paste()
                } label: {
                    Label(settings.t("common.paste"), systemImage: "doc.on.clipboard")
                }
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
            scanSourcePicker
            switch scanSource {
            case .image:  dropZone
            case .camera: cameraScanView
            }
            // Surface either the file-scan error or a camera-engine error
            // (rare: "no device" / "can't add input"). They're mutually
            // exclusive in practice because each is tied to its own
            // sub-mode, so prefer whichever applies to the active source.
            if let scanError {
                errorBanner(scanError)
            } else if scanSource == .camera, let camErr = camera.errorMessage {
                errorBanner(camErr)
            }
            decodedTextArea
        }
    }

    private var scanSourcePicker: some View {
        Picker("", selection: $scanSource) {
            Label(settings.t("qr.scan.source.image"),
                  systemImage: "photo").tag(ScanSource.image)
            Label(settings.t("qr.scan.source.camera"),
                  systemImage: "camera").tag(ScanSource.camera)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 280)
    }

    // MARK: - Camera scan

    @ViewBuilder
    private var cameraScanView: some View {
        switch camera.permission {
        case .notDetermined: cameraPermissionRequest
        case .denied, .restricted: cameraPermissionDenied
        case .authorized: cameraPreviewPanel
        }
    }

    private var cameraPermissionRequest: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("qr.scan.camera.permission"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                camera.requestAccess()
            } label: {
                Label(settings.t("qr.scan.camera.allow"),
                      systemImage: "camera.fill")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
    }

    private var cameraPermissionDenied: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.red)
            Text(settings.t("qr.scan.camera.denied"))
                .font(.headline)
            Text(settings.t("qr.scan.camera.deniedHint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                camera.openSystemSettings()
            } label: {
                Label(settings.t("qr.scan.camera.openSettings"),
                      systemImage: "gear")
                    .frame(minWidth: 200)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.red.opacity(0.25))
        )
    }

    private var cameraPreviewPanel: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                CameraPreviewView(session: camera.session)
                    .frame(minHeight: 280, maxHeight: 360)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10,
                                                style: .continuous))

                if !camera.isRunning {
                    // Dim overlay while session is stopped so the panel
                    // doesn't look like a frozen frame.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(settings.t("qr.scan.camera.stopped"))
                            .foregroundStyle(.white.opacity(0.9))
                            .font(.callout)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            HStack(spacing: 8) {
                if camera.isRunning {
                    Button {
                        camera.stop()
                    } label: {
                        Label(settings.t("qr.scan.camera.stop"),
                              systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        camera.start()
                    } label: {
                        Label(settings.t("qr.scan.camera.start"),
                              systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if !decoded.isEmpty {
                    Button(role: .destructive) {
                        decoded = ""
                        camera.clearDecoded()
                    } label: {
                        Label(settings.t("common.clear"), systemImage: "trash")
                    }
                }
                Spacer()
                Text(camera.isRunning
                     ? settings.t("qr.scan.camera.hint.running")
                     : settings.t("qr.scan.camera.hint.idle"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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

    /// One labelled value of a recognised payload. `copy` is what the copy
    /// button puts on the pasteboard (e.g. the bare digits of an amount).
    private struct PayloadRow {
        let label: String
        let value: String
        let copy: String
    }

    @ViewBuilder
    private var decodedTextArea: some View {
        if !decoded.isEmpty {
            let kind = QRPayload.classify(decoded)
            let rows = payloadRows(kind)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(rows.isEmpty
                         ? settings.t("qr.scan.result")
                         : settings.t("qr.scan.detectedFmt", kindName(kind)))
                        .font(.headline)
                    Spacer()
                    // `URL(string:)` happily parses "WIFI:T:WPA;…" as a URL with
                    // a "wifi" scheme, so only offer Open for plain text.
                    if rows.isEmpty, URL(string: decoded)?.scheme != nil {
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
                if rows.isEmpty {
                    rawPayloadBox
                        .frame(minHeight: 80, maxHeight: .infinity)
                } else {
                    payloadCard(rows)
                    DisclosureGroup(settings.t("qr.scan.raw"), isExpanded: $showRawPayload) {
                        rawPayloadBox
                            .frame(height: 90)
                    }
                }
            }
        }
    }

    private var rawPayloadBox: some View {
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
    }

    private func payloadCard(_ rows: [PayloadRow]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 12) {
                        Text(row.label)
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(row.value)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            copyText(row.copy)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(settings.t("common.copy"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    if index < rows.count - 1 { Divider() }
                }
            }
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

    private func kindName(_ kind: QRPayloadKind) -> String {
        switch kind {
        case .vietQR: return settings.t("qr.kind.vietqr")
        case .wifi:   return settings.t("qr.kind.wifi")
        case .vcard:  return settings.t("qr.kind.vcard")
        case .text:   return settings.t("qr.kind.text")
        }
    }

    /// Empty for plain text, which is shown as-is.
    private func payloadRows(_ kind: QRPayloadKind) -> [PayloadRow] {
        func row(_ key: String, _ value: String, copy: String? = nil) -> PayloadRow {
            PayloadRow(label: settings.t(key), value: value, copy: copy ?? value)
        }
        switch kind {
        case .text:
            return []
        case .vietQR(let info):
            var rows = [
                row("qr.vietqr.bank", VietQR.bankName(forBIN: info.bin) ?? "BIN \(info.bin)", copy: info.bin),
                row("qr.vietqr.account", info.account),
                info.amount.map { row("qr.vietqr.amount", formatVND($0), copy: String($0)) }
                    ?? row("qr.vietqr.amount", settings.t("qr.scan.noAmount"), copy: "")
            ]
            if let message = info.message, !message.isEmpty { rows.append(row("qr.vietqr.message", message)) }
            return rows
        case .wifi(let info):
            var rows = [row("qr.wifi.ssid", info.ssid)]
            if info.security != .none { rows.append(row("qr.wifi.password", info.password)) }
            rows.append(row("qr.wifi.security", settings.t(securityKey(info.security))))
            if info.hidden { rows.append(row("qr.wifi.hidden", settings.t("qr.scan.yes"))) }
            return rows
        case .vcard(let info):
            var rows: [PayloadRow] = []
            if !info.name.isEmpty { rows.append(row("qr.scan.field.name", info.name)) }
            if !info.organization.isEmpty { rows.append(row("qr.vcard.organization", info.organization)) }
            if !info.title.isEmpty { rows.append(row("qr.vcard.title", info.title)) }
            rows += info.phones.map { row("qr.vcard.phone", $0) }
            rows += info.emails.map { row("qr.vcard.email", $0) }
            rows += info.urls.map { row("qr.vcard.website", $0) }
            return rows
        }
    }

    private func securityKey(_ security: WiFiSecurity) -> String {
        switch security {
        case .wpa:  return "qr.wifi.security.wpa"
        case .wep:  return "qr.wifi.security.wep"
        case .none: return "qr.wifi.security.none"
        }
    }

    private func formatVND(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: settings.language.resolvedCode)
        return (f.string(from: NSNumber(value: amount)) ?? String(amount)) + " VND"
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

    /// The string the current form encodes. Engine errors are English
    /// (see `devpad-conventions`); the banner adds the localized prefix.
    private func currentPayload() throws -> String {
        switch payloadKind {
        case .text:
            return text
        case .vietqr:
            guard !vietBIN.isEmpty else { throw QRPayloadError.bankRequired }
            return try VietQR.build(
                bin: vietBIN == Self.otherBIN ? vietCustomBIN : vietBIN,
                account: vietAccount,
                amount: try VietQR.parseAmount(vietAmount),
                message: vietMessage
            )
        case .wifi:
            return try WiFiQR.build(ssid: wifiSSID, password: wifiPassword,
                                    security: wifiSecurity, hidden: wifiHidden)
        case .vcard:
            return try VCardQR.build(card)
        }
    }

    private func generate() {
        savedPath = nil
        do {
            qrImage = try QRCode.generate(
                try currentPayload(),
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
        switch payloadKind {
        case .text:
            text = ""
        case .vietqr:
            // Also forgets the remembered bank and account number.
            vietBIN = ""
            vietCustomBIN = ""
            vietAccount = ""
            vietAmount = ""
            vietMessage = ""
        case .wifi:
            wifiSSID = ""
            wifiPassword = ""
            wifiSecurity = .wpa
            wifiHidden = false
        case .vcard:
            card = ContactCard()
        }
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

// MARK: - Camera preview bridge

/// Thin SwiftUI wrapper around `AVCaptureVideoPreviewLayer`. The view is
/// **layer-hosting** rather than layer-backed: AppKit's rule is that to
/// substitute your own `CALayer` you must override `makeBackingLayer()`
/// and return the layer there, *then* set `wantsLayer = true`. Doing the
/// reverse — setting `wantsLayer = true` first and then assigning
/// `layer = …` — leaves the auto-created AppKit layer in place on some
/// macOS versions and is what triggered the original `EXC_BAD_ACCESS`.
private struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let v = PreviewNSView()
        v.previewLayer.session = session
        return v
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
    }

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func makeBackingLayer() -> CALayer {
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.contentsGravity = .resizeAspectFill
            return previewLayer
        }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}

#Preview {
    QRGeneratorView()
        .environmentObject(AppSettings.shared)
        .frame(width: 900, height: 700)
}
