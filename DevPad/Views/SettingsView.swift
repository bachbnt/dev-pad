//
//  SettingsView.swift
//  DevPad
//
//  Theme + language preferences. Available both as a tab in the main
//  window's sidebar and via the macOS Settings menu (⌘,).
//
//  Layout uses LabeledContent (the modern macOS-native pattern):
//  each row has a title + description on the left and the control on the
//  right, with no redundant section headers.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Picker(settings.t("settings.theme"), selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(settings.t(theme.labelKey)).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                } label: {
                    Text(settings.t("settings.theme"))
                        .font(.body)
                    Text(settings.t("settings.theme.footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent {
                    Picker(settings.t("settings.language"), selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(settings.t(lang.labelKey)).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 160)
                } label: {
                    Text(settings.t("settings.language"))
                        .font(.body)
                    Text(settings.t("settings.language.footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(minWidth: 480, minHeight: 240)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
        .frame(width: 560, height: 320)
}
