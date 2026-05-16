// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  AppDelegate.swift
//  DevPad
//
//  Drives the "menu bar app + optional window" lifecycle:
//  - Closing the main window doesn't quit DevPad. Instead, the dock icon
//    disappears and the app keeps running with its menu bar icon.
//  - Reopening the main window (from the menu bar's "Open DevPad" button
//    or by clicking the dock icon when one is shown) brings the dock
//    icon back via the window's onAppear.
//  - Real quit only happens via the menu bar's Quit button or ⌘Q while
//    the window is focused.
//

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Identifier prefix that we treat as "the main window".
    private let mainWindowPrefix = "main"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start in regular (dock icon visible) so the launch experience
        // matches a normal app.
        NSApp.setActivationPolicy(.regular)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    /// Returning false stops the app from quitting when the last window
    /// closes. Without this, our menu bar icon would vanish along with
    /// the window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopen the main window when the user clicks the dock icon while
    /// the app has no visible windows. (Mostly relevant before we drop
    /// to `.accessory`, but kept for completeness.)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .devPadShouldOpenMainWindow, object: nil)
        }
        return true
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard isMainWindow(window) else { return }

        // Defer the policy switch one runloop tick so SwiftUI finishes
        // tearing down the window before we hide the dock tile.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.hasOpenMainWindow() {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: - Helpers

    private func isMainWindow(_ window: NSWindow) -> Bool {
        guard let id = window.identifier?.rawValue else { return false }
        return id.hasPrefix(mainWindowPrefix)
    }

    private func hasOpenMainWindow() -> Bool {
        NSApp.windows.contains { w in
            isMainWindow(w) && w.isVisible
        }
    }
}

extension Notification.Name {
    static let devPadShouldOpenMainWindow = Notification.Name("DevPadShouldOpenMainWindow")
}
