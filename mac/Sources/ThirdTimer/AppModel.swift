import AppKit
import AVFoundation
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
    /// Only the walkthrough and the demos move this, to show a day in a minute.
    private var clockOffset: TimeInterval = 0
    private let launchedAt = Date()
    /// A suggestion waiting for a quiet moment, and the latest it may wait until.
    private var pendingNudge: (nudge: Nudge, latest: Date)?
    /// Two players, so the second strike can start while the first still rings.
    private var bellPlayers: [AVAudioPlayer] = []

    let meetings = MeetingWatcher()
    private var secondsSinceCalendarCheck = 0
    let presence = PresenceWatcher()
    /// The last moment the app was seen running, to notice sleep and restarts.
    private var lastAlive = Date()
    private var secondsSinceAliveStamp = 0
    private var microphoneLogged = false
    /// Demos and checks run on a made-up clock, so the real calendar is left alone.
    private static let scripted = ["--demo", "--at", "--walkthrough", "--print-title"]
        .contains { CommandLine.arguments.contains($0) }

    var snapshot: Snapshot { engine.snapshot(state, now: now) }

    private init() {
        stateURL = AppModel.resolveStateURL()
        state = EngineState()
        if let time = AppModel.argument(after: "--at") {
            setClock(to: time)
        }
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
        noticeTimeNotRunning()
        send(.launch)
        if state.meetings.pauseEnabled { watchCalendar() }
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
        send(.tick)
        deliverNudgeWhenQuiet()
    }

    /// Sets the app's clock to a time of day today, such as "12:05". For demos.
    func setClock(to time: String) {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              let target = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
        else { return }
        clockOffset = target.timeIntervalSince(Date())
        now = currentTime()
    }

    /// Starts looking at the calendar. Called at launch and when the setting is turned on.
    func watchCalendar() {
        guard !AppModel.scripted, AppModel.canNotify, meetings.access == .unknown else { return }
        meetings.requestAccess()
    }

    private func checkCalendar() {
        guard !AppModel.scripted else { return }
        secondsSinceCalendarCheck += 1
        guard secondsSinceCalendarCheck >= 15 else { return }
        secondsSinceCalendarCheck = 0
        send(.meeting(state.meetings.pauseEnabled && meetings.inMeeting(at: Date())))
    }

    // MARK: Away from the Mac

    /// A gap this long between two looks at the clock means the Mac slept or the app was closed.
    private static let absenceSeconds = 120.0

    private var aliveURL: URL {
        stateURL.deletingLastPathComponent().appendingPathComponent("alive")
    }

    private func stampAlive() {
        guard !AppModel.scripted else { return }
        try? String(Date().timeIntervalSince1970).write(to: aliveURL, atomically: true, encoding: .utf8)
    }

    /// At launch: if the app was closed or the Mac was off while something ran,
    /// that time is neither work nor break.
    private func noticeTimeNotRunning() {
        guard !AppModel.scripted,
              let text = try? String(contentsOf: aliveURL, encoding: .utf8),
              let seconds = Double(text)
        else { return }
        let last = Date(timeIntervalSince1970: seconds)
        if Date().timeIntervalSince(last) > AppModel.absenceSeconds {
            send(.absence(since: last))
        }
    }

    private func checkPresence() {
        guard !AppModel.scripted else { return }
        let real = Date()
        if real.timeIntervalSince(lastAlive) > AppModel.absenceSeconds {
            // The Mac slept: the app did not run in between.
            send(.absence(since: lastAlive))
        }
        lastAlive = real
        let wasAway = state.presence.away
        send(.away(state.presence.pauseEnabled && presence.isAway(working: state.mode == .working)))
        if wasAway != state.presence.away {
            log.notice("\(self.state.presence.away ? "AWAY" : "BACK", privacy: .public) \(self.presence.report, privacy: .public)")
        }
        secondsSinceAliveStamp += 1
        if secondsSinceAliveStamp >= 30 {
            secondsSinceAliveStamp = 0
            stampAlive()
        }
    }

    private func tick() {
        checkPresence()
        checkCalendar()
        send(.tick)
        deliverNudgeWhenQuiet()
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
        case .nudge(let nudge):
            // Hold it for a quiet moment, but not for long.
            pendingNudge = (nudge, Date().addingTimeInterval(AppModel.longestNudgeWait))
            deliverNudgeWhenQuiet()
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

    // MARK: Suggestions and the bell

    /// A suggestion lands better at a natural pause than in the middle of a thought.
    private static let quietSeconds = 15.0
    private static let longestNudgeWait = 600.0
    /// During a call a suggestion waits this much longer, then comes anyway.
    private static let longestCallWait = 2700.0

    private func deliverNudgeWhenQuiet() {
        guard let pending = pendingNudge else { return }
        guard state.mode == .working, snapshot.suggestion != nil else {
            pendingNudge = nil
            return
        }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let scripted = CommandLine.arguments.contains("--walkthrough")
        if !AppModel.scripted, state.presence.quietOnCalls, let user = presence.microphoneUser,
           Date() < pending.latest.addingTimeInterval(AppModel.longestCallWait) {
            if !microphoneLogged {
                microphoneLogged = true
                log.notice("QUIET microphone in use by \(user, privacy: .public)")
            }
            return
        }
        microphoneLogged = false
        guard scripted || idle >= AppModel.quietSeconds || Date() >= pending.latest else { return }
        pendingNudge = nil
        ring(strikes: 1)
        let snap = snapshot
        switch pending.nudge {
        case .pause:
            notify(title: "A good moment to pause",
                   body: "You've earned \(Format.short(snap.bankSeconds)) of break.")
        case .lunch:
            notify(title: "Lunchtime", body: "A proper lunch sets up the afternoon.")
        }
    }

    /// Rings the soft bell. One strike suggests a break; two bring you back.
    private func ring(strikes: Int) {
        if CommandLine.arguments.contains("--print-title") || CommandLine.arguments.contains("--walkthrough") {
            print(String(format: "BELL %d %.1f", strikes, Date().timeIntervalSince(launchedAt)))
            fflush(stdout)
        }
        guard state.rhythm.bellEnabled else { return }
        if bellPlayers.isEmpty, let url = AppModel.bellURL {
            bellPlayers = (0..<2).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
        }
        guard let first = bellPlayers.first else {
            // No recording in the bundle: fall back to a quiet system sound.
            NSSound(named: "Tink")?.play()
            return
        }
        first.currentTime = 0
        first.play()
        if strikes > 1, bellPlayers.count > 1 {
            let second = bellPlayers[1]
            second.currentTime = 0
            second.play(atTime: second.deviceCurrentTime + AppModel.secondStrikeDelay)
        }
    }

    private static let secondStrikeDelay = 2.5

    /// The bell recording that the build script copies into the app bundle.
    private static var bellURL: URL? {
        for ext in ["m4a", "wav", "mp3", "aiff"] {
            if let url = Bundle.main.url(forResource: "bell", withExtension: ext) { return url }
        }
        return nil
    }

    private func notify(title: String, body: String) {
        guard AppModel.canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func fireAlarm() {
        alarmTimer?.invalidate()
        alarmTimer = nil
        alarmDate = nil
        // After sleep this runs before the next tick, so look around first.
        checkPresence()
        guard state.mode == .breaking else { return }
        guard !state.presence.away else {
            // Nobody is there to hear it.
            send(.alarmFired)
            return
        }
        if CommandLine.arguments.contains("--print-title") {
            print("ALARM: break time is up")
            fflush(stdout)
        }
        ring(strikes: 2)
        notify(title: state.currentBreak?.isMeal == true ? "Lunch is over" : "Break time is up",
               body: "Ready when you are.")
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
            stampAlive()
        } catch {
            log.error("Could not save state: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Demo state (for screenshots and checks)

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
        // A first stint of 75 minutes, a 15-minute break, then the current stint:
        // 40 minutes long, or 65 for the "nudge" demo so that a pause is suggested.
        let total: TimeInterval = (kind == "nudge" ? 155 : 130) * 60
        let start = currentTime().addingTimeInterval(-total)
        let report = UUID(), slides = UUID()
        func apply(_ event: Event, _ offset: TimeInterval) {
            s = engine.reduce(s, event, now: start.addingTimeInterval(offset)).0
        }
        apply(.addDeliverable(id: report, name: "Quarterly report"), 0)
        apply(.addDeliverable(id: slides, name: "Board slides"), 0)
        apply(.startWork(deliverableID: report), 0)
        apply(.startBreak(seconds: nil), 75 * 60)
        apply(.recordCheckpoint("Intro done, section 2 half drafted"), 76 * 60)
        apply(.recordHandoff("Claude: check the figures in section 3"), 76 * 60)
        apply(.resumeWork(deliverableID: report), 90 * 60)
        switch kind {
        case "ending":
            // A break whose time runs out four seconds after launch.
            apply(.startBreak(seconds: 64), total - 60)
        case "breaking":
            apply(.startBreak(seconds: nil), total - 4 * 60)
            apply(.recordCheckpoint("Section 3 drafted, tables missing"), total - 3 * 60)
        case "lunch":
            apply(.startLunch, total - 5 * 60)
        case "meeting":
            // The calendar showed a meeting 25 minutes ago.
            apply(.meeting(true), total - 25 * 60)
        case "away":
            // The screen was locked 25 minutes ago.
            apply(.away(true), total - 25 * 60)
        case "paused":
            // In a meeting for the last 25 minutes.
            apply(.pause, total - 25 * 60)
        default:
            // "working", "nudge" and "noon" differ only in the clock and the stint length.
            break
        }
    }

    /// Realistic worst-case data: long names, a one-letter name, long notes
    /// with a URL, and a stint left running overnight.
    private func seedWorstCase(_ s: inout EngineState) {
        let start = Date().addingTimeInterval(-30 * 3600)
        func apply(_ event: Event, _ offset: TimeInterval) {
            s = engine.reduce(s, event, now: start.addingTimeInterval(offset)).0
        }
        let long = UUID()
        apply(.addDeliverable(
            id: long,
            name: "Aleksandra Wiśniewska-Kowalczyk: Q3 board report for Northwind Industries Holdings (final, v12)"), 0)
        apply(.addDeliverable(id: UUID(), name: "X"), 0)
        apply(.addDeliverable(id: UUID(), name: "Tax filing"), 0)
        apply(.addDeliverable(id: UUID(), name: "Überprüfung der Lieferantenverträge für das Geschäftsjahr 2027"), 0)
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
