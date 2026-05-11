//
//  DevPadApp.swift
//  DevPad
//
//  Native macOS 13+ SwiftUI app with three scenes:
//  - Window  "main"      : the formatter / diff / clipboard tabs
//  - MenuBarExtra        : compact clipboard history in the menu bar
//  - Settings (⌘,)       : theme + language preferences
//
//  Lifecycle: closing the main window does NOT quit the app — DevPad
//  stays alive in the menu bar (see AppDelegate). The user quits via
//  the menu bar's Quit button.
//

import SwiftUI
import AppKit

@main
struct DevPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var clipboard = ClipboardManager.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        Window(settings.t("app.name"), id: "main") {
            MainWindowView()
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(clipboard)
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                .environment(\.locale, settings.language.locale)
                .task {
                    clipboard.start()
                    // Sync the Drop Shelf monitor with the persisted setting.
                    DropShelfMonitor.shared.setEnabled(settings.dropShelfEnabled)
                }
                // Belt-and-suspenders: even if `AppSettings.dropShelfEnabled`'s
                // didSet doesn't propagate the toggle (e.g. when the change
                // arrives via a SwiftUI Binding inside a child view), this
                // view-level observer guarantees the monitor always tracks
                // the latest value.
                .onChange(of: settings.dropShelfEnabled) { newValue in
                    DropShelfMonitor.shared.setEnabled(newValue)
                }
                .onAppear {
                    // Whenever the main window comes back, restore dock presence.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        .handlesExternalEvents(matching: ["main"])

        MenuBarExtra {
            MenuBarView()
                .environmentObject(clipboard)
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                .environment(\.locale, settings.language.locale)
                .task {
                    clipboard.start()
                    DropShelfMonitor.shared.setEnabled(settings.dropShelfEnabled)
                }
                .onChange(of: settings.dropShelfEnabled) { newValue in
                    DropShelfMonitor.shared.setEnabled(newValue)
                }
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                .environment(\.locale, settings.language.locale)
        }
    }
}
