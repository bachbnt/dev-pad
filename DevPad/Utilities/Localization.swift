//
//  Localization.swift
//  DevPad
//
//  In-memory string catalog for English and Vietnamese.
//  Keeping the strings in code (rather than .strings / .xcstrings files)
//  lets us switch language at runtime without restarting the app.
//

import Foundation

enum Localization {

    /// Returns the localized string for `key` in the given language.
    /// Falls back to English, then to the raw key when no entry is found.
    static func string(for key: String, language: AppLanguage) -> String {
        let code = language.resolvedCode
        if let table = catalog[code], let value = table[key] {
            return value
        }
        if let value = catalog["en"]?[key] {
            return value
        }
        return key
    }

    // MARK: - Catalog

    private static let catalog: [String: [String: String]] = [
        "en": en,
        "vi": vi
    ]

    // MARK: English

    private static let en: [String: String] = [
        // App / sidebar
        "app.name":                          "DevPad",
        "sidebar.json":                      "JSON Formatter",
        "sidebar.xml":                       "XML Formatter",
        "sidebar.diff":                      "Diff Compare",
        "sidebar.clipboard":                 "Clipboard History",
        "sidebar.settings":                  "Settings",

        // Common buttons / labels
        "common.paste":                      "Paste",
        "common.copy":                       "Copy",
        "common.clear":                      "Clear",
        "common.clearAll":                   "Clear All",
        "common.cancel":                     "Cancel",
        "common.indent":                     "Indent:",
        "common.indent.2":                   "2 spaces",
        "common.indent.4":                   "4 spaces",
        "common.indent.tab":                 "Tab",
        "common.format":                     "Format",
        "common.minify":                     "Minify",
        "common.compare":                    "Compare",

        // JSON
        "json.placeholder":                  "Paste your JSON here…",
        "json.error.prefix":                 "Invalid JSON",
        "json.error.empty":                  "Input is empty.",
        "json.error.encoding":               "Cannot encode input as UTF-8.",

        // XML
        "xml.placeholder":                   "Paste your XML here…",
        "xml.error.prefix":                  "Invalid XML",
        "xml.error.empty":                   "Input is empty.",
        "xml.error.unclosed":                "Unclosed tag.",
        "xml.error.notokens":                "No tokens parsed.",

        // Diff
        "diff.original":                     "Original",
        "diff.changed":                      "Changed",
        "diff.placeholder.left":             "Paste original text…",
        "diff.placeholder.right":            "Paste changed text…",
        "diff.placeholder.empty":            "Enter text on both sides and tap Compare",
        "diff.summary.added":                "%d added",
        "diff.summary.removed":              "%d removed",
        "diff.summary.modified":             "%d modified",

        // Clipboard
        "clipboard.itemCount":               "%d items",
        "clipboard.itemCount.one":           "1 item",
        "clipboard.empty.title":             "Clipboard history is empty",
        "clipboard.empty.hint":              "Copy anything (Cmd+C) — it will appear here.",
        "clipboard.selectItem":              "Select an item on the left to view details",
        "clipboard.copyAgain":               "Copy again",
        "clipboard.pin":                     "Pin",
        "clipboard.unpin":                   "Unpin",
        "clipboard.delete":                  "Delete",
        "clipboard.deleteThis":              "Delete this item",
        "clipboard.confirm.title":           "Clear all clipboard history?",
        "clipboard.confirm.unpinned":        "Delete unpinned only",
        "clipboard.confirm.all":             "Delete all (including pinned)",
        "clipboard.kind.text":               "Text",
        "clipboard.kind.image":              "Image",
        "clipboard.image.unavailable":       "(Image not available)",
        "clipboard.preview.empty":           "(empty)",
        "clipboard.preview.image":           "🖼 Image — %d×%d, %d KB",

        // Menu bar
        "menubar.open":                      "Open DevPad",
        "menubar.empty":                     "No items yet",
        "menubar.quit":                      "Quit DevPad",

        // Settings
        "settings.title":                    "Settings",
        "settings.section.appearance":       "Appearance",
        "settings.theme":                    "Theme",
        "settings.theme.system":             "System",
        "settings.theme.light":              "Light",
        "settings.theme.dark":               "Dark",
        "settings.theme.footer":             "Choose how DevPad looks. \"System\" follows your macOS appearance.",
        "settings.section.language":         "Language",
        "settings.language":                 "Language",
        "settings.language.system":          "System",
        "settings.language.english":         "English",
        "settings.language.vietnamese":      "Tiếng Việt",
        "settings.language.footer":          "The change applies immediately, no restart required.",

        // Settings — About / License
        "settings.section.about":            "About",
        "settings.about.version":            "Version",
        "settings.about.copyright":          "Copyright",
        "settings.about.copyright.value":    "© 2026 bachbnt. All rights reserved.",
        "settings.about.license":            "License",
        "settings.about.license.value":      "Proprietary",
        "settings.about.license.footer":     "Unauthorized copying, modification or distribution of this software is strictly prohibited without prior written permission.",

        // Window
        "window.minSize":                    "DevPad"
    ]

    // MARK: Vietnamese

    private static let vi: [String: String] = [
        "app.name":                          "DevPad",
        "sidebar.json":                      "Định dạng JSON",
        "sidebar.xml":                       "Định dạng XML",
        "sidebar.diff":                      "So sánh khác biệt",
        "sidebar.clipboard":                 "Lịch sử Clipboard",
        "sidebar.settings":                  "Cài đặt",

        "common.paste":                      "Dán",
        "common.copy":                       "Sao chép",
        "common.clear":                      "Xóa",
        "common.clearAll":                   "Xóa tất cả",
        "common.cancel":                     "Hủy",
        "common.indent":                     "Thụt lề:",
        "common.indent.2":                   "2 dấu cách",
        "common.indent.4":                   "4 dấu cách",
        "common.indent.tab":                 "Tab",
        "common.format":                     "Định dạng",
        "common.minify":                     "Rút gọn",
        "common.compare":                    "So sánh",

        "json.placeholder":                  "Dán JSON vào đây…",
        "json.error.prefix":                 "JSON không hợp lệ",
        "json.error.empty":                  "Nội dung trống.",
        "json.error.encoding":               "Không thể mã hóa UTF-8.",

        "xml.placeholder":                   "Dán XML vào đây…",
        "xml.error.prefix":                  "XML không hợp lệ",
        "xml.error.empty":                   "Nội dung trống.",
        "xml.error.unclosed":                "Tag chưa đóng.",
        "xml.error.notokens":                "Không phân tích được token nào.",

        "diff.original":                     "Bản gốc",
        "diff.changed":                      "Bản sửa",
        "diff.placeholder.left":             "Dán văn bản gốc…",
        "diff.placeholder.right":            "Dán văn bản đã sửa…",
        "diff.placeholder.empty":            "Nhập văn bản hai bên và bấm So sánh",
        "diff.summary.added":                "Thêm %d",
        "diff.summary.removed":              "Xóa %d",
        "diff.summary.modified":             "Sửa %d",

        "clipboard.itemCount":               "%d mục",
        "clipboard.itemCount.one":           "1 mục",
        "clipboard.empty.title":             "Chưa có gì trong lịch sử",
        "clipboard.empty.hint":              "Copy bất kỳ (Cmd+C) — sẽ xuất hiện ở đây.",
        "clipboard.selectItem":              "Chọn 1 mục bên trái để xem chi tiết",
        "clipboard.copyAgain":               "Copy lại",
        "clipboard.pin":                     "Ghim",
        "clipboard.unpin":                   "Bỏ ghim",
        "clipboard.delete":                  "Xóa",
        "clipboard.deleteThis":              "Xóa mục này",
        "clipboard.confirm.title":           "Xóa toàn bộ lịch sử clipboard?",
        "clipboard.confirm.unpinned":        "Chỉ xóa mục chưa ghim",
        "clipboard.confirm.all":             "Xóa tất cả (kể cả mục đã ghim)",
        "clipboard.kind.text":               "Văn bản",
        "clipboard.kind.image":              "Hình ảnh",
        "clipboard.image.unavailable":       "(Hình ảnh không khả dụng)",
        "clipboard.preview.empty":           "(trống)",
        "clipboard.preview.image":           "🖼 Hình — %d×%d, %d KB",

        "menubar.open":                      "Mở DevPad",
        "menubar.empty":                     "Chưa có mục nào",
        "menubar.quit":                      "Thoát DevPad",

        "settings.title":                    "Cài đặt",
        "settings.section.appearance":       "Giao diện",
        "settings.theme":                    "Chế độ",
        "settings.theme.system":             "Theo hệ thống",
        "settings.theme.light":              "Sáng",
        "settings.theme.dark":               "Tối",
        "settings.theme.footer":             "Chọn giao diện cho DevPad. \"Theo hệ thống\" sẽ theo cài đặt macOS.",
        "settings.section.language":         "Ngôn ngữ",
        "settings.language":                 "Ngôn ngữ",
        "settings.language.system":          "Theo hệ thống",
        "settings.language.english":         "English",
        "settings.language.vietnamese":      "Tiếng Việt",
        "settings.language.footer":          "Thay đổi áp dụng ngay, không cần khởi động lại.",

        "settings.section.about":            "Thông tin",
        "settings.about.version":            "Phiên bản",
        "settings.about.copyright":          "Bản quyền",
        "settings.about.copyright.value":    "© 2026 bachbnt. Bảo lưu mọi quyền.",
        "settings.about.license":            "Giấy phép",
        "settings.about.license.value":      "Proprietary",
        "settings.about.license.footer":     "Nghiêm cấm sao chép, chỉnh sửa hoặc phân phối phần mềm này khi chưa có sự cho phép bằng văn bản.",

        "window.minSize":                    "DevPad"
    ]
}
