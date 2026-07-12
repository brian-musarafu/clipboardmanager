import AppKit
import Carbon.HIToolbox

/// Registry of hotkey actions, keyed by the id we assign each registration.
/// File-global (and main-actor isolated) because the Carbon C callback can't
/// capture Swift context — it looks actions up here by id.
@MainActor
private var hotKeyActions: [UInt32: () -> Void] = [:]

/// Registers system-wide keyboard shortcuts using the Carbon Hot Key API.
///
/// This is the native way to get a *global* shortcut (one that fires regardless
/// of which app is frontmost) without the Accessibility permission that
/// event-tap monitoring would require. Modern SwiftUI has no equivalent, so we
/// drop down to Carbon here.
@MainActor
final class HotKeyManager {
    /// Carbon modifier masks, exposed for callers.
    static let command = UInt32(cmdKey)
    static let shift = UInt32(shiftKey)
    static let option = UInt32(optionKey)
    static let control = UInt32(controlKey)

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    private var handlerInstalled = false

    /// Registers a global shortcut. `keyCode` is a `kVK_ANSI_*` virtual key code;
    /// `modifiers` is an OR of the masks above.
    func register(keyCode: Int, modifiers: UInt32, action: @escaping () -> Void) {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1
        hotKeyActions[id] = action

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CLIP"), id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr {
            hotKeyRefs.append(ref)
        } else {
            NSLog("HotKeyManager: failed to register hotkey (status \(status))")
            hotKeyActions[id] = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, nil)
    }
}

/// C callback invoked by Carbon when any registered hotkey is pressed. Runs on
/// the main run loop; it decodes the hotkey id and dispatches to the stored
/// action on the main actor.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let id = hotKeyID.id
    Task { @MainActor in
        hotKeyActions[id]?()
    }
    return noErr
}

/// Packs a 4-character string into an `OSType`/`FourCharCode`.
private func fourCharCode(_ string: String) -> FourCharCode {
    var code: FourCharCode = 0
    for scalar in string.unicodeScalars.prefix(4) {
        code = (code << 8) + FourCharCode(scalar.value & 0xFF)
    }
    return code
}
