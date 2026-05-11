//
//  ClipboardHistoryView.swift
//  DevPad
//
//  Full clipboard history view used inside the main window's tab.
//

import SwiftUI
import AppKit

struct ClipboardHistoryView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = ClipboardManager.shared
    @State private var selection: ClipboardItem.ID?
    @State private var confirmClearAll: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if manager.items.isEmpty {
                emptyState
            } else {
                content
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
            Text(itemCountText)
                .foregroundStyle(.secondary)
                .font(.callout)
            Spacer()
            Button(role: .destructive) {
                confirmClearAll = true
            } label: {
                Label(settings.t("common.clearAll"), systemImage: "trash")
            }
            .disabled(manager.items.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .confirmationDialog(
            settings.t("clipboard.confirm.title"),
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button(settings.t("clipboard.confirm.unpinned"), role: .destructive) {
                manager.clearAll()
            }
            Button(settings.t("clipboard.confirm.all"), role: .destructive) {
                manager.clearAllIncludingPinned()
            }
            Button(settings.t("common.cancel"), role: .cancel) {}
        }
    }

    private var itemCountText: String {
        manager.items.count == 1
            ? settings.t("clipboard.itemCount.one")
            : settings.t("clipboard.itemCount", manager.items.count)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(settings.t("clipboard.empty.title"))
                .foregroundStyle(.secondary)
            Text(settings.t("clipboard.empty.hint"))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Pinned items rendered as their own Section at the top, then a separate
    // unlabelled Section for the rest. The grouped list style draws the
    // section header + visual gap that acts as the divider.
    private var content: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                if !pinnedItems.isEmpty {
                    Section {
                        ForEach(pinnedItems) { item in
                            rowView(for: item)
                        }
                    } header: {
                        sectionHeader(
                            text: settings.t("clipboard.section.pinned"),
                            icon: "pin.fill",
                            iconColor: .orange
                        )
                    }
                }

                Section {
                    ForEach(unpinnedItems) { item in
                        rowView(for: item)
                    }
                } header: {
                    // Show "History" label only if there are pinned items above,
                    // so the section divider is visually motivated.
                    if !pinnedItems.isEmpty {
                        sectionHeader(
                            text: settings.t("clipboard.section.other"),
                            icon: "clock",
                            iconColor: .secondary
                        )
                    } else {
                        EmptyView()
                    }
                }
            }
            .listStyle(.inset)
            .frame(width: 340)

            Divider()

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pinnedItems: [ClipboardItem] { manager.items.filter { $0.pinned } }
    private var unpinnedItems: [ClipboardItem] { manager.items.filter { !$0.pinned } }

    private func sectionHeader(text: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(iconColor)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
    }

    private func rowView(for item: ClipboardItem) -> some View {
        HistoryRow(item: item)
            .tag(item.id)
            .contextMenu {
                Button {
                    manager.copyToPasteboard(item)
                } label: {
                    Label(settings.t("clipboard.copyAgain"), systemImage: "doc.on.doc")
                }
                Button {
                    manager.togglePin(item)
                } label: {
                    Label(
                        item.pinned
                            ? settings.t("clipboard.unpin")
                            : settings.t("clipboard.pin"),
                        systemImage: item.pinned ? "pin.slash" : "pin"
                    )
                }
                Divider()
                Button(role: .destructive) {
                    manager.remove(item)
                } label: {
                    Label(settings.t("clipboard.deleteThis"), systemImage: "trash")
                }
            }
    }

    private var detailPane: some View {
        Group {
            if let id = selection,
               let item = manager.items.first(where: { $0.id == id }) {
                ClipboardDetailView(item: item)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(settings.t("clipboard.selectItem"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Row

private struct HistoryRow: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = ClipboardManager.shared
    let item: ClipboardItem

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            iconColumn
            VStack(alignment: .leading, spacing: 2) {
                Text(preview(item, settings))
                    .font(.system(.callout))
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(formatDate(item.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            // .foregroundStyle is applied on the Button (not inside its label)
            // so the color reliably updates when `item.pinned` flips. On macOS
            // borderless buttons sometimes ignore the label's foreground change
            // until the view re-mounts.
            Button {
                manager.togglePin(item)
            } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(item.pinned ? Color.orange : Color.secondary)
            .help(item.pinned ? settings.t("clipboard.unpin") : settings.t("clipboard.pin"))

            Button(role: .destructive) {
                manager.remove(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(settings.t("clipboard.delete"))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var iconColumn: some View {
        switch item.kind {
        case .text:
            Image(systemName: "text.alignleft")
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.blue)
        case .image:
            if let img = item.nsImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
                    .frame(width: 32, height: 32)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.purple)
            }
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = settings.language.locale
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Detail

private struct ClipboardDetailView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = ClipboardManager.shared
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(item.kind == .text
                     ? settings.t("clipboard.kind.text")
                     : settings.t("clipboard.kind.image"))
                    .font(.headline)
                if item.pinned {
                    Label(settings.t("clipboard.pin"), systemImage: "pin.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(item.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            // The pane width is already bounded by the parent HStack, so we
            // can let the content fill via .frame(maxWidth: .infinity) and
            // rely on Text's natural wrapping. fixedSize(vertical: true)
            // makes the Text expand vertically while staying clamped
            // horizontally, which is exactly what we want inside ScrollView.
            ScrollView([.vertical]) {
                Group {
                    switch item.kind {
                    case .text:
                        Text(item.text ?? "")
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    case .image:
                        if let img = item.nsImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        } else {
                            Text(settings.t("clipboard.image.unavailable"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                Button {
                    manager.togglePin(item)
                } label: {
                    Label(
                        item.pinned ? settings.t("clipboard.unpin") : settings.t("clipboard.pin"),
                        systemImage: item.pinned ? "pin.slash" : "pin"
                    )
                }
                Spacer()
                Button(role: .destructive) {
                    manager.remove(item)
                } label: {
                    Label(settings.t("clipboard.delete"), systemImage: "trash")
                }
                Button {
                    manager.copyToPasteboard(item)
                } label: {
                    Label(settings.t("clipboard.copyAgain"), systemImage: "doc.on.doc")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }
}

// MARK: - Preview helper

/// Builds a localized one-line preview for a clipboard item.
/// `@MainActor` because it reads `settings.t(...)` which is main-actor isolated.
@MainActor
fileprivate func preview(_ item: ClipboardItem, _ settings: AppSettings) -> String {
    switch item.kind {
    case .text:
        let raw = item.text ?? ""
        let stripped = raw.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty {
            return settings.t("clipboard.preview.empty")
        }
        if stripped.count > 80 {
            return String(stripped.prefix(80)) + "…"
        }
        return stripped
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

#Preview {
    ClipboardHistoryView()
        .environmentObject(AppSettings.shared)
        .frame(width: 800, height: 500)
}
