import AppKit
import SwiftUI
import ThirdTimerCore

/// A scripted morning of use, for recording a demo video (`--walkthrough`).
/// It sends the same events a person would cause with the hotkey and the
/// panel, shows a caption for each step, and moves the clock forward quickly
/// where a real session would take an hour.
@MainActor
final class Walkthrough: ObservableObject {
    @Published var caption = ""
    @Published var keys = ""
    private var window: NSWindow?

    func start() {
        showCaptionWindow()
        Task { await run() }
    }

    private func run() async {
        let model = AppModel.shared
        let report = UUID()
        model.setClock(to: "09:00")

        await say("Nine o'clock. Third Timer lives in the menu bar. Add what you're working on.", 4)
        model.send(.addDeliverable(id: report, name: "Quarterly report"))
        await pause(2)
        await say("Start working.", 2, keys: "⌃⌥T")
        model.send(.startWork(deliverableID: report))
        await say("Work as long as you like. The ring fills toward a natural pause.", 3)

        await fastForward(60 * 60, label: "An hour later")
        await say("After an hour of unbroken work, a soft bell suggests a pause. It waits for a lull in your typing, and you can say not now.", 6, keys: "🔔")

        await say("Take the break. You've earned 20 minutes.", 3, keys: "⌃⌥T")
        model.send(.startBreak(seconds: nil))
        await pause(2)
        await say("Note where you left off…", 3)
        model.send(.recordCheckpoint("Intro done, section 2 half drafted"))
        await say("…and hand something to Claude, if you like.", 3)
        model.send(.recordHandoff("Claude: check the figures in section 3"))
        await say("Then step away from the screen.", 2)
        await fastForward(12 * 60, label: "12 minutes later")

        await say("Back early? The unused minutes stay banked, and your notes are waiting.", 4, keys: "⌃⌥T")
        model.send(.resumeWork(deliverableID: report))
        await pause(3)

        await fastForward(55 * 60, label: "55 minutes later")
        await say("Under pressure? Don't skip the break. Take just three minutes of it.", 4, keys: "3 min")
        model.send(.startBreak(seconds: 180))
        await pause(2)
        await fastForward(3 * 60 + 2, label: "Three minutes later")
        await say("Two soft strikes bring you back. The rest of the break is still yours.", 5, keys: "🔔 🔔")
        model.send(.resumeWork(deliverableID: report))
        await pause(2)

        await fastForward(49 * 60 + 30, label: "Toward noon")
        await say("At twelve it suggests lunch.", 5, keys: "🔔")
        model.send(.startLunch)
        await say("Lunch lasts as long as you set, whatever you had banked.", 4)
        await fastForward(60 * 60 + 2, label: "An hour later")
        await say("The bell rings, and the afternoon starts fresh.", 4, keys: "🔔 🔔")
        model.send(.resumeWork(deliverableID: report))
        await pause(2)

        await say("That's the rhythm: work, pause when it's natural, come back rested.", 6)
        caption = ""
        keys = ""
    }

    private func say(_ text: String, _ seconds: Double, keys: String = "") async {
        caption = text
        self.keys = keys
        await pause(seconds)
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    /// Runs the clock forward in small steps so the timers visibly spin.
    private func fastForward(_ seconds: TimeInterval, label: String) async {
        caption = "\(label)…"
        keys = "⏩"
        let steps = 50
        for _ in 0..<steps {
            AppModel.shared.advanceClock(by: seconds / Double(steps))
            try? await Task.sleep(for: .milliseconds(50))
        }
        await pause(1.2)
    }

    private func showCaptionWindow() {
        let host = NSHostingController(rootView: CaptionView(walkthrough: self))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.borderless]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.setFrame(NSRect(x: 40, y: 260, width: 420, height: 300), display: true)
        window.orderFront(nil)
        self.window = window
    }
}

private struct CaptionView: View {
    @ObservedObject var walkthrough: Walkthrough

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !walkthrough.keys.isEmpty {
                Text(walkthrough.keys)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
            }
            Text(walkthrough.caption)
                .font(.system(size: 24, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.white)
        .frame(width: 420, height: 300, alignment: .topLeading)
    }
}
