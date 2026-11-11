import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey. Uses the Carbon hotkey API, which needs no
/// accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var action: (() -> Void)?

    /// Control-Option-T.
    init(action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async { HotKey.action?() }
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

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
