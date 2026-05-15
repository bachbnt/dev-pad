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

    /// Delay between detecting a file drag and showing the shelf. Stops
    /// the panel from flashing on a quick accidental drag, and lets the
    /// user move the cursor toward the destination first without the
    /// shelf jumping in the way.
    private let showDelay: TimeInterval = 1.0

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var localUpMonitor: Any?
    private var panel: NSPanel?
    private var pendingShowTask: Task<Void, Never>?

    /// Last `NSPasteboard(.drag).changeCount` we treated as "seen".
    /// A real drag-and-drop session increments this exactly once when it
    /// starts; ordinary mouse drags over empty space don't touch it.
    /// We only consider showing the panel when the count moves forward,
    /// which lets us ignore stale drag-pasteboard contents from earlier
    /// sessions.
    private var lastDragChangeCount: Int = 0

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
        // Baseline the drag-pasteboard counter so any session already in
        // progress (or stale data from a previous drag) doesn't fire the
        // popup immediately.
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount

        if dragMonitor == nil {
            dragMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDragged]
            ) { [weak self] _ in
                Task { @MainActor in self?.handleDrag() }
            }
        }
        if upMonitor == nil {
            // Global monitor sees mouseUp in OTHER apps (Finder, etc.).
            upMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseUp]
            ) { [weak self] _ in
                Task { @MainActor in self?.handleMouseUp() }
            }
        }
        if localUpMonitor == nil {
            // Local monitor catches mouseUp inside our own windows
            // (e.g. when the drag ends in our shelf panel).
            localUpMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseUp]
            ) { [weak self] event in
                Task { @MainActor in self?.handleMouseUp() }
                return event
            }
        }
    }

    private func stopMonitoring() {
        [dragMonitor, upMonitor, localUpMonitor].forEach { token in
            if let token { NSEvent.removeMonitor(token) }
        }
        dragMonitor = nil
        upMonitor = nil
        localUpMonitor = nil
        pendingShowTask?.cancel()
        pendingShowTask = nil
        panel?.close()
        panel = nil
    }

    /// Called for every drag tick. Only a real drag-and-drop session (one
    /// that bumped the drag pasteboard's `changeCount`) AND that carries
    /// file URLs arms the show timer. Plain rubber-band selections or
    /// window-moving drags hit this method too — they don't change the
    /// pasteboard, so they're ignored.
    private func handleDrag() {
        guard isEnabled else { return }

        let pb = NSPasteboard(name: .drag)
        let count = pb.changeCount
        guard count != lastDragChangeCount else { return }
        // Only treat this as a "new drag session" if it actually carries
        // file URLs — non-file drags (text from a browser, colors, etc.)
        // are ignored. Still record the count so we don't re-evaluate
        // the same session over and over.
        lastDragChangeCount = count
        guard pasteboardContainsFileURLs(pb) else { return }

        // Already shown — nothing to schedule.
        if let panel, panel.isVisible { return }
        // Already pending — first scheduler wins.
        if pendingShowTask != nil { return }

        pendingShowTask = Task { @MainActor [showDelay] in
            try? await Task.sleep(nanoseconds: UInt64(showDelay * 500_000_000))
            defer { self.pendingShowTask = nil }
            guard !Task.isCancelled else { return }
            guard self.isEnabled else { return }
            // The drag may have ended during the delay; verify the same
            // session is still active.
            let nowPb = NSPasteboard(name: .drag)
            guard nowPb.changeCount == self.lastDragChangeCount,
                  self.pasteboardContainsFileURLs(nowPb) else { return }

            let p = self.ensurePanel()
            if !p.isVisible {
                self.positionPanelNearCursor(p)
                p.orderFrontRegardless()
            }
        }
    }

    private func handleMouseUp() {
        // If the user lets go before the show-delay expires, cancel the
        // pending panel so we don't flash it after the drag has ended.
        pendingShowTask?.cancel()
        pendingShowTask = nil
        // The panel itself stays visible if it's already up — the user
        // closes it via the X button. (They might have dropped files into
        // it and want to keep collecting.)
    }

    private func pasteboardContainsFileURLs(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        // Check both the modern UTType and the legacy NSPasteboardType
        // identifiers — different sources advertise different ones.
        return types.contains(.fileURL)
            || types.contains(NSPasteboard.PasteboardType("public.file-url"))
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
        // Let the user drag the panel by its header/background. The
        // file-stack view explicitly opts OUT of this via
        // `mouseDownCanMoveWindow = false` so it can start its own
        // AppKit drag session for the files instead.
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
