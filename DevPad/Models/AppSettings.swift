//
//  AppSettings.swift
//  DevPad
//
//  Holds user preferences (theme + language) and persists them in
//  UserDefaults. Acts as the source of truth observed by every view that
//  needs to localize text or react to theme changes.
//

import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// SwiftUI uses `nil` to mean "follow the system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var labelKey: String {
        switch self {
        case .system: return "settings.theme.system"
        case .light:  return "settings.theme.light"
        case .dark:   return "settings.theme.dark"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, vi

    var id: String { rawValue }

    /// Locale used by SwiftUI's date / number formatters.
    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .en:     return Locale(identifier: "en")
        case .vi:     return Locale(identifier: "vi")
        }
    }

    var labelKey: String {
        switch self {
        case .system: return "settings.language.system"
        case .en:     return "settings.language.english"
        case .vi:     return "settings.language.vietnamese"
        }
    }

    /// Returns the language code actually used for string lookup.
    /// `.system` falls back to "vi" if the OS language starts with "vi", else "en".
    var resolvedCode: String {
        switch self {
        case .system:
            let lang = Locale.preferredLanguages.first ?? "en"
            return lang.hasPrefix("vi") ? "vi" : "en"
        case .en: return "en"
        case .vi: return "vi"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let themeKey = "DevPad.settings.theme"
    private static let languageKey = "DevPad.settings.language"
    private static let dropShelfKey = "DevPad.settings.dropShelfEnabled"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
        }
    }

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
        }
    }

    /// When true, a small floating shelf pops up whenever a file drag is
    /// detected anywhere in the system (see `DropShelfMonitor`).
    @Published var dropShelfEnabled: Bool {
        didSet {
            UserDefaults.standard.set(dropShelfEnabled, forKey: Self.dropShelfKey)
            DropShelfMonitor.shared.setEnabled(dropShelfEnabled)
        }
    }

    /// Set to a Tool rawValue to request navigation in the main window.
    /// MainWindowView consumes and clears this on change.
    @Published var pendingTool: String? = nil

    private init() {
        let storedTheme = UserDefaults.standard.string(forKey: Self.themeKey) ?? ""
        self.theme = AppTheme(rawValue: storedTheme) ?? .system
        let storedLang = UserDefaults.standard.string(forKey: Self.languageKey) ?? ""
        self.language = AppLanguage(rawValue: storedLang) ?? .system
        // UserDefaults.bool returns `false` when the key is absent — which
        // is the default we want for the Drop Shelf (off until user opts in).
        self.dropShelfEnabled = UserDefaults.standard.bool(forKey: Self.dropShelfKey)
    }

    // MARK: - Localization

    /// Looks up `key` in the dictionary for the current language.
    /// Falls back to English, then to the key itself.
    func t(_ key: String) -> String {
        Localization.string(for: key, language: language)
    }

    /// Same as `t`, but interpolates `%@` / `%d` arguments.
    func t(_ key: String, _ args: CVarArg...) -> String {
        let template = Localization.string(for: key, language: language)
        return String(format: template, arguments: args)
    }
}
