// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  MainWindowView.swift
//  DevPad
//
//  Sidebar-style navigation for the main app window. Each section is a
//  full-screen tool. The clipboard tool also appears here in addition to
//  the menu-bar popover. The Settings tab is also reachable via ⌘,.
//

import SwiftUI

/// False for a tool tab that is alive but not the one on screen. Tools stay
/// mounted after their first visit so typed input survives tab switches, which
/// also means `onDisappear` no longer fires on a switch — views that hold
/// hardware (the QR camera) watch this instead.
private struct ToolActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isToolActive: Bool {
        get { self[ToolActiveKey.self] }
        set { self[ToolActiveKey.self] = newValue }
    }
}

private enum Tool: String, CaseIterable, Identifiable, Hashable {
    case json
    case xml
    case sql
    case url
    case qr
    case jwt
    case regex
    case hash
    case diff
    case clipboard
    case dropshelf
    case settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .json:      return "sidebar.json"
        case .xml:       return "sidebar.xml"
        case .sql:       return "sidebar.sql"
        case .url:       return "sidebar.url"
        case .qr:        return "sidebar.qr"
        case .jwt:       return "sidebar.jwt"
        case .regex:     return "sidebar.regex"
        case .hash:      return "sidebar.hash"
        case .diff:      return "sidebar.diff"
        case .clipboard: return "sidebar.clipboard"
        case .dropshelf: return "sidebar.dropshelf"
        case .settings:  return "sidebar.settings"
        }
    }

    var icon: String {
        switch self {
        case .json:      return "curlybraces"
        case .xml:       return "chevron.left.forwardslash.chevron.right"
        case .sql:       return "tablecells"
        case .url:       return "link"
        case .qr:        return "qrcode"
        case .jwt:       return "key"
        case .regex:     return "asterisk"
        case .hash:      return "number"
        case .diff:      return "arrow.left.arrow.right"
        case .clipboard: return "doc.on.clipboard"
        case .dropshelf: return "tray.and.arrow.down"
        case .settings:  return "gearshape"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var selection: Tool = .json
    /// Tools opened at least once. Only these are instantiated; see `detailStack`.
    @State private var visited: Set<Tool> = [.json]
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool

    /// Tools whose localized title contains `searchQuery`
    /// (case-insensitive, whitespace-trimmed). Returns every tool when the
    /// query is empty so the sidebar shows its full list by default.
    private var filteredTools: [Tool] {
        let q = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !q.isEmpty else { return Tool.allCases }
        return Tool.allCases.filter {
            settings.t($0.titleKey).lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                searchField
                if filteredTools.isEmpty {
                    searchEmptyState
                } else {
                    List(filteredTools, id: \.self, selection: $selection) { tool in
                        Label(settings.t(tool.titleKey), systemImage: tool.icon)
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .navigationTitle(settings.t("app.name"))
        } detail: {
            detailStack
                .navigationTitle(settings.t(selection.titleKey))
        }
        .onChange(of: selection) { newTool in
            visited.insert(newTool)
        }
        .onChange(of: settings.pendingTool) { pending in
            if let raw = pending, let tool = Tool(rawValue: raw) {
                selection = tool
                // Clear the search so the navigated-to tool is actually
                // visible in the sidebar after the jump.
                searchQuery = ""
                settings.pendingTool = nil
            }
        }
    }

    // MARK: - Detail

    /// Visited tools stay mounted and are only hidden, so switching tabs
    /// doesn't throw away what the user typed (a half-pasted JSON, a diff
    /// in progress). Hidden tabs are also disabled: without that their
    /// `⌘↵` shortcuts would still compete with the visible tool's.
    private var detailStack: some View {
        ZStack {
            ForEach(Tool.allCases) { tool in
                if visited.contains(tool) {
                    let isActive = tool == selection
                    toolView(tool)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                        .disabled(!isActive)
                        .accessibilityHidden(!isActive)
                        .environment(\.isToolActive, isActive)
                }
            }
        }
    }

    @ViewBuilder
    private func toolView(_ tool: Tool) -> some View {
        switch tool {
        case .json:      JSONFormatterView()
        case .xml:       XMLFormatterView()
        case .sql:       SQLFormatterView()
        case .url:       URLParserView()
        case .qr:        QRGeneratorView()
        case .jwt:       JWTInspectorView()
        case .regex:     RegexTesterView()
        case .hash:      HashGeneratorView()
        case .diff:      DiffCompareView()
        case .clipboard: ClipboardHistoryView()
        case .dropshelf: DropShelfView()
        case .settings:  SettingsView()
        }
    }

    // MARK: - Sidebar search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField(settings.t("sidebar.search.placeholder"), text: $searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(settings.t("sidebar.search.clear"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(settings.t("sidebar.search.empty", searchQuery))
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(AppSettings.shared)
        .environmentObject(ClipboardManager.shared)
        .frame(width: 1100, height: 720)
}
