// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  ClipboardStore.swift
//  DevPad
//
//  Disk persistence for the clipboard history. The item list (text, pin
//  state, timestamps) is a small JSON blob in UserDefaults; image bytes live
//  as `<uuid>.png` files in Application Support. Keeping megabytes of base64
//  out of the plist means a screenshot no longer makes every later
//  `persist()` re-encode and rewrite the whole history.
//
//  Thread-safe by construction (no shared mutable state) so ClipboardManager
//  can call `write` from a background queue.
//

import Foundation

struct ClipboardStore {
    let defaults: UserDefaults
    let key: String
    let imageDirectory: URL

    init(defaults: UserDefaults = .standard,
         key: String,
         imageDirectory: URL = ClipboardStore.defaultImageDirectory()) {
        self.defaults = defaults
        self.key = key
        self.imageDirectory = imageDirectory
    }

    static func defaultImageDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DevPad", isDirectory: true)
            .appendingPathComponent("ClipboardImages", isDirectory: true)
    }

    /// On-disk shape of an item. `imageData` is only ever *read* (v1 history
    /// stored PNG bytes inline); `write` never fills it.
    private struct Stored: Codable {
        var id: UUID
        var kind: ClipboardItem.Kind
        var text: String?
        var imageFile: String?
        var imageData: Data?
        var createdAt: Date
        var pinned: Bool
    }

    struct Loaded {
        var items: [ClipboardItem]
        /// True when the data came from the inline-image format, so the
        /// caller should write once to move the images out of UserDefaults.
        var needsMigration: Bool
    }

    // MARK: - Read

    func read() -> Loaded {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([Stored].self, from: data) else {
            return Loaded(items: [], needsMigration: false)
        }
        var items: [ClipboardItem] = []
        var migrate = false
        for s in stored {
            switch s.kind {
            case .text:
                items.append(ClipboardItem(id: s.id, kind: .text, text: s.text,
                                           createdAt: s.createdAt, pinned: s.pinned))
            case .image:
                var bytes: Data?
                if let file = s.imageFile {
                    bytes = try? Data(contentsOf: imageDirectory.appendingPathComponent(file))
                }
                if bytes == nil, let legacy = s.imageData {
                    bytes = legacy
                    migrate = true
                }
                // Image file gone and no inline copy: nothing to show, drop it.
                guard let png = bytes else { continue }
                items.append(ClipboardItem(id: s.id, kind: .image, imageData: png,
                                           createdAt: s.createdAt, pinned: s.pinned))
            }
        }
        return Loaded(items: items, needsMigration: migrate)
    }

    // MARK: - Write

    /// Best-effort: persisted history is a convenience, so I/O errors are
    /// swallowed rather than surfaced to the user.
    func write(_ items: [ClipboardItem]) {
        let fm = FileManager.default
        var stored: [Stored] = []
        var keepFiles = Set<String>()

        for item in items {
            var file: String?
            if item.kind == .image, let png = item.imageData {
                let name = "\(item.id.uuidString).png"
                if !fm.fileExists(atPath: imageDirectory.appendingPathComponent(name).path) {
                    try? fm.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
                    try? png.write(to: imageDirectory.appendingPathComponent(name), options: .atomic)
                }
                // Only reference the file if it really exists, otherwise the
                // item would silently vanish on next launch.
                if fm.fileExists(atPath: imageDirectory.appendingPathComponent(name).path) {
                    file = name
                    keepFiles.insert(name)
                }
            }
            stored.append(Stored(id: item.id, kind: item.kind, text: item.text,
                                 imageFile: file, imageData: nil,
                                 createdAt: item.createdAt, pinned: item.pinned))
        }

        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }

        // Delete after the JSON is saved so a crash in between can only leave
        // an orphan file, never a dangling reference.
        if let existing = try? fm.contentsOfDirectory(atPath: imageDirectory.path) {
            for name in existing where name.hasSuffix(".png") && !keepFiles.contains(name) {
                try? fm.removeItem(at: imageDirectory.appendingPathComponent(name))
            }
        }
    }
}
