// DevPad — Copyright © 2026 bachbnt. Proprietary.
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

    /// True while a drag started FROM the popup is in flight. We use
    /// this to suppress `handleMouseUp`'s "drop landed outside the
    /// popup → auto-dismiss" branch, because for popup-initiated
    /// drags the source's own `onSessionEnd` callback is authoritative
    /// and knows the difference between a real delivery and a
    /// cancelled drag (where the popup should STAY visible).
    private var isInternalDragInProgress: Bool = false

    /// True between detecting a real external file drag (in `handleDrag`)
    /// and the matching `mouseUp`. The flag is what lets `handleMouseUp`
    /// distinguish "a drag just ended outside the panel — dismiss" from
    /// "the user just clicked somewhere in Finder to change folders".
    /// Without it, every stray click outside the panel would hide it,
    /// and the user couldn't navigate Finder to a drop destination while
    /// the popup is visible.
    private var externalDragInFlight: Bool = false

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

    /// Screen-coordinate frame of the popup if it's currently visible,
    /// `nil` otherwise. Callers (notably the multi-file drag source)
    /// use this to tell whether a drop landed inside or outside the
    /// popup at session-end time.
    var visiblePanelFrame: NSRect? {
        guard let panel, panel.isVisible else { return nil }
        return panel.frame
    }

    /// Called by the popup's drag source when a drag-out session
    /// begins / ends. Lets `handleMouseUp` step aside while the
    /// drag-source callbacks handle the decision.
    func internalDragDidBegin() { isInternalDragInProgress = true }
    func internalDragDidEnd()   { isInternalDragInProgress = false }

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

        // A real file drag just started somewhere in the system. Arm the
        // flag so `handleMouseUp` knows the next mouseUp ends a drag (and
        // can decide whether to auto-dismiss based on where it lands).
        // Plain clicks elsewhere never hit this branch, so the flag stays
        // false for them and `handleMouseUp` leaves the panel alone.
        externalDragInFlight = true

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

        // Whatever this mouseUp is — drag-end or plain click — it closes
        // the current external-drag window. Snapshot the flag now and
        // reset it for the next cycle.
        let wasExternalDrag = externalDragInFlight
        externalDragInFlight = false

        // Popup-initiated drags route through `onSessionEnd` instead,
        // which can tell a real delivery apart from a mid-drag cancel.
        // Don't second-guess it from here.
        guard !isInternalDragInProgress else { return }

        // Plain click outside the panel — NOT the end of a drag. The
        // user is likely clicking around Finder to navigate to a drop
        // destination while keeping our popup as a holding pen. Leaving
        // the popup visible is the whole point; bail out before the
        // auto-dismiss check below.
        guard wasExternalDrag else { return }

        // A real external drag just ended. If the panel is visible and
        // the mouse came up OUTSIDE of it, the user dropped the files
        // somewhere else (Finder, another app, the desktop) —
        // auto-dismiss so the popup doesn't linger. Drops INSIDE the
        // panel keep it visible: the user may add more files in a
        // moment.
        guard let panel, panel.isVisible else { return }
        let cursor = NSEvent.mouseLocation
        if !panel.frame.contains(cursor) {
            panel.orderOut(nil)
        }
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
