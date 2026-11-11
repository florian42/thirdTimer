// Lists the on-screen windows of ThirdTimer: "<id> <layer> <x> <y> <width> <height>".
// Layer 25 is the menu bar item; the panel window opened by --window is layer 3.
// Every window on screen is also written to stderr, to help when none match.
import CoreGraphics
import Foundation

let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
let list = (raw as NSArray?) as? [[String: Any]] ?? []
FileHandle.standardError.write("windows on screen: \(list.count)\n".data(using: .utf8)!)
for window in list {
    let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
    let id = (window[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
    let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
    let b = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    func n(_ key: String) -> Int { (b[key] as? NSNumber)?.intValue ?? 0 }
    let line = "\(id) \(layer) \(n("X")) \(n("Y")) \(n("Width")) \(n("Height"))"
    FileHandle.standardError.write("  \(owner): \(line)\n".data(using: .utf8)!)
    if owner.contains("ThirdTimer") { print(line) }
}
