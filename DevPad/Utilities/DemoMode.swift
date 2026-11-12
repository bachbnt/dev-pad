// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  DemoMode.swift
//  DevPad
//
//  Screenshot helper. When the app is launched with the `--demo-fill`
//  argument (or the `DEVPAD_DEMO_FILL` env var), every tab is
//  pre-loaded with curated sample content so the maintainer can capture
//  marketing screenshots without typing anything in.
//
//  How to enable:
//    • Xcode → Edit Scheme → Run → Arguments → add `--demo-fill`
//    • Or: DEVPAD_DEMO_FILL=1 open /Applications/DevPad.app
//
//  Each view only injects its sample if its local state is empty, so
//  the user can still type over the placeholders during a real screenshot
//  session.
//

import Foundation
import AppKit

enum DemoMode {

    private static let launchArgument = "--demo-fill"
    private static let environmentKey = "DEVPAD_DEMO_FILL"

    /// `true` if the maintainer launched the app expecting auto-populated
    /// sample content (e.g. for taking marketing screenshots).
    ///
    /// Release builds always return `false` so the optimizer can dead-code
    /// strip the entire demo-injection path. The sample-content string
    /// literals further down still ship in Release (Swift keeps `static
    /// let` constants reachable from the type metadata), but they're
    /// never referenced from a hot code path, so they end up unused
    /// weight only. Wrapping them in `#if DEBUG` would force every view
    /// that references them to also conditionalise — not worth the
    /// noise for a few hundred bytes.
    static var isOn: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains(launchArgument) {
            return true
        }
        if ProcessInfo.processInfo.environment[environmentKey] != nil {
            return true
        }
#endif
        return false
    }

    /// Call from the app's main scene as soon as we have a chance to
    /// touch the singletons. Seeds the clipboard and drop-shelf with
    /// believable content; per-view samples (JSON/XML/SQL/URL/QR/Diff)
    /// are injected via each view's `.onAppear` hook by reading the
    /// `sample*` properties below.
    @MainActor
    static func bootstrap() {
        guard isOn else { return }
        seedClipboard()
        seedDropShelf()
    }

    // MARK: - Per-tab samples

    static let sampleJSON: String = """
    {
      "user": {
        "id": 42,
        "name": "bachbnt",
        "email": "[email protected]",
        "roles": ["admin", "editor"],
        "active": true
      },
      "session": {
        "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
        "expiresAt": "2026-12-31T23:59:59Z"
      },
      "preferences": {
        "theme": "dark",
        "language": "vi",
        "notifications": {
          "email": true,
          "push": false
        }
      }
    }
    """

    static let sampleXML: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <library>
      <book id="1">
        <title>Swift in Depth</title>
        <author>Tjeerd in 't Veen</author>
        <year>2019</year>
        <tags>
          <tag>swift</tag>
          <tag>language</tag>
        </tags>
      </book>
      <book id="2">
        <title>SwiftUI by Tutorials</title>
        <author>raywenderlich.com</author>
        <year>2022</year>
      </book>
    </library>
    """

    static let sampleSQL: String = """
    select u.id, u.name, u.email, count(o.id) as order_count, sum(o.total) as revenue from users u left join orders o on o.user_id = u.id where u.created_at > '2024-01-01' and u.status = 'active' group by u.id, u.name, u.email having count(o.id) > 5 order by revenue desc limit 100;
    """

    static let sampleURL: String =
        "https://user:secret@api.example.com:8443/v2/users/42/orders?status=paid&page=1&sort=-created_at&include=items,address#order-section"

    static let sampleQRText: String = "https://github.com/bachbnt/dev-pad"

    /// Pattern, flags, and test text for the Regex Tester demo. The pattern
    /// finds email addresses and captures their `user` and `domain` parts so
    /// the named-group rendering shows up in the screenshot.
    static let sampleRegexPattern: String =
        #"(?<user>[\w.+-]+)@(?<domain>[\w.-]+\.[A-Za-z]{2,})"#

    static let sampleRegexFlags: RegexFlags = [.caseInsensitive, .multiline]

    static let sampleRegexText: String = """
    Please reach out to [email protected] for product feedback.
    For billing issues, write to [email protected] or [email protected].
    Old contact (deprecated): [email protected]
    """

    /// Plain text seed for the Hash Generator demo. Picked to be long
    /// enough that every algorithm produces a visually distinct digest.
    static let sampleHashText: String =
        "DevPad — a native macOS developer utility. Quick, local, no telemetry."

    /// Text for the Base64 & URL Encode demo.
    static let sampleEncodeText: String =
        "DevPad: format, hash & decode — all offline."

    /// Unix timestamp for the Timestamp Converter demo (2023-11-14 22:13:20 UTC).
    static let sampleTimestamp: String = "1700000000"

    /// Which QR content type the QR demo opens on: `--demo-qr=vietqr|wifi|vcard`
    /// (or `DEVPAD_DEMO_QR`). Anything else keeps the plain-text sample.
    static var qrKind: String? {
#if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--demo-qr=") }) {
            return String(arg.dropFirst("--demo-qr=".count))
        }
        return ProcessInfo.processInfo.environment["DEVPAD_DEMO_QR"]
#else
        return nil
#endif
    }

    /// With `--demo-qr-scan`, the QR demo opens in Scan mode showing the
    /// decoded sample payload instead of the generated image.
    static var qrScan: Bool {
#if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--demo-qr-scan")
#else
        return false
#endif
    }

    // Fake data for the QR demos — never a real account, network or person.
    static let sampleVietQRBIN = "970436"
    static let sampleVietQRAccount = "0123456789"
    static let sampleVietQRAmount = "50000"
    static let sampleVietQRMessage = "Thanh toan don hang 1024"
    static let sampleWiFiSSID = "DevPad-Guest"
    static let sampleWiFiPassword = "welcome-2026"
    static let sampleCard = ContactCard(firstName: "An", lastName: "Nguyen", organization: "Example Co.",
                                        title: "Engineering Manager", mobile: "+84 90 123 4567",
                                        email: "an@example.com", website: "https://example.com")

    /// Made-up listeners for the Port Killer demo. The real tab would show
    /// the maintainer's actual processes in a public screenshot.
    static let samplePorts: [ListeningPort] = [
        ListeningPort(pid: 41872, processName: "node", port: 3000, addresses: ["::"]),
        ListeningPort(pid: 40215, processName: "postgres", port: 5432, addresses: ["127.0.0.1", "::1"]),
        ListeningPort(pid: 40388, processName: "redis-server", port: 6379, addresses: ["127.0.0.1"]),
        ListeningPort(pid: 42101, processName: "Python", port: 8000, addresses: ["127.0.0.1"]),
        ListeningPort(pid: 41990, processName: "java", port: 8080, addresses: ["::"]),
        ListeningPort(pid: 40977, processName: "docker-proxy", port: 9200, addresses: ["0.0.0.0"])
    ]

    /// HS256-signed JWT with a populated payload (iss/sub/aud/exp/iat/nbf/jti).
    /// `exp` is set to 2030-12-31 so the demo shows a "Valid" status no matter
    /// when screenshots are captured. Signed with secret = "devpad-demo-secret".
    static let sampleJWT: String = [
        // header  : {"alg":"HS256","typ":"JWT","kid":"devpad-key-1"}
        "eyJhbGciOiJIUzI1NiIsImtpZCI6ImRldnBhZC1rZXktMSIsInR5cCI6IkpXVCJ9",
        // payload : standard claims + custom name/roles
        "eyJhdWQiOlsiZGV2cGFkLXdlYiIsImRldnBhZC1tb2JpbGUiXSwiZXhwIjoxOTI" +
            "zNjE5NjAwLCJpYXQiOjE3NDcwNTk3MDAsImlzcyI6Imh0dHBzOi8vYWNjb3Vud" +
            "HMuZGV2cGFkLmFwcCIsImp0aSI6IjkyZmM5ZTQ3LWY3MWUtNGI0OS04YjFjLTU" +
            "wMjkzYTM0YmYwOSIsIm5hbWUiOiJiYWNoYm50Iiwicm9sZXMiOlsiYWRtaW4iL" +
            "CJlZGl0b3IiXSwic3ViIjoidXNlcl80MiJ9",
        // signature
        "Mu5j8btYwHvkLtgI4qVrtxKbnMnxHrqzNyHHGRm0E2I"
    ].joined(separator: ".")

    static let sampleDiffLeft: String = """
    // User authentication
    func login(email: String, password: String) -> Bool {
        guard let user = users.first(where: { $0.email == email }) else {
            return false
        }
        if user.password == password {
            session.start(for: user)
            return true
        }
        return false
    }

    let success = login(email: "[email protected]", password: pwd)
    print("Logged in: \\(success)")
    """

    static let sampleDiffRight: String = """
    // User authentication with hashing
    func login(email: String, password: String) -> Bool {
        guard let user = users.first(where: { $0.email == email.lowercased() }) else {
            return false
        }
        if user.passwordHash == hash(password) {
            session.start(for: user)
            return true
        }
        return false
    }

    let success = login(email: "[email protected]", password: pwd)
    print("Logged in: \\(success)")
    """

    // MARK: - Clipboard

    @MainActor
    private static func seedClipboard() {
        let mgr = ClipboardManager.shared
        guard mgr.items.isEmpty else { return }

        let samples: [ClipboardItem] = [
            ClipboardItem(
                kind: .text,
                text: "https://github.com/bachbnt/dev-pad",
                createdAt: Date().addingTimeInterval(-60 * 2),
                pinned: true
            ),
            ClipboardItem(
                kind: .text,
                text: "let formatted = try JSONFormatter.format(input, indent: 2)",
                createdAt: Date().addingTimeInterval(-60 * 6),
                pinned: true
            ),
            ClipboardItem(
                kind: .text,
                text: "TODO: review PR #142 before EOD",
                createdAt: Date().addingTimeInterval(-60 * 12)
            ),
            ClipboardItem(
                kind: .text,
                text: "SELECT id, name FROM users WHERE active = true ORDER BY created_at DESC LIMIT 50;",
                createdAt: Date().addingTimeInterval(-60 * 25)
            ),
            ClipboardItem(
                kind: .text,
                text: "[email protected]",
                createdAt: Date().addingTimeInterval(-60 * 40)
            ),
            ClipboardItem(
                kind: .text,
                text: "vi-VN, en-US, fr-FR, de-DE, ja-JP",
                createdAt: Date().addingTimeInterval(-60 * 90)
            ),
            ClipboardItem(
                kind: .text,
                text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
                createdAt: Date().addingTimeInterval(-60 * 120)
            ),
        ]

        mgr.injectForDemo(samples)
    }

    // MARK: - Drop Shelf

    @MainActor
    private static func seedDropShelf() {
        let mgr = DropShelfManager.shared
        guard mgr.urls.isEmpty else { return }

        // Use bundled system apps so the icons always look real.
        let candidates = [
            "/System/Applications/Calculator.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Reminders.app",
        ]
        let fm = FileManager.default
        for path in candidates where fm.fileExists(atPath: path) {
            mgr.add(URL(fileURLWithPath: path))
        }
    }
}
