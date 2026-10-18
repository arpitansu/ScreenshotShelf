import Carbon
import Foundation

/// Called by the system when the shortcut is pressed (a plain C callback).
private func hotKeyHandler(_ next: EventHandlerCallRef?,
                           _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in HotKey.action?() }
    return noErr
}

/// A system-wide keyboard shortcut. Uses the Carbon hot-key API,
/// which needs no Accessibility permission.
@MainActor
final class HotKey {
    static var action: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Default: Control + Command + V
    init(keyCode: UInt32 = UInt32(kVK_ANSI_V),
         modifiers: UInt32 = UInt32(controlKey | cmdKey),
         action: @escaping () -> Void) {
        HotKey.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x5348_4C46), id: 1) // "SHLF"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
