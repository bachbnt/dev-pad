// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  ClipboardItem.swift
//  DevPad
//
//  Represents a single entry in the clipboard history. Encodable so the
//  history can be persisted to UserDefaults.
//

import Foundation
import AppKit

struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let text: String?         // populated when kind == .text
    let imageData: Data?      // PNG bytes, populated when kind == .image
    let createdAt: Date
    var pinned: Bool

    init(id: UUID = UUID(),
         kind: Kind,
         text: String? = nil,
         imageData: Data? = nil,
         createdAt: Date = Date(),
         pinned: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.createdAt = createdAt
        self.pinned = pinned
    }

    // MARK: - Convenience

    /// Short preview suitable for menu/list rows.
    var preview: String {
        switch kind {
        case .text:
            let raw = text ?? ""
            let stripped = raw.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespaces)
            if stripped.count > 80 {
                return String(stripped.prefix(80)) + "…"
            }
            return stripped.isEmpty ? "(empty)" : stripped
        case .image:
            if let data = imageData,
               let img = NSImage(data: data) {
                let w = Int(img.size.width.rounded())
                let h = Int(img.size.height.rounded())
                let kb = max(1, data.count / 1024)
                return "🖼 Image — \(w)×\(h), \(kb) KB"
            }
            return "🖼 Image"
        }
    }

    /// Returns an NSImage suitable for displaying a thumbnail.
    var nsImage: NSImage? {
        guard kind == .image, let data = imageData else { return nil }
        return NSImage(data: data)
    }

    /// Hash used to deduplicate items: identical text or identical bytes.
    var dedupKey: String {
        switch kind {
        case .text:
            return "T:" + (text ?? "")
        case .image:
            // Use byte length + first/last bytes as a cheap fingerprint.
            guard let d = imageData, !d.isEmpty else { return "I:empty" }
            let head = d.prefix(16).map { String(format: "%02x", $0) }.joined()
            let tail = d.suffix(16).map { String(format: "%02x", $0) }.joined()
            return "I:\(d.count):\(head):\(tail)"
        }
    }
}
