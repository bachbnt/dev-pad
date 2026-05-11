//
//  DropShelfMonitor.swift
//  DevPad
//
//  Detects a system-wide file drag using NSEvent's global monitor +
//  the drag NSPasteboard, then shows a small floating panel (NSPanel
//  with `.nonactivatingPanel` style) so the user can drop the files
//  in, accumulate more, and later drag the whole bundle out to a new
//  destination — Dropover-style.
//
//  Limitations:
//  - Drags initiated INSIDE our own app don't fire global events;
//    that's fine — the shelf is meant for collecting files from
//    Finder, Mail, etc.
//  - No special permissions required. We never intercept or modify
//    drag events, only observe.
//

import AppKit
import SwiftUI

@MainActor
final class DropShelfMonitor {
    static let shared = DropShelfMonitor()

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var panel: NSPanel?

    /// Whether the feature is currently enabled (driven by AppSettings).
    private(set) var isEnabled: Bool = false

    private init() {}

    // MARK: - Public

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if on { startMonitoring() } else { stopMonitoring() }
    }

    /// Tear down the panel without disabling the feature — used when
    /// the user manually closes the shelf and we want to wait for the
    /// next drag before re-showing.
    func hidePanel() {
        panel?.orderOut(nil)
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        if dragMonitor == nil {
            dragMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDragged]
            ) { [weak self] _ in
                Task { @MainActor in self?.handleDrag() }
            }
        }
        if upMonitor == nil {
            upMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseUp]
            ) { [weak self] _ in
                Task { @MainActor in self?.handleMouseUp() }
            }
        }
    }

    private func stopMonitoring() {
        [dragMonitor, upMonitor].forEach { token in
            if let token { NSEvent.removeMonitor(token) }
        }
        dragMonitor = nil
        upMonitor = nil
        panel?.close()
        panel = nil
    }

    /// Called for every drag tick. If the drag pasteboard contains file
    /// URLs and our panel isn't visible yet, pop it up next to the cursor.
    private func handleDrag() {
        guard isEnabled else { return }
        guard pasteboardHasFileURLs() else { return }

        let panel = ensurePanel()
        if !panel.isVisible {
            positionPanelNearCursor(panel)
            panel.orderFrontRegardless()
        }
    }

    private func handleMouseUp() {
        // We don't auto-close the panel on mouse up — the user might
        // have dropped files into the shelf and want to keep collecting.
        // Closing is controlled by the X button or settings toggle.
    }

    private func pasteboardHasFileURLs() -> Bool {
        let pb = NSPasteboard(name: .drag)
        guard let types = pb.types,
              types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("public.file-url")) else {
            return false
        }
        return true
    }

    // MARK: - Panel

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let new = makePanel()
        panel = new
        return new
    }

    private func makePanel() -> NSPanel {
        let view = DropShelfPanelView()
            .environmentObject(DropShelfManager.shared)
            .environmentObject(AppSettings.shared)

        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hosting

        return panel
    }

    private func positionPanelNearCursor(_ panel: NSPanel) {
        let cursor = NSEvent.mouseLocation
        let size = panel.frame.size
        // Place slightly to the right and below the cursor (NSPoint origin
        // is bottom-left so "below" the cursor visually = smaller y).
        var origin = NSPoint(x: cursor.x + 24, y: cursor.y - size.height - 24)

        // Keep the panel inside the screen the cursor is on.
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(visible.minX, origin.x), visible.maxX - size.width)
            origin.y = min(max(visible.minY, origin.y), visible.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }
}
