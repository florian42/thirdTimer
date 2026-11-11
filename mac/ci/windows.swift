// Lists the on-screen windows of ThirdTimer: "<id> <layer> <x> <y> <width> <height>".
// Layer 25 is the menu bar item; the panel window opened by --window is layer 3.
import CoreGraphics
import Foundation

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in list where (window[kCGWindowOwnerName as String] as? String) == "ThirdTimer" {
    let id = window[kCGWindowNumber as String] as? Int ?? 0
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let b = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    func n(_ key: String) -> Int { Int((b[key] as? Double) ?? Double((b[key] as? Int) ?? 0)) }
    print(id, layer, n("X"), n("Y"), n("Width"), n("Height"))
}
