import AppKit
import Foundation
import os
import ServiceManagement
import ThirdTimerCore
import UserNotifications

/// Connects the session engine to the Mac: sends it events with the current
/// time, shows its state, and carries out its effects. No rules live here.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var state: EngineState
    @Published private(set) var now = Date()
    @Published var loadProblem: String?

    let engine = Engine(calendar: .current)
    private let log = Logger(subsystem: "app.thirdtimer.ThirdTimer", category: "app")
    private let stateURL: URL
    private var ticker: Timer?
    private var alarmTimer: Timer?
    private var alarmDate: Date?
    /// Only the walkthrough moves this, to show hours of use in a minute.
    private var clockOffset: TimeInterval = 0

    var snapshot: Snapshot { engine.snapshot(state, now: now) }

    private init() {
        stateURL = AppModel.resolveStateURL()
        state = EngineState()
        load()
        if let demo = AppModel.argument(after: "--demo") {
            seedDemo(demo)
        }
        if CommandLine.arguments.contains("--walkthrough") {
            state = EngineState()
            save()
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        send(.launch)
    }

    private func currentTime() -> Date {
        Date().addingTimeInterval(clockOffset)
    }

    /// Moves the app's clock forward. Used by the walkthrough only.
    func advanceClock(by seconds: TimeInterval) {
        clockOffset += seconds
        now = currentTime()
        if let alarmDate, alarmDate <= now {
            fireAlarm()
        }
    }

    private func tick() {
        now = currentTime()
        // `--print-title` writes the menu bar text once a second, for checks.
        if CommandLine.arguments.contains("--print-title") {
            print(snapshot.menuTitle)
            fflush(stdout)
        }
    }

    // MARK: Events

    func send(_ event: Event) {
        let time = currentTime()
        let (next, effects) = engine.reduce(state, event, now: time)
        state = next
        now = time
        effects.forEach(perform)
    }

    /// The global hotkey: start, break, resume, in that order.
    func toggle() {
        switch state.mode {
        case .idle:
            send(.startWork(deliverableID: snapshot.preselectedDeliverableID))
        case .working:
            send(.startBreak(seconds: nil))
        case .breaking:
            send(.resumeWork(deliverableID: state.currentBreak?.deliverableID))
        }
    }

    func copyCheckpointLog(for id: UUID) {
        let text = engine.checkpointLog(state, deliverableID: id)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Effects

    private func perform(_ effect: Effect) {
        switch effect {
        case .scheduleAlarm(let date):
            alarmTimer?.invalidate()
            alarmDate = date
            let fireAt = Date().addingTimeInterval(date.timeIntervalSince(currentTime()))
            let timer = Timer(fire: fireAt, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.fireAlarm() }
            }
            RunLoop.main.add(timer, forMode: .common)
            alarmTimer = timer
        case .cancelAlarm:
            alarmTimer?.invalidate()
            alarmTimer = nil
            alarmDate = nil
        case .askCheckpoint, .askHandoff, .showReturn:
            // The panel shows these from the snapshot.
            break
        case .setLaunchAtLogin(let on):
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                log.error("Could not change start at login: \(error.localizedDescription, privacy: .public)")
            }
        case .save:
            save()
        }
    }

    private func fireAlarm() {
        alarmTimer?.invalidate()
        alarmTimer = nil
        alarmDate = nil
        guard state.mode == .breaking else { return }
        NSSound(named: "Glass")?.play()
        if CommandLine.arguments.contains("--print-title") {
            print("ALARM: break time is up")
            fflush(stdout)
        }
        if AppModel.canNotify {
            let content = UNMutableNotificationContent()
            content.title = "Break time is up"
            content.body = "Your break has run its length."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "break-end", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        send(.alarmFired)
    }

    static var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    func requestNotificationPermission() {
        guard AppModel.canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: State file

    private static func resolveStateURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["THIRDTIMER_STATE_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ThirdTimer", isDirectory: true).appendingPathComponent("state.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        do {
            state = try Persistence.decode(data)
        } catch {
            // Keep the unreadable file so nothing is lost, and start fresh.
            let backup = stateURL.deletingLastPathComponent()
                .appendingPathComponent("state-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: stateURL, to: backup)
            log.error("Could not read saved state: \(String(describing: error), privacy: .public)")
            loadProblem = "The saved state could not be read. It was kept as \(backup.lastPathComponent)."
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Persistence.encode(state).write(to: stateURL, options: .atomic)
        } catch {
            log.error("Could not save state: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Demo state (for screenshots and checks: `--demo working`, `breaking` or `ending`)

    static func argument(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private func seedDemo(_ kind: String) {
        var s = EngineState()
        if kind == "worst" {
            seedWorstCase(&s)
        } else if kind != "idle" {
            seedSample(&s, kind: kind)
        }
        state = s
        save()
    }

    private func seedSample(_ s: inout EngineState, kind: String) {
        let start = Date().addingTimeInterval(-3 * 3600)
        let report = UUID(), slides = UUID()
        func apply(_ event: Event, _ offset: TimeInterval) {
            s = engine.reduce(s, event, now: start.addingTimeInterval(offset)).0
        }
        apply(.addDeliverable(id: report, name: "Quarterly report",
                              deadline: Date().addingTimeInterval(3 * 86400)), 0)
        apply(.addDeliverable(id: slides, name: "Board slides",
                              deadline: Date().addingTimeInterval(6 * 86400)), 0)
        apply(.startWork(deliverableID: report), 0)
        apply(.startBreak(seconds: nil), 75 * 60)
        apply(.recordCheckpoint("Intro done, section 2 half drafted"), 76 * 60)
        apply(.recordHandoff("Claude: check the figures in section 3"), 76 * 60)
        apply(.resumeWork(deliverableID: report), 90 * 60)
        if kind == "ending" {
            // A break whose time runs out four seconds after launch.
            apply(.startBreak(seconds: 64), 3 * 3600 - 60)
        }
        if kind == "breaking" {
            apply(.startBreak(seconds: nil), 3 * 3600 - 4 * 60)
            apply(.recordCheckpoint("Section 3 drafted, tables missing"), 3 * 3600 - 3 * 60)
        }
    }

    /// Realistic worst-case data: long names, a one-letter name, a deadline
    /// that has passed, long notes with a URL, and a stint left running overnight.
    private func seedWorstCase(_ s: inout EngineState) {
        let start = Date().addingTimeInterval(-30 * 3600)
        func apply(_ event: Event, _ offset: TimeInterval) {
            s = engine.reduce(s, event, now: start.addingTimeInterval(offset)).0
        }
        let long = UUID()
        apply(.addDeliverable(
            id: long,
            name: "Aleksandra Wiśniewska-Kowalczyk: Q3 board report for Northwind Industries Holdings (final, v12)",
            deadline: Date().addingTimeInterval(2 * 86400)), 0)
        apply(.addDeliverable(id: UUID(), name: "X", deadline: Date().addingTimeInterval(40 * 86400)), 0)
        apply(.addDeliverable(id: UUID(), name: "Tax filing", deadline: Date().addingTimeInterval(-86400)), 0)
        apply(.addDeliverable(id: UUID(), name: "Überprüfung der Lieferantenverträge für das Geschäftsjahr 2027",
                              deadline: Date().addingTimeInterval(9 * 86400)), 0)
        apply(.startWork(deliverableID: long), 0)
        apply(.startBreak(seconds: nil), 2 * 3600)
        apply(.recordCheckpoint(
            "Sections 1 to 4 drafted; figures in 3.2 still disagree with the finance export at "
            + "https://docs.northwind-industries-holdings.example.com/quarterly/2026/q3/board-report-final-v12"), 2 * 3600)
        apply(.recordHandoff(
            "Claude: reconcile every table in section 3 against the finance export and list each mismatch with its source row"),
            2 * 3600)
        apply(.resumeWork(deliverableID: long), 2 * 3600 + 600)
    }
}
