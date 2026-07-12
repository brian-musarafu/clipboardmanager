import AppKit
import ApplicationServices

/// Sends a synthetic ⌘V to the frontmost application so a clicked history item
/// is pasted straight into whatever field the user had focused.
///
/// This needs the **Accessibility** permission (System Settings → Privacy &
/// Security → Accessibility) because posting keystrokes to *other* apps is a
/// privileged operation. It also requires the app to run outside the App
/// Sandbox — see `ClipboardManager.entitlements`.
@MainActor
enum PasteService {
    /// Virtual key code for the "V" key (`kVK_ANSI_V`).
    private static let vKeyCode: CGKeyCode = 0x09

    /// Whether the app is currently trusted for Accessibility.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility if it isn't already granted.
    /// Returns the current trust state. macOS shows its own dialog and deep
    /// links into System Settings; the grant takes effect without a relaunch.
    @discardableResult
    static func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() { return true }
        // Value of `kAXTrustedCheckOptionPrompt`, inlined because the global is
        // flagged as non-concurrency-safe under Swift 6 strict concurrency.
        let promptKey = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// Simulates ⌘V against the frontmost app. No-op (aside from prompting) if
    /// Accessibility hasn't been granted yet.
    static func pasteToFrontmostApp() {
        guard ensureAccessibilityPermission() else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
