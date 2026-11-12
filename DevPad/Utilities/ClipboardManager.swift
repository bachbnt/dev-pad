// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  ClipboardManager.swift
//  DevPad
//
//  Watches NSPasteboard for changes and stores up to `maxItems` recent
//  text/image items. Pinned items are kept on top and never evicted by
//  the size cap. History survives relaunches via ClipboardStore (JSON in
//  UserDefaults + image files on disk); ordering and privacy rules live in
//  ClipboardHistory so they can be tested without a pasteboard.
//

import Foundation
import AppKit
import Combine

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipboardItem] = []

    /// Maximum non-pinned items to retain.
    var maxItems: Int = 20

    /// Images larger than this (PNG bytes) are not recorded: 20 of them would
    /// sit in memory and on disk, and nobody scrolls back to a 50 MB bitmap.
    private let maxImageBytes = 10 * 1024 * 1024

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = ClipboardManager.fastInterval
    private var idleTicks = 0
    private var activationObserver: NSObjectProtocol?

    private static let fastInterval: TimeInterval = 0.6
    private static let slowInterval: TimeInterval = 2.0
    /// Quiet polls (~1 minute at the fast rate) before backing off.
    private static let idleTicksBeforeBackoff = 100

    private let store = ClipboardStore(key: "DevPad.ClipboardHistory.v1")
    /// Serial queue for disk writes and PNG conversion, kept off the main thread.
    private let ioQueue = DispatchQueue(label: "com.bachbnt.DevPad.clipboard-io", qos: .utility)
    private var persistGeneration = 0

    /// When the manager itself writes to the pasteboard (e.g. user clicks an old
    /// item to re-copy it), we don't want to record a duplicate entry.
    private var suppressNextChange: Bool = false

    private init() {
        self.lastChangeCount = pasteboard.changeCount
        load()
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTimer == nil else { return }
        schedulePolling(interval: Self.fastInterval)
        // Coming back to the app is when someone is most likely to look at the
        // history, so snap back to the fast rate and catch up immediately.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.wakePolling()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let token = activationObserver {
            NotificationCenter.default.removeObserver(token)
            activationObserver = nil
        }
    }

    /// Writes pending changes synchronously. Called on app termination, where
    /// the debounced write may not have fired yet.
    func flush() {
        persistGeneration += 1
        let snapshot = items
        let store = self.store
        ioQueue.sync { store.write(snapshot) }
    }

    // MARK: - Polling

    private func schedulePolling(interval: TimeInterval) {
        pollTimer?.invalidate()
        pollInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.pollTick()
            }
        }
        timer.tolerance = interval / 3
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func pollTick() {
        if checkPasteboard() {
            idleTicks = 0
            if pollInterval != Self.fastInterval { schedulePolling(interval: Self.fastInterval) }
        } else {
            idleTicks += 1
            if idleTicks >= Self.idleTicksBeforeBackoff, pollInterval != Self.slowInterval {
                schedulePolling(interval: Self.slowInterval)
            }
        }
    }

    private func wakePolling() {
        guard pollTimer != nil else { return }
        idleTicks = 0
        if pollInterval != Self.fastInterval { schedulePolling(interval: Self.fastInterval) }
        _ = checkPasteboard()
    }

    // MARK: - Mutations

    /// Copy an existing history item back to the pasteboard.
    func copyToPasteboard(_ item: ClipboardItem) {
        suppressNextChange = true
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            if let s = item.text {
                pasteboard.setString(s, forType: .string)
            }
        case .image:
            if let data = item.imageData,
               let img = NSImage(data: data) {
                pasteboard.writeObjects([img])
            }
        }
        lastChangeCount = pasteboard.changeCount
        // Bump it so it is easier to find again.
        items = ClipboardHistory.bumped(items, id: item.id, maxItems: maxItems)
        persist()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        items = ClipboardHistory.sortAndCap(items, maxItems: maxItems)
        persist()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    /// Removes all unpinned entries.
    func clearAll() {
        items.removeAll { !$0.pinned }
        persist()
    }

    /// Removes everything, pinned items included.
    func clearAllIncludingPinned() {
        items.removeAll()
        persist()
    }

    /// Seeds the history with a curated list of items. Used by `DemoMode`
    /// for screenshot/demo builds; no-op if the list is non-empty so we
    /// never overwrite a real user's clipboard.
    func injectForDemo(_ samples: [ClipboardItem]) {
        guard items.isEmpty else { return }
        items = ClipboardHistory.sortAndCap(samples, maxItems: maxItems)
        persist()
    }

    // MARK: - Pasteboard polling

    /// Returns true if the pasteboard changed since the last check (whether or
    /// not the change was recorded) so the poller knows to stay at full speed.
    @discardableResult
    private func checkPasteboard() -> Bool {
        let cc = pasteboard.changeCount
        guard cc != lastChangeCount else { return false }
        lastChangeCount = cc

        if suppressNextChange {
            suppressNextChange = false
            return true
        }

        // Password managers and similar mark secrets with a "don't record"
        // type. Bail before reading the content or touching the pasteboard,
        // so Pure Paste doesn't rewrite it either.
        if let types = pasteboard.types,
           ClipboardHistory.shouldSkip(pasteboardTypes: types.map(\.rawValue)) {
            return true
        }

        // Try image first (so a copy from Preview is recorded as image, not its filename).
        // Prefer the raw bytes already on the pasteboard: PNG is used as-is, TIFF is
        // converted off the main thread. Decoding to NSImage and re-encoding on the
        // main thread is only the fallback for other formats (PDF, image files).
        if let png = pasteboard.data(forType: .png) {
            ingestImage(png)
            return true
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            ioQueue.async { [weak self] in
                let png = ClipboardManager.pngData(fromTIFF: tiff)
                DispatchQueue.main.async { [weak self] in
                    if let png { self?.ingestImage(png) }
                }
            }
            return true
        }
        if let imgs = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = imgs.first,
           let tiff = img.tiffRepresentation,
           let png = ClipboardManager.pngData(fromTIFF: tiff) {
            ingestImage(png)
            return true
        }

        // PurePaste: when the toggle is on and the clipboard carries any
        // rich-text representation (RTF/HTML/etc.) alongside the plain
        // string, overwrite the pasteboard with just the plain text. Any
        // app that pastes afterward gets unformatted text.
        if AppSettings.shared.purePasteEnabled, hasRichTextContent() {
            if let plain = pasteboard.string(forType: .string), !plain.isEmpty {
                suppressNextChange = true
                pasteboard.clearContents()
                pasteboard.setString(plain, forType: .string)
                lastChangeCount = pasteboard.changeCount
                ingest(.init(kind: .text, text: plain))
                return true
            }
        }

        if let s = pasteboard.string(forType: .string),
           !s.isEmpty {
            ingest(.init(kind: .text, text: s))
        }
        return true
    }

    /// Returns true if the pasteboard advertises any rich-text type
    /// in addition to (or instead of) plain text.
    private func hasRichTextContent() -> Bool {
        guard let types = pasteboard.types else { return false }
        let richTypes: [NSPasteboard.PasteboardType] = [
            .rtf,
            .rtfd,
            .html,
            NSPasteboard.PasteboardType("public.html"),
            NSPasteboard.PasteboardType("public.rtf"),
            NSPasteboard.PasteboardType("com.apple.flat-rtfd"),
            NSPasteboard.PasteboardType("WebArchivePboardType")
        ]
        return richTypes.contains { types.contains($0) }
    }

    private func ingestImage(_ png: Data) {
        guard !png.isEmpty, png.count <= maxImageBytes else { return }
        ingest(.init(kind: .image, imageData: png))
    }

    private func ingest(_ candidate: ClipboardItem) {
        guard let updated = ClipboardHistory.inserting(candidate, into: items, maxItems: maxItems) else {
            return
        }
        items = updated
        persist()
    }

    /// Safe off the main thread: no pasteboard or UI state involved.
    nonisolated private static func pngData(fromTIFF tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Persistence

    /// Debounced: a burst of changes (copy, pin, delete) becomes one write,
    /// and the encoding + file I/O happen on `ioQueue`, not the main thread.
    private func persist() {
        persistGeneration += 1
        let generation = persistGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, generation == self.persistGeneration else { return }
            let snapshot = self.items
            let store = self.store
            self.ioQueue.async { store.write(snapshot) }
        }
    }

    private func load() {
        let loaded = store.read()
        items = ClipboardHistory.sortAndCap(loaded.items, maxItems: maxItems)
        if loaded.needsMigration { persist() }
    }
}
