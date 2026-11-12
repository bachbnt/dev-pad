// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  UUIDGeneratorView.swift
//  DevPad
//
//  Generates UUID v4, UUID v7 or ULID identifiers in batches of up to 100.
//  This tool has no input to validate, so its primary button (`⌘↵`) is
//  always enabled. Each row has its own copy button; "Copy all" joins the
//  batch with newlines.
//

import SwiftUI
import AppKit

struct UUIDGeneratorView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var kind: IDKind = .uuidV4
    @State private var count: Int = 1
    @State private var uppercase = false
    @State private var hyphens = true
    @State private var ids: [String] = []

    var body: some View {
        VStack(spacing: 12) {
            kindPicker
            optionsBar
            if ids.isEmpty { placeholder } else { resultList }
            actionBar
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if DemoMode.isOn, ids.isEmpty {
                count = 5
                generate()
            }
        }
        // IDs of another kind would look like they match the new selection.
        .onChange(of: kind) { _ in ids = [] }
    }

    // MARK: - Pieces

    private var kindPicker: some View {
        Picker("", selection: $kind) {
            Text(settings.t("uuid.kind.v4")).tag(IDKind.uuidV4)
            Text(settings.t("uuid.kind.v7")).tag(IDKind.uuidV7)
            Text(settings.t("uuid.kind.ulid")).tag(IDKind.ulid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
    }

    private var optionsBar: some View {
        HStack(spacing: 16) {
            Stepper(value: $count, in: 1...IDGenerator.maxCount) {
                Text(settings.t("uuid.countFmt", count))
                    .monospacedDigit()
            }
            .fixedSize()
            Toggle(settings.t("uuid.uppercase"), isOn: $uppercase)
                .toggleStyle(.checkbox)
            if kind != .ulid {
                Toggle(settings.t("uuid.hyphens"), isOn: $hyphens)
                    .toggleStyle(.checkbox)
            }
            Spacer()
            Button {
                copy(ids.joined(separator: "\n"))
            } label: {
                Label(settings.t("uuid.copyAll"), systemImage: "doc.on.doc")
            }
            .disabled(ids.isEmpty)
        }
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                    HStack(spacing: 8) {
                        Text(id)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            copy(id)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(settings.t("common.copy"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    if index < ids.count - 1 { Divider() }
                }
            }
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
            Image(systemName: "dice")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("uuid.empty.title")).font(.headline)
            Text(settings.t("uuid.empty.hint"))
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
                generate()
            } label: {
                Label(settings.t("uuid.run"), systemImage: "wand.and.stars")
                    .frame(minWidth: 120)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func generate() {
        ids = IDGenerator.generate(kind: kind, count: count, uppercase: uppercase, hyphens: hyphens)
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

#Preview {
    UUIDGeneratorView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 700)
}
