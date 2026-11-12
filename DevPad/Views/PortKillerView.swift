// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  PortKillerView.swift
//  DevPad
//
//  Lists every process that is listening on a TCP port and lets you stop it
//  with one click (SIGTERM; SIGKILL from the context menu). Scanning is done
//  through `PortKillerManager` (shared with the menu-bar popover), on first
//  show, whenever the tab becomes active again, and on demand (`⌘↵`). The
//  view never kills the DevPad process itself or PID ≤ 1. In demo mode it
//  shows made-up rows so screenshots don't leak the maintainer's real
//  processes.
//

import SwiftUI
import AppKit

struct PortKillerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.isToolActive) private var isToolActive

    @ObservedObject private var manager = PortKillerManager.shared
    @State private var filter: String = ""

    private var ports: [ListeningPort] { manager.ports }
    private var isScanning: Bool { manager.isScanning }
    private var hasScanned: Bool { manager.hasScanned }
    private var errorMessage: String? { manager.errorMessage }
    private var ownPID: Int32 { manager.ownPID }

    private var visiblePorts: [ListeningPort] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ports }
        return ports.filter {
            String($0.port).contains(q)
                || String($0.pid).contains(q)
                || $0.processName.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            filterBar
            if let errorMessage { errorBanner(errorMessage) }
            content
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { manager.refresh() }
        // Tabs stay mounted, so `onAppear` only fires once per session; the
        // listening ports change while the user is elsewhere.
        .onChange(of: isToolActive) { active in
            if active { manager.refresh() }
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(settings.t("ports.filter.placeholder"), text: $filter)
                .textFieldStyle(.plain)
            if !filter.isEmpty {
                Button {
                    filter = ""
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !hasScanned && errorMessage == nil {
            // First scan in flight.
            Color.clear.frame(maxHeight: .infinity)
        } else if ports.isEmpty {
            if errorMessage == nil { placeholder }
            else { Color.clear.frame(maxHeight: .infinity) }
        } else if visiblePorts.isEmpty {
            noMatchState
        } else {
            portList
        }
    }

    private var portList: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visiblePorts) { item in
                        row(item)
                        Divider()
                    }
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

    private var header: some View {
        HStack(spacing: 12) {
            columnTitle("ports.col.port").frame(width: 70, alignment: .leading)
            columnTitle("ports.col.process").frame(maxWidth: .infinity, alignment: .leading)
            columnTitle("ports.col.pid").frame(width: 70, alignment: .leading)
            columnTitle("ports.col.scope").frame(width: 170, alignment: .leading)
            // Placeholder over the Kill column. A bare `Color` is greedy in
            // BOTH directions, so without a fixed height it stretches the
            // whole header row to a third of the table.
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func columnTitle(_ key: String) -> some View {
        Text(settings.t(key))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func row(_ item: ListeningPort) -> some View {
        let isSelf = item.pid == ownPID
        return HStack(spacing: 12) {
            Text(verbatim: String(item.port))
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .textSelection(.enabled)
                .frame(width: 70, alignment: .leading)
            HStack(spacing: 6) {
                Text(item.processName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isSelf {
                    Text(settings.t("ports.thisApp"))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: String(item.pid))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(width: 70, alignment: .leading)
            scopeLabel(item)
                .frame(width: 170, alignment: .leading)
            Button(role: .destructive) {
                manager.terminate(item, force: false)
            } label: {
                Text(settings.t("ports.kill"))
                    .frame(minWidth: 40)
            }
            .buttonStyle(.bordered)
            .disabled(isSelf)
            .frame(width: 70)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contextMenu {
            Button(settings.t("ports.kill")) { manager.terminate(item, force: false) }
                .disabled(isSelf)
            Button(settings.t("ports.forceKill")) { manager.terminate(item, force: true) }
                .disabled(isSelf)
            Divider()
            Button(settings.t("ports.copyPort")) { copy(String(item.port)) }
            Button(settings.t("ports.copyPID")) { copy(String(item.pid)) }
        }
    }

    /// "All interfaces" is highlighted: a dev server reachable from the
    /// network is usually not what you meant to leave running.
    @ViewBuilder
    private func scopeLabel(_ item: ListeningPort) -> some View {
        if item.isExposed {
            Label(settings.t("ports.scope.all"), systemImage: "network")
                .font(.callout)
                .foregroundStyle(Color.orange)
        } else {
            Text(item.addresses.joined(separator: ", "))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("ports.empty.title")).font(.headline)
            Text(settings.t("ports.empty.hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(settings.t("ports.noMatchFmt", filter))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isScanning {
                ProgressView().controlSize(.small)
                Text(settings.t("ports.scanning"))
                    .foregroundStyle(.secondary)
            } else if hasScanned, errorMessage == nil {
                Text(settings.t("ports.countFmt", ports.count))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                manager.refresh()
            } label: {
                Label(settings.t("ports.refresh"), systemImage: "arrow.clockwise")
                    .frame(minWidth: 120)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(isScanning)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text("\(settings.t("ports.error.prefix")): \(message)")
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

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

#Preview {
    PortKillerView()
        .environmentObject(AppSettings.shared)
        .frame(width: 1000, height: 700)
}
