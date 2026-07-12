import CoreGraphics
import Foundation

/// Posts synthetic keystrokes: backspaces to delete a typed trigger, and Unicode
/// characters to "type" the expansion. This deliberately avoids the pasteboard
/// so text expansion never disturbs the clipboard history this app manages.
enum KeyInjector {
    /// Marker written into each synthetic event so the expansion tap can ignore
    /// the app's own injected keystrokes (`'CLIP'`).
    static let sentinel: Int64 = 0x434C_4950

    private static let backspaceKey: CGKeyCode = 51
    private static let returnKey: CGKeyCode = 36
    private static let tabKey: CGKeyCode = 48

    static func deleteBackward(count: Int) {
        for _ in 0..<max(0, count) {
            postKeyCode(backspaceKey)
        }
    }

    static func type(_ text: String) {
        for character in text {
            switch character {
            case "\n", "\r": postKeyCode(returnKey)
            case "\t": postKeyCode(tabKey)
            default: postUnicode(character)
            }
        }
    }

    // MARK: - Private

    private static func postKeyCode(_ code: CGKeyCode) {
        post(virtualKey: code, unicode: nil)
    }

    private static func postUnicode(_ character: Character) {
        post(virtualKey: 0, unicode: Array(String(character).utf16))
    }

    private static func post(virtualKey: CGKeyCode, unicode: [UniChar]?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else { continue }
            if let unicode {
                event.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode)
            }
            event.setIntegerValueField(.eventSourceUserData, value: sentinel)
            event.post(tap: .cghidEventTap)
        }
    }
}
