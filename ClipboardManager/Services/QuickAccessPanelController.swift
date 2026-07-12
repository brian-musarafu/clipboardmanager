import AppKit
import SwiftUI

/// Presents the clipboard UI as a floating panel summoned by the global ⌘⇧V
/// shortcut. SwiftUI's `MenuBarExtra` window can't be opened programmatically,
/// so the hotkey path uses its own panel hosting the same `MainView`.
@MainActor
final class QuickAccessPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var escapeMonitor: Any?
    private let rootView: AnyView

    init(rootView: AnyView) {
        self.rootView = rootView
    }

    /// Shows the panel if hidden, hides it if already visible.
    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // Activate our app so the search field can take keyboard focus, and
        // center the panel on the active screen.
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        installEscapeMonitor()
    }

    func hide() {
        removeEscapeMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - Panel construction

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    // MARK: - Dismissal

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    /// Auto-dismiss when the panel loses key status (click elsewhere, or after a
    /// paste hides the app).
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
