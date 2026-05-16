// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  XMLFormatterView.swift
//  DevPad
//
//  Single-textbox XML formatter — same UX as the JSON formatter view.
//

import SwiftUI
import AppKit

struct XMLFormatterView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var text: String = ""
    @State private var errorDetails: String?
    @State private var indent: Int = 2

    var body: some View {
        VStack(spacing: 12) {
            controlBar
            editor
            if let errorDetails {
                errorBanner(errorDetails)
            }
            footerBar
        }
        .padding(16)
        .onAppear {
            if DemoMode.isOn, text.isEmpty {
                text = DemoMode.sampleXML
                format()
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            Text(settings.t("common.indent"))
                .foregroundStyle(.secondary)
            Picker(settings.t("common.indent"), selection: $indent) {
                Text(settings.t("common.indent.2")).tag(2)
                Text(settings.t("common.indent.4")).tag(4)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            Spacer()
            Button {
                paste()
            } label: {
                Label(settings.t("common.paste"), systemImage: "doc.on.clipboard")
            }
            Button(role: .destructive) {
                clear()
            } label: {
                Label(settings.t("common.clear"), systemImage: "trash")
            }
        }
    }

    private var editor: some View {
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
                Text(settings.t("xml.placeholder"))
                    .foregroundStyle(.tertiary)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 13)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("\(settings.t("xml.error.prefix")): \(message)")
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

    private var footerBar: some View {
        HStack(spacing: 8) {
            Button {
                copyOut()
            } label: {
                Label(settings.t("common.copy"), systemImage: "doc.on.doc")
            }
            Spacer()
            Button {
                format()
            } label: {
                Label(settings.t("common.format"), systemImage: "wand.and.stars")
                    .frame(minWidth: 100)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func format() {
        do {
            text = try XMLFormatter.format(text, indent: indent)
            errorDetails = nil
        } catch {
            errorDetails = error.localizedDescription
        }
    }

    private func paste() {
        if let s = NSPasteboard.general.string(forType: .string) {
            text = s
            errorDetails = nil
        }
    }

    private func copyOut() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func clear() {
        text = ""
        errorDetails = nil
    }
}

#Preview {
    XMLFormatterView()
        .environmentObject(AppSettings.shared)
        .frame(width: 800, height: 600)
}
