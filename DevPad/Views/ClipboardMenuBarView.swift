//
//  ClipboardMenuBarView.swift
//  DevPad
//
//  Compact view shown when the user clicks the menu bar icon.
//  Lists recent clipboard items and lets them re-copy / pin / delete.
//

import SwiftUI
import AppKit

struct ClipboardMenuBarView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = ClipboardManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 360, height: 480)
    }

    private var header: some View {
        // Header carries content-level actions: title, count, and Clear.
        // Clear belongs here (not the footer) because it acts on the list.
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
            Text(settings.t("sidebar.clipboard"))
                .font(.headline)
            if !manager.items.isEmpty {
                Text("\(manager.items.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            Spacer()
            if !manager.items.isEmpty {
                Button(role: .destructive) {
                    manager.clearAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(settings.t("common.clearAll"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var pinnedItems: [ClipboardItem] { manager.items.filter { $0.pinned } }
    private var unpinnedItems: [ClipboardItem] { manager.items.filter { !$0.pinned } }

    @ViewBuilder
    private var list: some View {
        if manager.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(settings.t("menubar.empty"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !pinnedItems.isEmpty {
                        sectionLabel(
                            text: settings.t("clipboard.section.pinned"),
                            icon: "pin.fill",
                            iconColor: .orange
                        )
                        ForEach(pinnedItems) { item in
                            // Explicit `.id` with section prefix so an item
                            // moving between sections gets a brand-new view
                            // (instead of SwiftUI reusing the previous one
                            // with stale `displayPinned`).
                            MenuBarRow(item: item, displayPinned: true)
                                .id("pinned-\(item.id.uuidString)")
                            Divider().padding(.leading, 50)
                        }
                        sectionLabel(
                            text: settings.t("clipboard.section.other"),
                            icon: "clock",
                            iconColor: .secondary
                        )
                    }
                    ForEach(unpinnedItems) { item in
                        MenuBarRow(item: item, displayPinned: false)
                            .id("unpinned-\(item.id.uuidString)")
                        Divider().padding(.leading, 50)
                    }
                }
            }
        }
    }

    private func sectionLabel(text: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(iconColor)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        // Footer carries app-level actions: navigation (open window) and
        // lifecycle (settings, quit). Both buttons are text-labelled with
        // matching visual weight so the hierarchy reads cleanly.
        HStack(spacing: 8) {
            Button {
                // Restore dock presence before opening the window so the
                // app feels like a regular foreground app again.
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Image(systemName: "macwindow")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(settings.t("menubar.open"))

            Button {
                settings.pendingTool = "settings"
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Image(systemName: "gearshape")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(settings.t("settings.title"))

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                // "Quit" + power icon: text disambiguates from system shutdown,
                // which a bare power glyph would suggest.
                Image(systemName: "power")
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(settings.t("menubar.quit"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

}

private struct MenuBarRow: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = ClipboardManager.shared
    let item: ClipboardItem
    /// Visual state for the pin icon — supplied by the parent based on
    /// which section the row is rendered in. This bypasses a SwiftUI bug
    /// where `item.pinned` reads stale inside nested buttons after toggle.
    let displayPinned: Bool
    @State private var hovered = false

    var body: some View {
        // Outer Button = the row's primary action (copy back to pasteboard).
        // Nested pin/delete buttons must stay independently clickable, so
        // we use .buttonStyle(.plain) outside and .borderless inside —
        // SwiftUI then routes clicks on the inner buttons to those buttons.
        Button {
            manager.copyToPasteboard(item)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(localizedPreview)
                        .font(.callout)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(timeShort(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Single pin button — icon driven by the section the row is
                // rendered in (`displayPinned`), not by `item.pinned`. This
                // sidesteps the macOS SwiftUI bug where nested-button label
                // foreground stays stale after a toggle. The click action
                // still calls togglePin which mutates the real model.
                Button {
                    manager.togglePin(item)
                } label: {
                    Image(systemName: displayPinned ? "pin.fill" : "pin")
                        .foregroundStyle(displayPinned ? Color.orange : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(displayPinned ? settings.t("clipboard.unpin") : settings.t("clipboard.pin"))

                Button(role: .destructive) {
                    manager.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(settings.t("clipboard.delete"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(hovered ? Color.accentColor.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .frame(width: 28, height: 28)
                .background(Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.blue)
        case .image:
            if let img = item.nsImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .frame(width: 28, height: 28)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.purple)
            }
        }
    }

    private var localizedPreview: String {
        switch item.kind {
        case .text:
            let raw = item.text ?? ""
            let stripped = raw.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { return settings.t("clipboard.preview.empty") }
            return stripped.count > 80 ? String(stripped.prefix(80)) + "…" : stripped
        case .image:
            if let data = item.imageData,
               let img = NSImage(data: data) {
                let w = Int(img.size.width.rounded())
                let h = Int(img.size.height.rounded())
                let kb = max(1, data.count / 1024)
                return settings.t("clipboard.preview.image", w, h, kb)
            }
            return settings.t("clipboard.kind.image")
        }
    }

    private func timeShort(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = settings.language.locale
        return f.localizedString(for: d, relativeTo: Date())
    }
}

#Preview {
    ClipboardMenuBarView()
        .environmentObject(AppSettings.shared)
}
