import AppKit
import CoreGraphics

/// Watches typed keystrokes system-wide and expands snippet triggers.
///
/// It installs a `CGEvent` keyboard tap (needs Accessibility), keeps a small
/// rolling buffer of recently typed characters, and when the buffer ends with a
/// known trigger it deletes the trigger and injects the expansion via
/// `KeyInjector` — no pasteboard involved.
@MainActor
final class TextExpansionService {
    struct Rule {
        let trigger: String
        let content: String
    }

    private var rules: [Rule] = []
    private var buffer = ""
    private var maxBuffer = 64

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isExpanding = false

    /// Replaces the active expansion rules (call whenever snippets change).
    func setRules(_ rules: [Rule]) {
        self.rules = rules.filter { !$0.trigger.isEmpty }
        let longest = self.rules.map(\.trigger.count).max() ?? 0
        maxBuffer = max(64, longest + 1)
    }

    /// Installs the keyboard tap. Returns false if Accessibility isn't granted.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard PasteService.ensureAccessibilityPermission() else { return false }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: expansionTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    /// Re-enables the tap if the system disabled it (timeout / heavy input).
    func reenable() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    // MARK: - Keystroke handling

    /// Handles one observed keystroke, already decoded to plain values so nothing
    /// non-`Sendable` crosses into the main actor from the C tap callback.
    fileprivate func handleKey(sentinel: Int64, keyCode: Int64, typed: String) {
        // Ignore our own injected keystrokes and anything typed mid-expansion.
        guard sentinel != KeyInjector.sentinel, !isExpanding else { return }

        // Backspace edits the buffer.
        if keyCode == 51 {
            if !buffer.isEmpty { buffer.removeLast() }
            return
        }

        guard !typed.isEmpty else { return }

        // Whitespace / newline is a word boundary — reset so triggers only match
        // contiguous input.
        if typed.allSatisfy(\.isWhitespace) {
            buffer = ""
            return
        }

        buffer.append(typed)
        if buffer.count > maxBuffer {
            buffer = String(buffer.suffix(maxBuffer))
        }
        checkForTrigger()
    }

    private func checkForTrigger() {
        guard let rule = rules.first(where: { buffer.hasSuffix($0.trigger) }) else { return }
        buffer = ""
        expand(rule)
    }

    private func expand(_ rule: Rule) {
        isExpanding = true
        let output = SnippetVariables.expand(rule.content)
        let triggerLength = rule.trigger.count

        // Let the final trigger keystroke land in the target app first, then
        // delete the trigger and type the expansion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            KeyInjector.deleteBackward(count: triggerLength)
            KeyInjector.type(output)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.isExpanding = false
            }
        }
    }
}

/// C tap callback. The run-loop source lives on the main run loop, so this fires
/// on the main thread; it decodes `refcon` back to the service and dispatches.
private func expansionTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<TextExpansionService>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .keyDown:
        // Decode to Sendable values here (in the C callback) before hopping to
        // the main actor — CGEvent itself isn't Sendable.
        let sentinel = event.getIntegerValueField(.eventSourceUserData)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        let typed = length > 0 ? String(utf16CodeUnits: chars, count: length) : ""
        MainActor.assumeIsolated {
            service.handleKey(sentinel: sentinel, keyCode: keyCode, typed: typed)
        }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { service.reenable() }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
