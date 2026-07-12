import AppKit
import SwiftUI

/// Hosts the snippet library in a normal resizable window, summoned from the
/// menu-bar UI. Kept as an AppKit window (rather than a SwiftUI `Window` scene)
/// so it can be opened from both the menu-bar window and the ⌘⇧V panel.
@MainActor
final class SnippetsWindowController {
    private var window: NSWindow?
    private let rootView: AnyView

    init(rootView: AnyView) {
        self.rootView = rootView
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Snippets"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: rootView)
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
