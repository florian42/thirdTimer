import CoreGraphics
import Foundation

// Presses Control-Option-T the way a keyboard would, to check the global hotkey.
let source = CGEventSource(stateID: .hidSystemState)
for down in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: 17, keyDown: down)!
    event.flags = [.maskControl, .maskAlternate]
    event.post(tap: .cghidEventTap)
    usleep(100_000)
}
print("pressed Control-Option-T")
