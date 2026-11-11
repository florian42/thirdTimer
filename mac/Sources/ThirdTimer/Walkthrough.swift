import AppKit
import SwiftUI
import ThirdTimerCore

/// A scripted day of use, for recording a demo video (`--walkthrough`).
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
        let due = Calendar.current.date(
            bySettingHour: 17, minute: 0, second: 0, of: Date().addingTimeInterval(3 * 86400)) ?? Date()

        await say("Third Timer lives in the menu bar. Start by adding what you have to deliver, and when.", 4)
        model.send(.addDeliverable(id: report, name: "Quarterly report", deadline: due))
        await say("It now shows how much work time is left before the deadline, with breaks already budgeted.", 5)

        await say("Start working.", 2, keys: "⌃⌥T")
        model.send(.startWork(deliverableID: report))
        await pause(2)

        await say("Work for as long as you like. Every minute earns a third of a minute of break.", 2)
        await fastForward(50 * 60, label: "50 minutes later")

        await say("Ready for a pause? You have earned 16 minutes.", 3, keys: "⌃⌥T")
        model.send(.startBreak(seconds: nil))
        await pause(2)

        await say("Write one line on where you left off…", 3)
        model.send(.recordCheckpoint("Intro done, section 2 half drafted"))
        await say("…and hand something to Claude, so progress continues while you're away.", 3)
        model.send(.recordHandoff("Claude: check the figures in section 3"))
        await say("The break is budgeted: the work time left does not shrink while you rest.", 3)
        await fastForward(10 * 60, label: "10 minutes later")

        await say("Back early? The unused break time stays banked, and your notes are waiting.", 3, keys: "⌃⌥T")
        model.send(.resumeWork(deliverableID: report))
        await pause(4)

        await fastForward(75 * 60, label: "75 minutes of deep work later")
        await say("Under pressure? Don't skip the break. Take just 3 minutes of it.", 4, keys: "3 min")
        model.send(.startBreak(seconds: 180))
        await pause(2)
        await fastForward(3 * 60 + 4, label: "3 minutes later")
        await say("An alarm sounds when the time is up. The rest of your break is still banked.", 4)
        model.send(.resumeWork(deliverableID: report))
        await pause(2)

        await say("Crunch time? Tighten the ratio. Breaks get shorter, but they still happen.", 3, keys: "1/5")
        model.send(.setRatio(denominator: 5))
        await pause(3)
        await fastForward(60 * 60, label: "An hour later")

        await say("That's the loop: work, break in proportion, keep what you don't use.", 6)
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
        await pause(1)
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
