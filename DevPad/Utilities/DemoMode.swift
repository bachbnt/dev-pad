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
        "email": "dev@example.com",
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
    Please reach out to feedback@example.com for product feedback.
    For billing issues, write to billing@example.com or finance@example.org.
    Old contact (deprecated): old.support@example.net
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

    /// With `--demo-menubar=clipboard|dropshelf|ports` the menu-bar popover
    /// opens on that tab (for screenshots and layout checks).
    static var menuBarTab: String? {
#if DEBUG
        if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--demo-menubar=") }) {
            return String(arg.dropFirst("--demo-menubar=".count))
        }
#endif
        return nil
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

    let success = login(email: "dev@example.com", password: pwd)
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

    let success = login(email: "dev@example.com", password: pwd)
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
                text: "dev@example.com",
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

// MARK: - Self-screenshot (Debug builds only)

#if DEBUG
extension DemoMode {

    /// `--demo-screenshot=<name>.png [--demo-tool=<slug>]` — once the main
    /// window is up and the demo data is in, opens the given tool, renders the
    /// window itself (title bar, traffic lights and all) onto a transparent
    /// canvas with a soft shadow, like a ⇧⌘4-then-Space capture, writes the
    /// PNG and quits. The window draws itself, so no Screen Recording
    /// permission is needed. The App Sandbox only lets us write inside the
    /// container, so the file lands in `NSTemporaryDirectory()`; the full path
    /// is printed.
    @MainActor
    static func captureScreenshotIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        func value(_ prefix: String) -> String? {
            args.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        }
        guard let name = value("--demo-screenshot=") else { return }
        let tool = value("--demo-tool=")
        // The demo shelf files only show while the shelf is switched on. Scoped to
        // this tool so an ordinary --demo-fill run never flips a persisted setting.
        if tool == "dropshelf" { AppSettings.shared.dropShelfEnabled = true }

        // Fixed delays rather than polling: SwiftUI gives no "layout finished"
        // signal, and the demo data is applied in `onAppear`.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if let tool { AppSettings.shared.pendingTool = tool }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let path = (NSTemporaryDirectory() as NSString).appendingPathComponent((name as NSString).lastPathComponent)
                let ok = writeWindowScreenshot(to: path, tool: tool)
                print(ok ? "demo-screenshot: \(path)" : "demo-screenshot: FAILED")
                NSApp.terminate(nil)
            }
        }
    }

    @MainActor
    private static func renderWindow(_ frameView: NSView, scale: Int) -> NSBitmapImageRep? {
        let size = frameView.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                                         pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        return rep
    }

    /// `cacheDisplay` can't draw the vibrant selected row of the sidebar: it
    /// comes out solid black, label and icon included. `other` is a second
    /// capture with a different tool selected, where that row is drawn
    /// normally (dark glyphs on a light row). Its darkness becomes the white
    /// of the glyphs on an accent-coloured pill, which is how the selected
    /// row really looks.
    private static func repairSelectedSidebarRow(in shot: NSBitmapImageRep, using other: NSBitmapImageRep, accent: NSColor) {
        guard let pa = shot.bitmapData, let pb = other.bitmapData,
              shot.pixelsWide == other.pixelsWide, shot.pixelsHigh == other.pixelsHigh,
              shot.bytesPerRow == other.bytesPerRow else { return }
        let w = shot.pixelsWide, h = shot.pixelsHigh, stride = shot.bytesPerRow, bpp = shot.bitsPerPixel / 8
        let sidebarWidth = w * 4 / 10

        func isBlack(_ x: Int, _ y: Int) -> Bool {
            let o = y * stride + x * bpp
            return pa[o] < 14 && pa[o + 1] < 14 && pa[o + 2] < 14 && pa[o + 3] > 200
        }
        var top = -1, bottom = -1
        for y in 0..<h {
            var count = 0
            for x in 0..<sidebarWidth where isBlack(x, y) { count += 1 }
            if count > 250 {                      // a full-width pill row, not a line of text
                if top < 0 { top = y }
                bottom = y
            }
        }
        guard top >= 0 else { return }
        // Measure the pill along its middle line only, as one run of black: the
        // rows above and below can touch black text in the detail pane.
        let middle = (top + bottom) / 2
        var left = -1, right = -1, gap = 0
        for x in 0..<sidebarWidth {
            if isBlack(x, middle) {
                if left < 0 { left = x }
                right = x
                gap = 0
            } else if left >= 0 {
                gap += 1
                if gap > 6 { break }
            }
        }
        guard left >= 0, right - left > 100 else { return }

        func luminance(_ o: Int) -> Double {
            0.299 * Double(pb[o]) + 0.587 * Double(pb[o + 1]) + 0.114 * Double(pb[o + 2])
        }
        var light = 0.0, dark = 255.0
        for y in top...bottom {
            for x in left...right {
                let l = luminance(y * stride + x * bpp)
                light = max(light, l); dark = min(dark, l)
            }
        }
        guard light - dark > 20, let c = accent.usingColorSpace(.sRGB) else { return }
        let blue = (r: c.redComponent * 255, g: c.greenComponent * 255, b: c.blueComponent * 255)
        let radius = 14.0

        for y in top...bottom {
            for x in left...right {
                // Rounded-rectangle test, so the corners keep what was drawn there.
                let dx = max(Double(left) + radius - Double(x), Double(x) - (Double(right) - radius), 0)
                let dy = max(Double(top) + radius - Double(y), Double(y) - (Double(bottom) - radius), 0)
                if dx * dx + dy * dy > radius * radius { continue }
                let t = min(max((light - luminance(y * stride + x * bpp)) / (light - dark), 0), 1)
                let o = y * stride + x * bpp
                pa[o]     = UInt8(blue.r * (1 - t) + 255 * t)
                pa[o + 1] = UInt8(blue.g * (1 - t) + 255 * t)
                pa[o + 2] = UInt8(blue.b * (1 - t) + 255 * t)
                pa[o + 3] = 255
            }
        }
    }

    /// The sidebar toggle sits in a glass "platter" that renders as an empty
    /// circle offscreen; draw its glyph into the spot where the platter is.
    @MainActor
    private static func drawToolbarGlyphs(on shot: NSBitmapImageRep, in frameView: NSView) {
        var platters: [NSRect] = []
        func walk(_ v: NSView) {
            if String(describing: type(of: v)).contains("NSToolbarPlatterView"), v.bounds.width < 80 {
                platters.append(v.convert(v.bounds, to: frameView))
            }
            v.subviews.forEach(walk)
        }
        walk(frameView)
        guard !platters.isEmpty, let context = NSGraphicsContext(bitmapImageRep: shot),
              let symbol = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.secondaryLabelColor]))) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for platter in platters {
            let glyph = symbol.size
            symbol.draw(in: NSRect(x: platter.midX - glyph.width / 2, y: platter.midY - glyph.height / 2,
                                   width: glyph.width, height: glyph.height))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    @MainActor
    private static func writeWindowScreenshot(to path: String, tool: String?) -> Bool {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) && $0.frame.width > 800 }),
              let frameView = window.contentView?.superview else { return false }
        // The documented default size; a fresh container would otherwise open at the 900-pt minimum.
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))

        let size = frameView.bounds.size
        let scale = 2
        guard let shot = renderWindow(frameView, scale: scale) else { return false }

        // Second pass: move the selection elsewhere so the first tool's row is drawn normally.
        AppSettings.shared.pendingTool = (tool == "json" || tool == nil) ? "xml" : "json"
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        if let other = renderWindow(frameView, scale: scale) {
            repairSelectedSidebarRow(in: shot, using: other, accent: NSColor.controlAccentColor)
        }
        drawToolbarGlyphs(on: shot, in: frameView)

        // Same proportions as the screenshots already in docs/screenshots: a
        // 1574-px-wide canvas with the window inset by 56 px.
        let canvasWidth: CGFloat = 1574, margin: CGFloat = 56
        let windowWidth = canvasWidth - margin * 2
        let windowHeight = size.height * windowWidth / size.width
        let canvasHeight = Int(windowHeight + margin * 2 + 18)
        guard let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasWidth), pixelsHigh: canvasHeight,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: canvas) else { return false }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        let rect = NSRect(x: margin, y: margin + 18, width: windowWidth, height: windowHeight)
        let outline = NSBezierPath(roundedRect: rect, xRadius: 26, yRadius: 26)

        context.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 34
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.set()
        NSColor.white.setFill()
        outline.fill()
        context.restoreGraphicsState()

        context.saveGraphicsState()
        outline.addClip()
        NSImage(size: size, flipped: false) { _ in
            shot.draw(in: NSRect(origin: .zero, size: size))
            return true
        }.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        context.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.18).setStroke()
        outline.lineWidth = 1
        outline.stroke()

        guard let png = canvas.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
#endif
