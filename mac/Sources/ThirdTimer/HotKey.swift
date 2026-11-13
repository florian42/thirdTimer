import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey. Uses the Carbon hotkey API, which needs no
/// accessibility permission.
@MainActor
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// The result of setting the hotkey up, for the log.
    private(set) var status = ""
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
        // The dispatcher target also receives hotkeys while the app is in the
        // background with no window, which is how a menu bar app spends its life.
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in HotKey.action?() }
                return noErr
            },
            1, &spec, nil, &handlerRef
        )
        let id = EventHotKeyID(signature: OSType(0x5454_4D52), id: 1) // "TTMR"
        let registered = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            UInt32(controlKey | optionKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        // 0 means it worked; -9878 means another app already holds the combination.
        status = "HOTKEY handler \(installed) register \(registered)"
    }
}
