//
//  DropShelfView.swift
//  DevPad
//
//  Main-window sidebar tab for the Drop Shelf. Layout mirrors the
//  Clipboard History tab almost 1-to-1: a thin header row of metadata
//  + actions, then the content area below. The on/off toggle lives in
//  the header, replacing the old setting in Settings.
//

import SwiftUI
import AppKit

struct DropShelfView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = DropShelfManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(.secondary)

            if settings.dropShelfEnabled, !manager.urls.isEmpty {
                Text(settings.t("dropshelf.count", manager.urls.count))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            // Toggle uses a visible label so users can find the on/off
            // affordance at a glance. (Earlier attempts hid the label
            // with `.labelsHidden()` which made the switch effectively
            // invisible in an otherwise empty row.)
            Toggle(settings.t("dropshelf.toggle"), isOn: $settings.dropShelfEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            Button(role: .destructive) {
                manager.clear()
            } label: {
                Label(settings.t("common.clearAll"), systemImage: "trash")
            }
            .disabled(!settings.dropShelfEnabled || manager.urls.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !settings.dropShelfEnabled {
            disabledState
        } else if manager.urls.isEmpty {
            emptyState
        } else {
            populated
        }
    }

    private var disabledState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("dropshelf.disabled.title"))
                .font(.headline)
            Text(settings.t("dropshelf.disabled.hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(settings.t("dropshelf.toggleHint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(settings.t("dropshelf.list.empty"))
                .font(.headline)
            Text(settings.t("dropshelf.list.empty.hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var populated: some View {
        VStack(spacing: 12) {
            stackHandle
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(manager.urls, id: \.self) { url in
                        FileRow(url: url)
                        Divider().padding(.leading, 50)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    /// Stack thumbnail used as a drag source for ALL files in the shelf.
    private var stackHandle: some View {
        // Snapshot at render time — see DropShelfPanelView.stack for the
        // same pattern. Drag-out semantics across every shelf surface
        // (popup, in-app, menubar) is "move": when the destination
        // accepts the drop, the files belong to it now, so drop them
        // from the shared shelf state too.
        let draggedURLs = manager.urls
        return MultiFileDragSource(
            urls: manager.urls,
            onSessionEnd: { _, operation in
                guard operation != [] else { return }
                Task { @MainActor in
                    for url in draggedURLs { DropShelfManager.shared.remove(url) }
                }
            }
        ) {
            ZStack {
                let visible = Array(manager.urls.suffix(3).enumerated())
                ForEach(visible, id: \.element) { (i, url) in
                    fileTile(for: url)
                        .rotationEffect(.degrees(Double(i - visible.count + 1) * 4))
                        .offset(
                            x: CGFloat(i - visible.count + 1) * 8,
                            y: CGFloat(visible.count - 1 - i) * -4
                        )
                }
            }
            .frame(width: 120, height: 120)
        }
        .frame(width: 120, height: 120)
        .frame(maxWidth: .infinity)
    }

    private func fileTile(for url: URL) -> some View {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return VStack(spacing: 2) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
            Text(url.lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 100)
                .foregroundStyle(.primary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }
}

// MARK: - File row

private struct FileRow: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = DropShelfManager.shared
    let url: URL

    var body: some View {
        HStack(spacing: 10) {
            MultiFileDragSource(
                urls: [url],
                onSessionEnd: { [url] _, operation in
                    // Per-row drag: dropping this single file outside
                    // means it's been delivered → drop it from the
                    // shared shelf state.
                    guard operation != [] else { return }
                    Task { @MainActor in
                        DropShelfManager.shared.remove(url)
                    }
                }
            ) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                manager.remove(url)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(settings.t("dropshelf.remove"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    DropShelfView()
        .environmentObject(AppSettings.shared)
        .frame(width: 600, height: 500)
}
