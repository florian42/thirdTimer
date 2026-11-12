import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey. Uses the Carbon hotkey API, which needs no
/// accessibility permission.
@MainActor
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// The Carbon callback is a plain C function and cannot capture anything,
    /// so the action lives here. It is only ever touched on the main actor.
    private static var action: (@MainActor () -> Void)?

    /// Control-Option-T.
    init(action: @escaping @MainActor () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in HotKey.action?() }
                return noErr
            },
            1, &spec, nil, &handlerRef
        )
        let id = EventHotKeyID(signature: OSType(0x5454_4D52), id: 1) // "TTMR"
        RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(controlKey | optionKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}
