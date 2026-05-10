# DevPad

App macOS native cho developer — format JSON/XML, so sánh diff, lưu lịch sử clipboard. Chạy ngầm ở menu bar, ẩn dock icon khi không dùng.

![License](https://img.shields.io/badge/license-Proprietary-blue.svg)
![macOS](https://img.shields.io/badge/macOS-13.0+-black.svg)
![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)

## Tính năng

- **JSON Formatter** — paste JSON → bấm Format → text trong ô input thành pretty-printed. Hỗ trợ Minify, indent 2/4 spaces hoặc Tab.
- **XML Formatter** — pretty-print XML với indentation chuẩn.
- **Diff Compare** — so sánh 2 đoạn text side-by-side, line-level + word-level inline highlight (đỏ/xanh) như diffchecker.com.
- **Clipboard History** — tự lưu 20 item clipboard gần nhất (text + image), pin item quan trọng, persist sau khi quit, xóa từng item hoặc xóa tất cả.
- **Menu bar app** — icon `📋` ở thanh menu macOS, click để xem clipboard history nhanh, click vào item để copy lại.
- **Settings** — chọn theme (System / Light / Dark) và ngôn ngữ (English / Tiếng Việt). Đổi runtime, không cần khởi động lại.
- **Localization** — full UI dịch sang tiếng Việt và tiếng Anh.

## Yêu cầu

- macOS 13.0 (Ventura) trở lên
- Xcode 15+ để build từ source

## Build & chạy

### Mở trong Xcode

```bash
open DevPad.xcodeproj
```

Sau đó nhấn `⌘R` để build và chạy.

### Đóng gói DMG

```bash
./build_dmg.sh
```

Output: `build/DevPad.dmg`. Mount file DMG, kéo `DevPad.app` vào folder Applications là xong.

> ⚠️ DMG mặc định build với ad-hoc signing (không có Apple Developer ID). Lần đầu mở phải **right-click → Open** để bypass Gatekeeper.
>
> Nếu có Developer ID, chạy `./build_dmg.sh --signed` để dùng signing identity của Xcode.

## Cách dùng

### Menu bar
Sau khi mở app lần đầu, icon clipboard hiện ở thanh menu macOS (góc phải trên cùng). Click để xem 20 item gần nhất:

- Click vào 1 item → copy lại vào clipboard.
- Hover 1 item → hiện nút **pin** và **delete**.
- Header có badge đếm số item + nút clear all.

### Window
Click **Open DevPad** ở footer menu bar popup để mở cửa sổ chính. Sidebar có 5 tab:

| Tab | Mô tả |
|-----|-------|
| JSON Formatter | Paste JSON, bấm Format hoặc `⌘↵` |
| XML Formatter | Paste XML, bấm Format hoặc `⌘↵` |
| Diff Compare | 2 ô text side-by-side, bấm Compare hoặc `⌘↵` |
| Clipboard History | View đầy đủ với detail pane bên phải |
| Settings | Theme + Language |

### Lifecycle (quan trọng)

- **Đóng cửa sổ (red X)** → dock icon ẩn, app vẫn chạy ngầm với menu bar icon.
- **Mở lại** → click "Open DevPad" trong menu bar popup.
- **Quit hoàn toàn** → nút Quit trong menu bar popup, hoặc `⌘Q` khi window đang focus.

Đây là pattern menu-bar app chuẩn (giống Maccy, Bartender). Khác với app thường ở chỗ đóng cửa sổ KHÔNG quit app.

### Phím tắt

| Phím | Action |
|------|--------|
| `⌘↵` | Run Format / Compare (trong view formatter/diff) |
| `⌘,` | Mở Settings |
| `⌘Q` | Quit app (chỉ khi window focus) |

## Cấu trúc dự án

```
DevPad/
├── DevPad.xcodeproj/                # Xcode project file
├── DevPad/                          # Source code
│   ├── DevPadApp.swift              # App entry point, scene definitions
│   ├── AppDelegate.swift            # Window/dock activation policy
│   ├── MainWindowView.swift         # Sidebar navigation
│   ├── Models/
│   │   ├── AppSettings.swift        # Theme + language store (persisted)
│   │   └── ClipboardItem.swift      # Codable clipboard entry
│   ├── Utilities/
│   │   ├── JSONFormatter.swift      # Pretty printer + minifier
│   │   ├── XMLFormatter.swift       # Tokenizer-based pretty printer
│   │   ├── DiffEngine.swift         # LCS line + word/char diff
│   │   ├── ClipboardManager.swift   # NSPasteboard polling, persist
│   │   └── Localization.swift       # EN/VI string catalog
│   ├── Views/
│   │   ├── JSONFormatterView.swift
│   │   ├── XMLFormatterView.swift
│   │   ├── DiffCompareView.swift
│   │   ├── ClipboardHistoryView.swift   # Window detail view
│   │   ├── ClipboardMenuBarView.swift   # Menu bar popover
│   │   └── SettingsView.swift
│   ├── Assets.xcassets/
│   ├── DevPad.entitlements          # App sandbox entitlements
│   └── Preview Content/
├── build_dmg.sh                     # Release build + DMG packaging
├── LICENSE
└── README.md
```

## Notes về implementation

- **Localization**: dictionary in-memory (`Localization.swift`) thay vì `Localizable.strings` để switch language runtime mà không cần restart. Mỗi view dùng `@EnvironmentObject AppSettings` và gọi `settings.t("key")` — khi `language` đổi thì @Published trigger re-render.
- **Clipboard polling**: `Timer` poll `NSPasteboard.general.changeCount` mỗi 0.6s. Trade-off giữa CPU và độ trễ.
- **Persistence**: clipboard history serialize qua `Codable` → `UserDefaults`. Image lưu dạng PNG bytes.
- **Diff algorithm**: LCS classic (`O(m·n)`) cho line-level. Sau đó cho mỗi modified line, chạy LCS thứ 2 ở token-level (chữ/số liền kề là 1 token, mỗi punctuation là 1 token riêng) để inline highlight đúng phần thay đổi.
- **Menu bar app pattern**: `applicationShouldTerminateAfterLastWindowClosed = false` + dynamic activation policy (`.regular` ↔ `.accessory`) để đóng window không quit app.
- **No Localizable.xcstrings**: lý do trên (runtime switch). Trade-off: không thể export sang phiên dịch viên qua Xcode String Catalog. Nếu sau này cần i18n nhiều ngôn ngữ thì migrate sang `.xcstrings` + Bundle override.

## License

Copyright © 2026 bachbnt. All rights reserved.

Xem file [LICENSE](LICENSE) để biết chi tiết.
