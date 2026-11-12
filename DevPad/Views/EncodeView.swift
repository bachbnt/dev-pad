// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  EncodeView.swift
//  DevPad
//
//  Base64 / Base64URL / URL percent-encoding tool. The top picker chooses the
//  scheme, a second picker the direction; the work is done by `EncodeEngine`
//  on demand (`⌘↵`) like every other text tool. "Use as input" feeds the
//  result back in with the direction flipped, which is the quickest way to
//  check a round trip.
//

import SwiftUI
import AppKit

private enum EncodeDirection: String, CaseIterable, Identifiable {
    case encode, decode
    var id: String { rawValue }
}

struct EncodeView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var mode: EncodeMode = .base64
    @State private var direction: EncodeDirection = .encode
    @State private var input: String = ""
    @State private var output: String = ""
    @State private var hasResult = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            modePicker
            inputEditor
            optionsBar
            if let errorMessage { errorBanner(errorMessage) }
            if hasResult { outputView } else if errorMessage == nil { placeholder }
            actionBar
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if DemoMode.isOn, input.isEmpty {
                input = DemoMode.sampleEncodeText
                run()
            }
        }
        // A result computed for another scheme / direction would look like it
        // belongs to the current settings.
        .onChange(of: mode) { _ in clearResult() }
        .onChange(of: direction) { _ in clearResult() }
    }

    // MARK: - Pieces

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text(settings.t("encode.mode.base64")).tag(EncodeMode.base64)
            Text(settings.t("encode.mode.base64url")).tag(EncodeMode.base64url)
            Text(settings.t("encode.mode.url")).tag(EncodeMode.url)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
    }

    private var inputEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            TextEditor(text: $input)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
            if input.isEmpty {
                Text(settings.t("encode.input.placeholder"))
                    .foregroundStyle(.tertiary)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 13)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 120, maxHeight: 200)
    }

    private var optionsBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $direction) {
                Text(settings.t("encode.direction.encode")).tag(EncodeDirection.encode)
                Text(settings.t("encode.direction.decode")).tag(EncodeDirection.decode)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            Spacer()
            Button {
                useOutputAsInput()
            } label: {
                Label(settings.t("encode.useAsInput"), systemImage: "arrow.up.doc")
            }
            .disabled(!hasResult)
            Button {
                copy(output)
            } label: {
                Label(settings.t("common.copy"), systemImage: "doc.on.doc")
            }
            .disabled(!hasResult)
        }
    }

    private var outputView: some View {
        ScrollView {
            Text(output)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
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

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "textformat.abc")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("encode.empty.title")).font(.headline)
            Text(settings.t("encode.empty.hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack {
            Spacer()
            Button {
                run()
            } label: {
                Label(settings.t(direction == .encode ? "encode.run.encode" : "encode.run.decode"),
                      systemImage: direction == .encode ? "arrow.right.circle" : "arrow.left.circle")
                    .frame(minWidth: 120)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(input.isEmpty)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text("\(settings.t("encode.error.prefix")): \(message)")
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

    // MARK: - Actions

    private func run() {
        guard !input.isEmpty else { return }
        do {
            switch direction {
            case .encode: output = EncodeEngine.encode(input, mode: mode)
            case .decode: output = try EncodeEngine.decode(input, mode: mode)
            }
            hasResult = true
            errorMessage = nil
        } catch {
            output = ""
            hasResult = false
            errorMessage = error.localizedDescription
        }
    }

    private func clearResult() {
        output = ""
        hasResult = false
        errorMessage = nil
    }

    private func useOutputAsInput() {
        input = output
        direction = direction == .encode ? .decode : .encode
        // `direction` just changed, so the onChange above wipes the result.
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

#Preview {
    EncodeView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 700)
}
