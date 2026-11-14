import AppKit
import CoreAudio
import CoreGraphics
import IOKit.pwr_mgt

/// Tells whether the user is at the Mac, and whether a call is running.
/// Everything is read on demand; nothing is recorded.
@MainActor
final class PresenceWatcher {
    /// Work with no key press or mouse movement for this long counts as having left.
    static let idleSeconds = 600.0
    private var idle = false

    /// True while the user is not at the Mac: the screen is locked, another user
    /// is logged in at the screen, the display is off, or a stint of work has
    /// seen no input for a while.
    func isAway(working: Bool) -> Bool {
        let sinceInput = secondsSinceInput
        if idle {
            // Back at the first touch.
            if sinceInput < 30 { idle = false }
        } else if working, sinceInput >= PresenceWatcher.idleSeconds, !displayKeptAwake {
            idle = true
        }
        return idle || screenLocked || displayAsleep
    }

    var secondsSinceInput: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    var screenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if session["CGSSessionScreenIsLocked"] as? Bool == true { return true }
        // After fast user switching this session is no longer the one on screen.
        if let onScreen = session["kCGSSessionOnConsoleKey"] as? Bool, !onScreen { return true }
        return false
    }

    var displayAsleep: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// A film or a video call keeps the display awake. Watching one is not being away.
    var displayKeptAwake: Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let counts = status?.takeRetainedValue() as? [String: Int]
        else { return false }
        return (counts["PreventUserIdleDisplaySleep"] ?? 0) > 0 || (counts["NoDisplaySleepAssertion"] ?? 0) > 0
    }

    /// The name of a program that is recording from a microphone right now, as
    /// in a call, or nil. Needs macOS 14; earlier versions always say nil.
    var microphoneUser: String? {
        guard #available(macOS 14.0, *) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return nil }
        for process in processes {
            var recording: UInt32 = 0
            var flagSize = UInt32(MemoryLayout<UInt32>.size)
            address.mSelector = kAudioProcessPropertyIsRunningInput
            guard AudioObjectGetPropertyData(process, &address, 0, nil, &flagSize, &recording) == noErr,
                  recording != 0
            else { continue }
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            address.mSelector = kAudioProcessPropertyBundleID
            let status = AudioObjectGetPropertyData(process, &address, 0, nil, &nameSize, &name)
            let bundleID = status == noErr ? (name?.takeRetainedValue() as String?) ?? "" : ""
            // Listening for "Hey Siri" or dictation is not a call.
            let system = ["com.apple.corespeech", "com.apple.assistant", "com.apple.siri", "com.apple.speech"]
            if system.contains(where: { bundleID.lowercased().hasPrefix($0) }) { continue }
            return bundleID.isEmpty ? "unknown" : bundleID
        }
        return nil
    }

    /// One line with every reading, for the log and for checks.
    var report: String {
        "PRESENCE locked \(screenLocked) displayAsleep \(displayAsleep) keptAwake \(displayKeptAwake) "
            + "microphone \(microphoneUser ?? "free") input \(Int(secondsSinceInput))s"
    }
}
