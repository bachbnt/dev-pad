// DevPad — Copyright © 2026 bachbnt. Proprietary.
//
//  DropShelfManager.swift
//  DevPad
//
//  Holds the URLs currently sitting in the Drop Shelf. The list is
//  observable so any view that's showing the shelf can react to add/
//  remove/clear.
//

import Foundation
import Combine

@MainActor
final class DropShelfManager: ObservableObject {
    static let shared = DropShelfManager()

    /// Files currently parked in the shelf, oldest-first.
    @Published private(set) var urls: [URL] = []

    private init() {}

    func add(_ url: URL) {
        guard !urls.contains(url) else { return }
        urls.append(url)
    }

    func add(_ newURLs: [URL]) {
        for u in newURLs { add(u) }
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
    }

    func clear() {
        urls.removeAll()
    }
}
