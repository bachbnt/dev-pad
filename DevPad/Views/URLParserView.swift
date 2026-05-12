//
//  URLParserView.swift
//  DevPad
//
//  Paste a URL → press Parse → see every component (scheme, user,
//  password, host, port, path, query string, query parameters, fragment)
//  on its own labelled row. Each value is selectable and one click
//  copies it to the pasteboard.
//

import SwiftUI
import AppKit

private struct ParsedURL {
    let scheme: String?
    let user: String?
    let password: String?
    let host: String?
    let port: Int?
    let path: String
    let query: String?
    let queryItems: [URLQueryItem]
    let fragment: String?
}

struct URLParserView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var input: String = ""
    @State private var parsed: ParsedURL?
    @State private var errorDetails: String?

    var body: some View {
        VStack(spacing: 12) {
            inputEditor
            actionBar
            if let errorDetails {
                errorBanner(errorDetails)
            }
            if let parsed {
                results(parsed)
            } else if errorDetails == nil {
                placeholder
            }
        }
        .padding(16)
    }

    // MARK: - Input

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
                Text(settings.t("url.placeholder"))
                    .foregroundStyle(.tertiary)
                    .font(.system(.body, design: .monospaced))
                    .padding(.leading, 13)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 80, maxHeight: 120)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
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
            Spacer()
            Button {
                parse()
            } label: {
                Label(settings.t("url.parse"), systemImage: "link")
                    .frame(minWidth: 100)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("\(settings.t("url.error.prefix")): \(message)")
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

    // MARK: - Empty state

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("url.empty.title"))
                .font(.headline)
            Text(settings.t("url.empty.hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private func results(_ p: ParsedURL) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                row(label: settings.t("url.scheme"), value: p.scheme)
                row(label: settings.t("url.user"), value: p.user)
                row(label: settings.t("url.password"), value: p.password.map { String(repeating: "•", count: $0.count) })
                row(label: settings.t("url.host"), value: p.host)
                row(label: settings.t("url.port"), value: p.port.map { String($0) })
                row(label: settings.t("url.path"), value: p.path.isEmpty ? nil : p.path)
                row(label: settings.t("url.query"), value: p.query)
                row(label: settings.t("url.fragment"), value: p.fragment)

                Divider().padding(.vertical, 8)

                queryParamsSection(p.queryItems)
            }
            .padding(.vertical, 6)
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
        .frame(maxHeight: .infinity)
    }

    private func row(label: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    copyToPasteboard(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(settings.t("common.copy"))
            } else {
                Text(settings.t("url.absent"))
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func queryParamsSection(_ items: [URLQueryItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(settings.t("url.queryParams"))
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.bottom, 2)

            if items.isEmpty {
                Text(settings.t("url.queryParams.empty"))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.name)
                            .font(.system(.callout, design: .monospaced).weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .trailing)

                        Text(item.value ?? "")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            copyToPasteboard(item.value ?? "")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help(settings.t("common.copy"))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func parse() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsed = nil
            errorDetails = settings.t("url.error.empty")
            return
        }
        guard let components = URLComponents(string: trimmed) else {
            parsed = nil
            errorDetails = settings.t("url.error.invalid")
            return
        }
        parsed = ParsedURL(
            scheme: components.scheme,
            user: components.user,
            password: components.password,
            host: components.host,
            port: components.port,
            path: components.path,
            query: components.query,
            queryItems: components.queryItems ?? [],
            fragment: components.fragment
        )
        errorDetails = nil
    }

    private func paste() {
        if let s = NSPasteboard.general.string(forType: .string) {
            input = s
            errorDetails = nil
        }
    }

    private func clear() {
        input = ""
        parsed = nil
        errorDetails = nil
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

#Preview {
    URLParserView()
        .environmentObject(AppSettings.shared)
        .frame(width: 900, height: 600)
}
