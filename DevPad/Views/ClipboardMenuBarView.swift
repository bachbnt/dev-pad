//
//  ClipboardMenuBarView.swift  →  MenuBarView
//  DevPad
//
//  Menu-bar popover hosted by `MenuBarExtra`. Lets the user switch
//  between two tabs — Clipboard history and Drop Shelf — and exposes
//  a shared footer (Open DevPad, Settings, Quit).
//
//  All three tabs (popup, main-window sidebar, this menubar tab)
//  share the same underlying state via `DropShelfManager.shared` and
//  `ClipboardManager.shared`, so changes propagate everywhere.
//

import SwiftUI
import AppKit

private enum MenuBarTab: String, CaseIterable, Identifiable {
    case clipboard
    case dropshelf

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .clipboard: return "menubar.tab.clipboard"
        case .dropshelf: return "menubar.tab.dropshelf"
        }
    }

    var icon: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .dropshelf: return "tray.and.arrow.down"
        }
    }
}

// MARK: - Root

struct MenuBarView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @ObservedObject private var shelfManager = DropShelfManager.shared
    @Environment(\.openWindow) private var openWindow

    @State private var tab: MenuBarTab = .clipboard

    var body: some View {
        VStack(spacing: 0) {
            tabPicker
            Divider()
            switch tab {
            case .clipboard:
                ClipboardSection()
            case .dropshelf:
                DropShelfSection()
            }
            Divider()
            footer
        }
        .frame(width: 360, height: 520)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            ForEach(MenuBarTab.allCases) { t in
                Label(settings.t(t.labelKey), systemImage: t.icon).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Footer (shared)

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
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

// MARK: - Clipboard tab content

private struct ClipboardSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = ClipboardManager.shared

    private var pinnedItems: [ClipboardItem] { manager.items.filter { $0.pinned } }
    private var unpinnedItems: [ClipboardItem] { manager.items.filter { !$0.pinned } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
    }

    private var header: some View {
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
}

// MARK: - Drop Shelf tab content

private struct DropShelfSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = DropShelfManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(.secondary)
            Text(settings.t("dropshelf.title"))
                .font(.headline)
            if settings.dropShelfEnabled, !manager.urls.isEmpty {
                Text("\(manager.urls.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            Spacer()
            Toggle("", isOn: $settings.dropShelfEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            if settings.dropShelfEnabled, !manager.urls.isEmpty {
                Button(role: .destructive) {
                    manager.clear()
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

    @ViewBuilder
    private var content: some View {
        if !settings.dropShelfEnabled {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(settings.t("dropshelf.disabled.title"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text(settings.t("dropshelf.disabled.hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if manager.urls.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(settings.t("dropshelf.list.empty"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text(settings.t("dropshelf.list.empty.hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                stackHandle
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.urls, id: \.self) { url in
                            ShelfRow(url: url)
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
    }

    /// Fanned stack of file thumbnails (the "drag out all" handle), same
    /// shape as the one in the main-window Drop Shelf tab and the floating
    /// popup. The user grabs this to drag every file in the shelf at once.
    private var stackHandle: some View {
        MultiFileDragSource(urls: manager.urls) {
            VStack(spacing: 6) {
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
                .frame(width: 100, height: 100)

                Text(settings.t("dropshelf.count", manager.urls.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func fileTile(for url: URL) -> some View {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return VStack(spacing: 2) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
            Text(url.lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 80)
                .foregroundStyle(.primary)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }
}

private struct ShelfRow: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = DropShelfManager.shared
    let url: URL

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MultiFileDragSource(urls: [url]) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Button(role: .destructive) {
                manager.remove(url)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(settings.t("dropshelf.remove"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Clipboard menu-bar row (unchanged)

private struct MenuBarRow: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = ClipboardManager.shared
    let item: ClipboardItem
    let displayPinned: Bool
    @State private var hovered = false

    var body: some View {
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

// MARK: - Back-compat shim
//
// `ClipboardMenuBarView` was the old public type used by DevPadApp's
// `MenuBarExtra`. Kept as a thin wrapper so existing call sites keep
// compiling; new code should use `MenuBarView` directly.
typealias ClipboardMenuBarView = MenuBarView

#Preview {
    MenuBarView()
        .environmentObject(AppSettings.shared)
}
