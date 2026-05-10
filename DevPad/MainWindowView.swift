//
//  MainWindowView.swift
//  DevPad
//
//  Sidebar-style navigation for the main app window. Each section is a
//  full-screen tool. The clipboard tool also appears here in addition to
//  the menu-bar popover. The Settings tab is also reachable via ⌘,.
//

import SwiftUI

private enum Tool: String, CaseIterable, Identifiable, Hashable {
    case json
    case xml
    case diff
    case clipboard
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .json:      return "sidebar.json"
        case .xml:       return "sidebar.xml"
        case .diff:      return "sidebar.diff"
        case .clipboard: return "sidebar.clipboard"
        case .settings:  return "sidebar.settings"
        }
    }

    var icon: String {
        switch self {
        case .json:      return "curlybraces"
        case .xml:       return "chevron.left.forwardslash.chevron.right"
        case .diff:      return "arrow.left.arrow.right"
        case .clipboard: return "doc.on.clipboard"
        case .settings:  return "gearshape"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var selection: Tool = .json

    var body: some View {
        NavigationSplitView {
            List(Tool.allCases, id: \.self, selection: $selection) { tool in
                Label(settings.t(tool.titleKey), systemImage: tool.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .navigationTitle(settings.t("app.name"))
        } detail: {
            switch selection {
            case .json:
                JSONFormatterView()
                    .navigationTitle(settings.t("sidebar.json"))
            case .xml:
                XMLFormatterView()
                    .navigationTitle(settings.t("sidebar.xml"))
            case .diff:
                DiffCompareView()
                    .navigationTitle(settings.t("sidebar.diff"))
            case .clipboard:
                ClipboardHistoryView()
                    .navigationTitle(settings.t("sidebar.clipboard"))
            case .settings:
                SettingsView()
                    .navigationTitle(settings.t("sidebar.settings"))
            }
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppSettings.shared)
        .environmentObject(ClipboardManager.shared)
        .frame(width: 1100, height: 720)
}
