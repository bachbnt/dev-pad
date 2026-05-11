//
//  DropShelfPanelView.swift
//  DevPad
//
//  SwiftUI content for the floating Drop Shelf panel.
//
//  Layout:
//  ┌─────────────────────────┐
//  │ ⓧ   Drop Shelf      ⋯  │  header (close, title, menu)
//  ├─────────────────────────┤
//  │      [📄][📄][📄]        │  stack of file thumbnails (drag source)
//  │      "3 files"          │
//  └─────────────────────────┘
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropShelfPanelView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var manager: DropShelfManager
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .padding(6)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                DropShelfMonitor.shared.hidePanel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(settings.t("dropshelf.close"))

            Spacer()

            Text(settings.t("dropshelf.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Spacer()

            Menu {
                Button(role: .destructive) {
                    manager.clear()
                } label: {
                    Label(settings.t("dropshelf.clear"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if manager.urls.isEmpty {
            emptyState
        } else {
            populated
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 32))
                // AnyShapeStyle erases the heterogeneous branches
                // (Color vs HierarchicalShapeStyle) so the ternary
                // type-checks under `.foregroundStyle`.
                .foregroundStyle(
                    isDropTargeted
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(HierarchicalShapeStyle.tertiary)
                )
            Text(settings.t("dropshelf.empty"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(settings.t("dropshelf.hint"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
    }

    private var populated: some View {
        VStack(spacing: 10) {
            stack
            Text(settings.t("dropshelf.count", manager.urls.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    /// Up to three fanned-out thumbnails. Wrapped in `MultiFileDragSource`
    /// so the user grabs the whole bundle and drops all files in one go
    /// — Dropover-style.
    private var stack: some View {
        let visible = Array(manager.urls.suffix(3).enumerated())
        return MultiFileDragSource(urls: manager.urls) {
            ZStack {
                ForEach(visible, id: \.element) { (i, url) in
                    thumbnail(for: url)
                        .rotationEffect(.degrees(Double(i - visible.count + 1) * 4))
                        .offset(
                            x: CGFloat(i - visible.count + 1) * 8,
                            y: CGFloat(visible.count - 1 - i) * -4
                        )
                }
            }
            .frame(width: 100, height: 100)
        }
        .frame(width: 100, height: 100)
    }

    private func thumbnail(for url: URL) -> some View {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return VStack(spacing: 2) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
            Text(url.lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 90)
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

    // MARK: - Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    manager.add(url)
                }
            }
        }
        return accepted
    }
}

#Preview {
    DropShelfPanelView()
        .environmentObject(AppSettings.shared)
        .environmentObject(DropShelfManager.shared)
        .frame(width: 240, height: 300)
}
