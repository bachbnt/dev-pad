//
//  MultiFileDragSource.swift
//  DevPad
//
//  SwiftUI's `.onDrag` returns a single `NSItemProvider`, so it can't
//  drag a *set* of files out to Finder / Mail / any other drop target.
//  This file bridges to AppKit's `NSDraggingSource` API, which natively
//  supports a session containing multiple `NSDraggingItem`s (one per
//  file). The result feels like Dropover: grab the stack, drop on a
//  folder, all files land together.
//
//  Usage:
//
//      MultiFileDragSource(urls: manager.urls) {
//          MyStackView()
//      }
//
//  The hosted SwiftUI content is the visual; the surrounding NSView
//  catches mouseDown / mouseDragged and starts the AppKit drag.
//

import SwiftUI
import AppKit

struct MultiFileDragSource<Content: View>: NSViewRepresentable {
    let urls: [URL]
    let content: () -> Content

    init(urls: [URL], @ViewBuilder content: @escaping () -> Content) {
        self.urls = urls
        self.content = content
    }

    func makeNSView(context: Context) -> DragSourceHostView<Content> {
        let view = DragSourceHostView(rootView: content())
        view.urls = urls
        return view
    }

    func updateNSView(_ nsView: DragSourceHostView<Content>, context: Context) {
        nsView.urls = urls
        nsView.update(rootView: content())
    }
}

/// `NSView` that hosts a SwiftUI subtree (for the visual) and acts as
/// `NSDraggingSource`, beginning a drag of every URL in `urls` once the
/// user moves the mouse beyond a small threshold.
final class DragSourceHostView<Content: View>: NSView, NSDraggingSource {

    var urls: [URL] = []

    private let hosting: NSHostingView<Content>
    private var mouseDownLocation: NSPoint?

    init(rootView: Content) {
        self.hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func update(rootView: Content) {
        hosting.rootView = rootView
    }

    override var intrinsicContentSize: NSSize {
        hosting.intrinsicContentSize
    }

    /// IMPORTANT: prevents the parent panel (which has
    /// `isMovableByWindowBackground = true`) from stealing our mouseDown
    /// for window movement. Without this override, dragging the file
    /// stack drags the panel itself instead of starting a file drag.
    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        // Defer to mouseDragged so a plain click doesn't start a drag.
        mouseDownLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard !urls.isEmpty, let start = mouseDownLocation else { return }
        let here = event.locationInWindow
        // Require ~3pt of movement before committing to a drag, matching
        // AppKit conventions.
        let distance = hypot(here.x - start.x, here.y - start.y)
        guard distance >= 3 else { return }

        beginMultiFileDrag(event: event)
        mouseDownLocation = nil
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
    }

    // MARK: - Drag session

    private func beginMultiFileDrag(event: NSEvent) {
        var draggingItems: [NSDraggingItem] = []
        let stride: CGFloat = 6

        for (index, url) in urls.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)

            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let iconSize = NSSize(width: 56, height: 56)
            icon.size = iconSize

            // Stagger each item's drag frame so the preview looks like a
            // small stack of files following the cursor.
            let origin = convert(event.locationInWindow, from: nil)
            let offset = CGFloat(index) * stride
            let frame = NSRect(
                x: origin.x - iconSize.width / 2 + offset,
                y: origin.y - iconSize.height / 2 - offset,
                width: iconSize.width,
                height: iconSize.height
            )
            item.setDraggingFrame(frame, contents: icon)

            draggingItems.append(item)
        }

        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Allow both copy and move targets. The destination (Finder, app,
        // etc.) chooses which to perform based on its own rules and any
        // modifier keys the user is holding.
        switch context {
        case .outsideApplication: return [.copy, .move, .link]
        case .withinApplication:  return [.copy, .move]
        @unknown default:         return [.copy]
        }
    }

    /// Allow the user to drag this stack into any application — including
    /// re-dropping into our own window (e.g. another shelf in the future).
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }
}
