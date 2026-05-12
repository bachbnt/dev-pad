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
        "sidebar.sql":                       "SQL Formatter",
        "sidebar.url":                       "URL Parser",
        "sidebar.qr":                        "QR Generator",
        "sidebar.diff":                      "Diff Compare",
        "sidebar.clipboard":                 "Clipboard History",
        "sidebar.dropshelf":                 "Drop Shelf",
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

        "sql.placeholder":                   "Paste your SQL here…",
        "sql.error.prefix":                  "Invalid SQL",
        "sql.error.empty":                   "Input is empty.",

        // URL Parser
        "url.placeholder":                   "Paste a URL here…",
        "url.parse":                         "Parse",
        "url.scheme":                        "Scheme",
        "url.user":                          "User",
        "url.password":                      "Password",
        "url.host":                          "Host",
        "url.port":                          "Port",
        "url.path":                          "Path",
        "url.query":                         "Query string",
        "url.queryParams":                   "Query parameters",
        "url.fragment":                      "Fragment",
        "url.error.invalid":                 "Couldn't parse URL.",
        "url.error.empty":                   "Input is empty.",
        "url.error.prefix":                  "Invalid URL",
        "url.empty.title":                   "Paste a URL to parse it",
        "url.empty.hint":                    "Splits the URL into scheme, host, path, query parameters, and fragment.",
        "url.queryParams.empty":             "(no query parameters)",
        "url.absent":                        "—",

        // QR Generator
        "qr.mode.generate":                  "Generate",
        "qr.mode.scan":                      "Scan",
        "qr.placeholder":                    "Type or paste text / URL to encode as QR…",
        "qr.generate":                       "Generate QR",
        "qr.save":                           "Save as PNG…",
        "qr.copy":                           "Copy QR image",
        "qr.errorCorrection":                "Error correction",
        "qr.errorCorrection.L":              "Low (~7% recovery)",
        "qr.errorCorrection.M":              "Medium (~15% recovery)",
        "qr.errorCorrection.Q":              "Quartile (~25% recovery)",
        "qr.errorCorrection.H":              "High (~30% recovery)",
        "qr.scan.dropHint":                  "Drop a QR-code image here, or click Choose file…",
        "qr.scan.choose":                    "Choose file…",
        "qr.scan.paste":                     "Paste from clipboard",
        "qr.scan.result":                    "Decoded text",
        "qr.scan.empty":                     "No image yet",
        "qr.scan.copy":                      "Copy decoded text",
        "qr.scan.openLink":                  "Open as link",
        "qr.error.empty":                    "Enter text to encode.",
        "qr.error.tooLong":                  "Text is too long for a QR code.",
        "qr.error.invalidImage":             "Couldn't read the image.",
        "qr.error.noQR":                     "No QR code found in this image.",
        "qr.error.prefix":                   "QR error",
        "qr.saved":                          "Saved to %@",
        "qr.centerIcon":                     "Center icon",
        "qr.centerIcon.add":                 "Add icon",
        "qr.centerIcon.remove":              "Remove icon",
        "qr.centerIcon.hint":                "Adding a center icon hides part of the QR — Quartile or High error correction is recommended.",

        // Diff
        "diff.original":                     "Original",
        "diff.changed":                      "Changed",
        "diff.placeholder.left":             "Paste original text…",
        "diff.placeholder.right":            "Paste changed text…",
        "diff.placeholder.empty":            "Enter text on both sides and tap Compare",
        "diff.summary.added":                "%d added",
        "diff.summary.removed":              "%d removed",
        "diff.summary.modified":             "%d modified",
        "diff.identical":                    "Both sides are identical.",
        "diff.viewMode":                     "View",
        "diff.viewMode.split":               "Split",
        "diff.viewMode.unified":             "Unified",
        "diff.context":                      "Context",
        "diff.hunk.gap":                     "… %d unchanged line(s) hidden …",
        "diff.options.whitespace":           "Ignore whitespace",
        "diff.options.case":                 "Ignore case",

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
        "clipboard.section.pinned":          "Pinned",
        "clipboard.section.other":           "History",
        "clipboard.purePaste":               "Pure Paste",
        "clipboard.purePaste.tooltip":       "Auto-strip rich text formatting from copied text. Paste always lands as plain text.",

        // Menu bar
        "menubar.open":                      "Open DevPad",
        "menubar.empty":                     "No items yet",
        "menubar.quit":                      "Quit DevPad",

        // Drop Shelf — popup
        "dropshelf.title":                   "Drop Shelf",
        "dropshelf.empty":                   "Drop files here",
        "dropshelf.hint":                    "Drag files in, then drag them out together to a new destination.",
        "dropshelf.count":                   "%d file(s)",
        "dropshelf.clear":                   "Clear",
        "dropshelf.close":                   "Close",
        // Drop Shelf — main view / menubar section
        "dropshelf.toggle":                  "Enable",
        "dropshelf.toggleHint":              "When on, a floating shelf appears whenever you start dragging files anywhere on the Mac.",
        "dropshelf.disabled.title":          "Drop Shelf is off",
        "dropshelf.disabled.hint":           "Turn it on to start collecting files while you drag.",
        "dropshelf.list.empty":              "No files yet",
        "dropshelf.list.empty.hint":         "Drag files into the floating shelf and they'll appear here.",
        "dropshelf.remove":                  "Remove from shelf",
        // Menu-bar tab labels
        "menubar.tab.clipboard":             "Clipboard",
        "menubar.tab.dropshelf":             "Drop Shelf",

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

        // Settings — Drop Shelf
        "settings.section.dropshelf":        "Drop Shelf",
        "settings.dropshelf":         "Enable",
        "settings.dropshelf.footer":         "Show a floating shelf when you start dragging files. Drop files into it, then drag the bundle out to a new destination.",

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
        "sidebar.sql":                       "Định dạng SQL",
        "sidebar.url":                       "Phân tích URL",
        "sidebar.qr":                        "Tạo mã QR",
        "sidebar.diff":                      "So sánh khác biệt",
        "sidebar.clipboard":                 "Lịch sử Clipboard",
        "sidebar.dropshelf":                 "Khay thả file",
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

        "sql.placeholder":                   "Dán SQL vào đây…",
        "sql.error.prefix":                  "SQL không hợp lệ",
        "sql.error.empty":                   "Nội dung trống.",

        "url.placeholder":                   "Dán URL vào đây…",
        "url.parse":                         "Phân tích",
        "url.scheme":                        "Giao thức",
        "url.user":                          "User",
        "url.password":                      "Mật khẩu",
        "url.host":                          "Máy chủ",
        "url.port":                          "Cổng",
        "url.path":                          "Đường dẫn",
        "url.query":                         "Query string",
        "url.queryParams":                   "Tham số query",
        "url.fragment":                      "Fragment",
        "url.error.invalid":                 "Không phân tích được URL.",
        "url.error.empty":                   "Nội dung trống.",
        "url.error.prefix":                  "URL không hợp lệ",
        "url.empty.title":                   "Dán URL để phân tích",
        "url.empty.hint":                    "Tách URL thành scheme, host, path, tham số query và fragment.",
        "url.queryParams.empty":             "(không có tham số)",
        "url.absent":                        "—",

        "qr.mode.generate":                  "Tạo",
        "qr.mode.scan":                      "Quét",
        "qr.placeholder":                    "Gõ hoặc dán text / URL để tạo QR…",
        "qr.generate":                       "Tạo QR",
        "qr.save":                           "Lưu PNG…",
        "qr.copy":                           "Copy ảnh QR",
        "qr.errorCorrection":                "Mức sửa lỗi",
        "qr.errorCorrection.L":              "Thấp (~7% phục hồi)",
        "qr.errorCorrection.M":              "Trung bình (~15% phục hồi)",
        "qr.errorCorrection.Q":              "Khá cao (~25% phục hồi)",
        "qr.errorCorrection.H":              "Cao (~30% phục hồi)",
        "qr.scan.dropHint":                  "Thả ảnh QR vào đây, hoặc bấm Chọn file…",
        "qr.scan.choose":                    "Chọn file…",
        "qr.scan.paste":                     "Dán từ clipboard",
        "qr.scan.result":                    "Nội dung giải mã",
        "qr.scan.empty":                     "Chưa có ảnh",
        "qr.scan.copy":                      "Copy text",
        "qr.scan.openLink":                  "Mở như liên kết",
        "qr.error.empty":                    "Nhập text để encode.",
        "qr.error.tooLong":                  "Text quá dài cho mã QR.",
        "qr.error.invalidImage":             "Không đọc được ảnh.",
        "qr.error.noQR":                     "Không tìm thấy mã QR trong ảnh.",
        "qr.error.prefix":                   "Lỗi QR",
        "qr.saved":                          "Đã lưu vào %@",
        "qr.centerIcon":                     "Icon giữa",
        "qr.centerIcon.add":                 "Thêm icon",
        "qr.centerIcon.remove":              "Xóa icon",
        "qr.centerIcon.hint":                "Icon giữa che bớt mã QR — nên dùng mức sửa lỗi Quartile hoặc High.",

        "diff.original":                     "Bản gốc",
        "diff.changed":                      "Bản sửa",
        "diff.placeholder.left":             "Dán văn bản gốc…",
        "diff.placeholder.right":            "Dán văn bản đã sửa…",
        "diff.placeholder.empty":            "Nhập văn bản hai bên và bấm So sánh",
        "diff.summary.added":                "Thêm %d",
        "diff.summary.removed":              "Xóa %d",
        "diff.summary.modified":             "Sửa %d",
        "diff.identical":                    "Hai bên giống hệt nhau.",
        "diff.viewMode":                     "Hiển thị",
        "diff.viewMode.split":               "Tách 2 cột",
        "diff.viewMode.unified":             "Ghép 1 cột",
        "diff.context":                      "Ngữ cảnh",
        "diff.hunk.gap":                     "… %d dòng không đổi đã ẩn …",
        "diff.options.whitespace":           "Bỏ qua khoảng trắng",
        "diff.options.case":                 "Bỏ qua hoa thường",

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
        "clipboard.section.pinned":          "Đã ghim",
        "clipboard.section.other":           "Lịch sử",
        "clipboard.purePaste":               "Bỏ định dạng",
        "clipboard.purePaste.tooltip":       "Tự động bỏ định dạng (rich text) khỏi clipboard. Khi paste sẽ ra plain text.",

        "menubar.open":                      "Mở DevPad",
        "menubar.empty":                     "Chưa có mục nào",
        "menubar.quit":                      "Thoát DevPad",

        "dropshelf.title":                   "Khay thả file",
        "dropshelf.empty":                   "Thả file vào đây",
        "dropshelf.hint":                    "Kéo file vào, rồi kéo cả bộ ra một thư mục mới.",
        "dropshelf.count":                   "%d file",
        "dropshelf.clear":                   "Xóa khay",
        "dropshelf.close":                   "Đóng",
        "dropshelf.dragOut":                 "Kéo cả bộ ra",
        "dropshelf.toggle":                  "Bật",
        "dropshelf.toggleHint":              "Khi bật, khay nổi sẽ tự hiện khi bạn bắt đầu kéo file ở bất kỳ đâu trên máy.",
        "dropshelf.disabled.title":          "Khay thả đang tắt",
        "dropshelf.disabled.hint":           "Bật lên để bắt đầu gom file khi đang kéo.",
        "dropshelf.list.empty":              "Chưa có file nào",
        "dropshelf.list.empty.hint":         "Kéo file vào khay nổi — chúng sẽ hiện ở đây.",
        "dropshelf.remove":                  "Xóa khỏi khay",
        "menubar.tab.clipboard":             "Clipboard",
        "menubar.tab.dropshelf":             "Khay thả file",

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

        "settings.section.dropshelf":        "Khay thả file",
        "settings.dropshelf":                "Bật",
        "settings.dropshelf.footer":         "Hiện khay nổi khi bạn bắt đầu kéo file. Thả file vào khay, sau đó kéo cả bộ ra thư mục mới.",

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
