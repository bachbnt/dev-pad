// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  ClipboardManager.swift
//  DevPad
//
//  Watches NSPasteboard for changes and stores up to `maxItems` recent
//  text/image items. Pinned items are kept on top and never evicted by
//  the size cap. Persists to UserDefaults so history survives relaunches.
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

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var pollTimer: Timer?
    private let storageKey = "DevPad.ClipboardHistory.v1"

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
        // Poll every 0.6s — light enough not to be noticed, fast enough to feel live.
        let timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
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
        // Move the chosen item to the top so it's easier to find again.
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            let it = items.remove(at: idx)
            items.insert(it, at: 0)
            persist()
        }
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        sortAndCap()
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
        items = samples
        sortAndCap()
        persist()
    }

    // MARK: - Pasteboard polling

    private func checkPasteboard() {
        let cc = pasteboard.changeCount
        guard cc != lastChangeCount else { return }
        lastChangeCount = cc

        if suppressNextChange {
            suppressNextChange = false
            return
        }

        // Try image first (so a copy from Preview is recorded as image, not its filename).
        if let imgs = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let img = imgs.first,
           let data = pngData(from: img) {
            ingest(.init(kind: .image, imageData: data))
            return
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
                return
            }
        }

        if let s = pasteboard.string(forType: .string),
           !s.isEmpty {
            ingest(.init(kind: .text, text: s))
        }
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

    private func ingest(_ candidate: ClipboardItem) {
        // Deduplicate: if the existing top item has the same content, just bump it.
        if let existing = items.first, existing.dedupKey == candidate.dedupKey {
            return
        }
        // If the same content exists elsewhere in history, move it to the top instead of duplicating.
        if let idx = items.firstIndex(where: { $0.dedupKey == candidate.dedupKey }) {
            let it = items.remove(at: idx)
            items.insert(it, at: 0)
            sortAndCap()
            persist()
            return
        }
        items.insert(candidate, at: 0)
        sortAndCap()
        persist()
    }

    private func sortAndCap() {
        // Stable sort: pinned first, then by creation time desc.
        items.sort { a, b in
            if a.pinned != b.pinned { return a.pinned && !b.pinned }
            return a.createdAt > b.createdAt
        }
        // Cap unpinned items only.
        var unpinnedCount = 0
        var newList: [ClipboardItem] = []
        for it in items {
            if it.pinned {
                newList.append(it)
            } else if unpinnedCount < maxItems {
                newList.append(it)
                unpinnedCount += 1
            }
        }
        items = newList
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Persisted history is best-effort; silently ignore encode errors.
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([ClipboardItem].self, from: data)
            items = decoded
            sortAndCap()
        } catch {
            // Old/corrupt data — start fresh.
            items = []
        }
    }
}
