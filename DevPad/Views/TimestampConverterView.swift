// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  TimestampConverterView.swift
//  DevPad
//
//  Unix timestamp ↔ date converter. One input accepts either an epoch number
//  (unit auto-detected, or pinned from the picker) or a date string; the
//  result is a list of equivalent representations, each with a copy button.
//  Rows are derived from the stored result at render time so the readable /
//  relative rows follow the app language, and "Now" fills in the current
//  epoch and converts it in one step.
//

import SwiftUI
import AppKit

private enum ZoneChoice: String, CaseIterable, Identifiable {
    case local, utc
    var id: String { rawValue }

    var timeZone: TimeZone {
        switch self {
        case .local: return .current
        case .utc:   return TimeZone(identifier: "UTC") ?? .current
        }
    }
}

struct TimestampConverterView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var input: String = ""
    /// `nil` means auto-detect.
    @State private var unit: TimestampUnit?
    @State private var zone: ZoneChoice = .local
    @State private var result: TimestampResult?
    @State private var convertedAt = Date()
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            inputBar
            optionsBar
            if let errorMessage { errorBanner(errorMessage) }
            if let result { resultsView(result) } else if errorMessage == nil { placeholder }
            actionBar
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if DemoMode.isOn, input.isEmpty {
                input = DemoMode.sampleTimestamp
                run()
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(settings.t("timestamp.input.placeholder"), text: $input)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .onSubmit { run() }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25))
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                )
            Button {
                useNow()
            } label: {
                Label(settings.t("timestamp.now"), systemImage: "clock")
            }
        }
    }

    private var optionsBar: some View {
        HStack(spacing: 12) {
            Text(settings.t("timestamp.unit"))
                .foregroundStyle(.secondary)
            Picker("", selection: $unit) {
                Text(settings.t("timestamp.unit.auto")).tag(TimestampUnit?.none)
                ForEach(TimestampUnit.allCases) { u in
                    Text(unitSymbol(u)).tag(TimestampUnit?.some(u))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            Text(settings.t("timestamp.zone"))
                .foregroundStyle(.secondary)
            Picker("", selection: $zone) {
                Text(settings.t("timestamp.zone.local")).tag(ZoneChoice.local)
                Text(settings.t("timestamp.zone.utc")).tag(ZoneChoice.utc)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            Spacer()
        }
    }

    // MARK: - Results

    private struct Row: Identifiable {
        let labelKey: String
        let value: String
        var id: String { labelKey }
    }

    private func rows(for r: TimestampResult) -> [Row] {
        let locale = Locale(identifier: settings.language.resolvedCode)
        let local = TimeZone.current
        let utc = ZoneChoice.utc.timeZone
        return [
            Row(labelKey: "timestamp.row.seconds",
                value: String(TimestampEngine.epochSeconds(r.date))),
            Row(labelKey: "timestamp.row.millis",
                value: String(TimestampEngine.epochMilliseconds(r.date))),
            Row(labelKey: "timestamp.row.isoUTC",
                value: TimestampEngine.iso8601(r.date, timeZone: utc)),
            Row(labelKey: "timestamp.row.isoLocal",
                value: TimestampEngine.iso8601(r.date, timeZone: local)),
            Row(labelKey: "timestamp.row.readable",
                value: TimestampEngine.readable(r.date, timeZone: local, locale: locale)),
            Row(labelKey: "timestamp.row.relative",
                value: TimestampEngine.relative(r.date, to: convertedAt, locale: locale))
        ]
    }

    private func resultsView(_ r: TimestampResult) -> some View {
        let list = rows(for: r)
        return VStack(alignment: .leading, spacing: 6) {
            if unit == nil, let detected = r.unit {
                Label(settings.t("timestamp.detectedFmt", unitSymbol(detected)),
                      systemImage: "wand.and.stars")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            Text(settings.t(row.labelKey))
                                .foregroundStyle(.secondary)
                                .frame(width: 170, alignment: .leading)
                            Text(row.value)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                copy(row.value)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help(settings.t("common.copy"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        if index < list.count - 1 { Divider() }
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
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("timestamp.empty.title")).font(.headline)
            Text(settings.t("timestamp.empty.hint"))
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
                Label(settings.t("timestamp.run"), systemImage: "arrow.triangle.2.circlepath")
                    .frame(minWidth: 120)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text("\(settings.t("timestamp.error.prefix")): \(message)")
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

    private func unitSymbol(_ u: TimestampUnit) -> String {
        switch u {
        case .seconds:      return "s"
        case .milliseconds: return "ms"
        case .microseconds: return "µs"
        case .nanoseconds:  return "ns"
        }
    }

    private func run() {
        do {
            result = try TimestampEngine.parse(input, unit: unit, zoneLessTimeZone: zone.timeZone)
            convertedAt = Date()
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func useNow() {
        input = String(Int64(Date().timeIntervalSince1970))
        // A pinned unit would misread a seconds value.
        unit = nil
        run()
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

#Preview {
    TimestampConverterView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 700)
}
