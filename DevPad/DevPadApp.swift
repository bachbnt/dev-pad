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
            ClipboardMenuBarView()
                .environmentObject(clipboard)
                .environmentObject(settings)
                .preferredColorScheme(settings.theme.colorScheme)
                .environment(\.locale, settings.language.locale)
                .task {
                    clipboard.start()
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
