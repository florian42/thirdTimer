// swift-tools-version:5.9
import PackageDescription

// Complete data-race checking in every target.
let strict: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

var targets: [Target] = [
    // The session engine: every rule of the method, no clock, disk or system access.
    .target(name: "ThirdTimerCore", swiftSettings: strict),
    .testTarget(name: "ThirdTimerCoreTests", dependencies: ["ThirdTimerCore"], swiftSettings: strict),
]

#if os(macOS)
// The Mac shell: menu bar item, panel, hotkey, alarm. Only builds on a Mac.
targets.append(.executableTarget(name: "ThirdTimer", dependencies: ["ThirdTimerCore"], swiftSettings: strict))
#endif

let package = Package(
    name: "ThirdTimer",
    platforms: [.macOS(.v13)],
    targets: targets
)
