import Foundation

/// The session engine. Every rule of the method lives here.
/// It never reads the clock: the current time is always passed in.
public struct Engine: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public static let allowedDenominators = [2, 3, 4, 5, 6]
    /// Longest deliverable name, and longest checkpoint or hand-off note, in characters.
    public static let nameLimit = 120
    public static let noteLimit = 280
    /// Longest deliverable name shown in the menu bar before it is cut short.
    public static let menuNameLimit = 24

    // MARK: - Reduce

    public func reduce(_ state: EngineState, _ event: Event, now: Date) -> (EngineState, [Effect]) {
        var s = state
        var effects: [Effect] = []

        switch event {
        case .launch:
            if s.mode == .breaking, let b = s.currentBreak, !b.alarmFired {
                effects.append(.scheduleAlarm(at: b.start.addingTimeInterval(b.allowanceSeconds)))
            }
            return (s, effects)

        case .tick:
            guard case .working(let stint) = s.session else { return (state, []) }
            let rhythm = s.rhythm
            var log = s.nudgeLog
            let elapsed = now.timeIntervalSince(stint.start)
            if lunchIsDue(s, now: now), log.lunchSuggestedOn != calendar.startOfDay(for: now) {
                log.lunchSuggestedOn = calendar.startOfDay(for: now)
                // Lunch replaces a pause suggestion that would fall at the same moment.
                log.nudgesThisStint = max(log.nudgesThisStint, nudgesDue(rhythm, elapsed: elapsed, now: now))
                effects.append(.nudge(.lunch))
            } else if rhythm.nudgeEnabled {
                let due = nudgesDue(rhythm, elapsed: elapsed, now: now)
                if due > log.nudgesThisStint {
                    // After a long gap (the Mac was asleep) only one suggestion is made.
                    log.nudgesThisStint = due
                    effects.append(.nudge(.pause))
                }
            }
            s.nudgeLog = log

        case .startWork(let deliverableID):
            guard s.mode == .idle else { return (state, []) }
            beginStint(&s, deliverableID: deliverableID, handoff: nil, now: now, effects: &effects)

        case .startBreak, .startLunch:
            guard s.mode == .working, let stint = s.stint else { return (state, []) }
            s.bankSeconds += accrued(stint, ratio: s.ratio, now: now)
            s.workLog.append(WorkEntry(start: stint.start, end: now, deliverableID: stint.deliverableID))
            let allowance: Double
            let isMeal: Bool
            switch event {
            case .startBreak(let seconds):
                allowance = min(max(0, seconds ?? s.bankSeconds), s.bankSeconds)
                isMeal = false
            default:
                // Lunch lasts as long as you set, however much was banked.
                allowance = Double(s.rhythm.lunchLengthMinutes) * 60
                isMeal = true
                var log = s.nudgeLog
                log.lunchTakenOn = calendar.startOfDay(for: now)
                s.nudgeLog = log
            }
            s.returnInfo = nil
            s.session = .breaking(BreakSession(
                start: now,
                allowanceSeconds: allowance,
                deliverableID: stint.deliverableID,
                checkpoint: nil,
                handoff: nil,
                alarmFired: false,
                isMeal: isMeal
            ))
            effects.append(.scheduleAlarm(at: now.addingTimeInterval(allowance)))
            effects.append(.askCheckpoint)
            if s.settings.handoffPrompt { effects.append(.askHandoff) }

        case .recordCheckpoint(let raw):
            guard s.mode == .breaking, var b = s.currentBreak else { return (state, []) }
            let text = oneLine(raw, limit: Engine.noteLimit)
            guard !text.isEmpty else { return (state, []) }
            if b.checkpoint != nil, !s.checkpoints.isEmpty {
                // A second checkpoint in the same break replaces the first.
                s.checkpoints[s.checkpoints.count - 1].text = text
            } else {
                s.checkpoints.append(Checkpoint(time: now, text: text, deliverableID: b.deliverableID))
            }
            b.checkpoint = text
            s.session = .breaking(b)

        case .recordHandoff(let raw):
            guard s.mode == .breaking, var b = s.currentBreak else { return (state, []) }
            let text = oneLine(raw, limit: Engine.noteLimit)
            guard !text.isEmpty else { return (state, []) }
            b.handoff = text
            s.session = .breaking(b)

        case .resumeWork(let deliverableID):
            guard s.mode == .breaking, let b = s.currentBreak else { return (state, []) }
            let taken = max(0, now.timeIntervalSince(b.start))
            // Debit card, not credit card: the bank never goes below zero.
            // Lunch uses up what was banked, so the afternoon starts fresh.
            s.bankSeconds = b.isMeal == true ? 0 : max(0, s.bankSeconds - taken)
            s.breakLog.append(BreakEntry(start: b.start, end: now))
            effects.append(.cancelAlarm)
            beginStint(&s, deliverableID: deliverableID, handoff: b.handoff, now: now, effects: &effects)

        case .alarmFired:
            guard s.mode == .breaking, var b = s.currentBreak, !b.alarmFired else { return (state, []) }
            b.alarmFired = true
            s.session = .breaking(b)

        case .setRatio(let denominator):
            guard Engine.allowedDenominators.contains(denominator), denominator != s.ratioDenominator else {
                return (state, [])
            }
            if var stint = s.stint {
                // Close the earning at the old ratio; the new ratio applies from now on.
                stint.earnedSeconds = accrued(stint, ratio: s.ratio, now: now)
                stint.earnAnchor = now
                s.session = .working(stint)
            }
            s.ratioDenominator = denominator

        case .addDeliverable(let id, let rawName):
            let name = oneLine(rawName, limit: Engine.nameLimit)
            guard !name.isEmpty, !s.deliverables.contains(where: { $0.id == id }) else { return (state, []) }
            s.deliverables.append(Deliverable(id: id, name: name, isDone: false, completedAt: nil))

        case .renameDeliverable(let id, let rawName):
            let name = oneLine(rawName, limit: Engine.nameLimit)
            guard !name.isEmpty, let index = s.deliverables.firstIndex(where: { $0.id == id }) else {
                return (state, [])
            }
            s.deliverables[index].name = name

        case .completeDeliverable(let id):
            guard let index = s.deliverables.firstIndex(where: { $0.id == id }), !s.deliverables[index].isDone else {
                return (state, [])
            }
            s.deliverables[index].isDone = true
            s.deliverables[index].completedAt = now

        case .dismissSuggestion:
            guard case .working(let stint) = s.session else { return (state, []) }
            var log = s.nudgeLog
            if lunchIsDue(s, now: now) {
                log.lunchDismissedOn = calendar.startOfDay(for: now)
            } else {
                log.dismissedNudges = max(1, nudgesDue(s.rhythm, elapsed: now.timeIntervalSince(stint.start), now: now))
            }
            s.nudgeLog = log

        case .setRhythm(let rhythm):
            var r = rhythm
            r.firstNudgeMinutes = min(max(r.firstNudgeMinutes, 15), 180)
            r.repeatNudgeMinutes = min(max(r.repeatNudgeMinutes, 10), 120)
            r.lunchMinuteOfDay = min(max(r.lunchMinuteOfDay, 0), 24 * 60 - 1)
            r.lunchLengthMinutes = min(max(r.lunchLengthMinutes, 15), 180)
            r.dipStartMinute = min(max(r.dipStartMinute, 0), 24 * 60 - 1)
            r.dipEndMinute = min(max(r.dipEndMinute, r.dipStartMinute), 24 * 60)
            r.dipNudgeMinutes = min(max(r.dipNudgeMinutes, 15), 180)
            s.rhythm = r

        case .setHandoffPrompt(let on):
            s.settings.handoffPrompt = on

        case .setLaunchAtLogin(let on):
            s.settings.launchAtLogin = on
            effects.append(.setLaunchAtLogin(on))

        case .resetSession:
            // Time already worked or rested stays on the record; only the session is cleared.
            if let stint = s.stint {
                s.workLog.append(WorkEntry(start: stint.start, end: now, deliverableID: stint.deliverableID))
            }
            if let b = s.currentBreak {
                s.breakLog.append(BreakEntry(start: b.start, end: now))
                effects.append(.cancelAlarm)
            }
            s.session = .idle
            s.bankSeconds = 0
            s.returnInfo = nil
        }

        if s != state { effects.append(.save) }
        return (s, effects)
    }

    private func beginStint(
        _ s: inout EngineState,
        deliverableID: UUID?,
        handoff: String?,
        now: Date,
        effects: inout [Effect]
    ) {
        let id = deliverableID.flatMap { id in s.deliverables.contains(where: { $0.id == id }) ? id : nil }
        s.session = .working(Stint(start: now, deliverableID: id, earnedSeconds: 0, earnAnchor: now))
        var log = s.nudgeLog
        log.nudgesThisStint = 0
        log.dismissedNudges = 0
        s.nudgeLog = log
        if let id { s.lastDeliverableID = id }
        let lastCheckpoint = s.checkpoints.last(where: { $0.deliverableID == id })?.text
        if lastCheckpoint != nil || handoff != nil {
            let info = ReturnInfo(checkpoint: lastCheckpoint, handoff: handoff)
            s.returnInfo = info
            effects.append(.showReturn(info))
        } else {
            s.returnInfo = nil
        }
    }

    /// How many pause suggestions should have been made after this much unbroken work.
    /// During the afternoon dip the first one comes sooner.
    private func nudgesDue(_ rhythm: Rhythm, elapsed: Double, now: Date) -> Int {
        var firstMinutes = rhythm.firstNudgeMinutes
        if rhythm.dipEnabled, minuteOfDay(now) >= Double(rhythm.dipStartMinute),
           minuteOfDay(now) < Double(rhythm.dipEndMinute) {
            firstMinutes = min(firstMinutes, rhythm.dipNudgeMinutes)
        }
        let first = Double(firstMinutes) * 60
        guard elapsed >= first else { return 0 }
        return 1 + Int((elapsed - first) / (Double(rhythm.repeatNudgeMinutes) * 60))
    }

    private func minuteOfDay(_ date: Date) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for: date)) / 60
    }

    /// A walk does the most good around the afternoon dip.
    private func movementSuggested(_ state: EngineState, now: Date) -> Bool {
        let rhythm = state.rhythm
        guard rhythm.dipEnabled, state.mode == .breaking else { return false }
        let minute = minuteOfDay(now)
        return minute >= Double(rhythm.dipStartMinute)
            && minute < Double(rhythm.dipEndMinute + Rhythm.movementTailMinutes)
    }

    /// Lunch is suggested while working, from lunchtime for a while after, until lunch is taken.
    private func lunchIsDue(_ state: EngineState, now: Date) -> Bool {
        let rhythm = state.rhythm
        guard rhythm.lunchEnabled, state.mode == .working else { return false }
        let day = calendar.startOfDay(for: now)
        guard state.nudgeLog.lunchTakenOn != day, state.nudgeLog.lunchDismissedOn != day else { return false }
        let minutes = minuteOfDay(now)
        let start = Double(rhythm.lunchMinuteOfDay)
        return minutes >= start && minutes < start + Double(Rhythm.lunchWindowMinutes)
    }

    private func accrued(_ stint: Stint, ratio: Double, now: Date) -> Double {
        stint.earnedSeconds + max(0, now.timeIntervalSince(stint.earnAnchor)) * ratio
    }

    private func oneLine(_ text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: { $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(line.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Snapshot

    public func snapshot(_ state: EngineState, now: Date) -> Snapshot {
        let liveBank = self.liveBank(state, now: now)
        var elapsed = 0.0
        var remaining: Double?
        var currentID: UUID?

        switch state.mode {
        case .idle:
            break
        case .working:
            if let stint = state.stint {
                elapsed = max(0, now.timeIntervalSince(stint.start))
                currentID = stint.deliverableID
            }
        case .breaking:
            if let b = state.currentBreak {
                elapsed = max(0, now.timeIntervalSince(b.start))
                remaining = b.allowanceSeconds - elapsed
                currentID = b.deliverableID
            }
        }

        let currentName = currentID.flatMap { id in state.deliverables.first(where: { $0.id == id })?.name }

        let title: String
        switch state.mode {
        case .idle:
            title = "Idle"
        case .working:
            title = "\(menuName(currentName)) · \(Format.short(elapsed))"
        case .breaking:
            let r = remaining ?? 0
            title = r >= 0 ? "Break · \(Format.clock(r)) left" : "Break · \(Format.clock(-r)) past"
        }

        let views = state.deliverables.map { d in
            DeliverableView(
                id: d.id,
                name: d.name,
                isDone: d.isDone,
                investedSeconds: invested(state, deliverableID: d.id, now: now),
                checkpoints: state.checkpoints.filter { $0.deliverableID == d.id }
            )
        }

        let dayStart = calendar.startOfDay(for: now)
        var todayWork = state.workLog.reduce(0.0) { $0 + overlap($1.start, $1.end, dayStart, now) }
        var todayBreak = state.breakLog.reduce(0.0) { $0 + overlap($1.start, $1.end, dayStart, now) }
        if let stint = state.stint { todayWork += overlap(stint.start, now, dayStart, now) }
        if let b = state.currentBreak { todayBreak += overlap(b.start, now, dayStart, now) }

        let preselected = state.lastDeliverableID.flatMap { id in
            state.deliverables.contains(where: { $0.id == id && !$0.isDone }) ? id : nil
        }

        return Snapshot(
            mode: state.mode,
            menuTitle: title,
            elapsedSeconds: elapsed,
            breakRemainingSeconds: remaining,
            bankSeconds: liveBank,
            ratioDenominator: state.ratioDenominator,
            currentDeliverableID: currentID,
            currentDeliverableName: currentName,
            activeDeliverables: views.filter { !$0.isDone },
            doneDeliverables: views.filter { $0.isDone },
            todayWorkSeconds: todayWork,
            todayBreakSeconds: todayBreak,
            preselectedDeliverableID: preselected,
            returnInfo: state.returnInfo,
            awaitingCheckpoint: state.mode == .breaking && state.currentBreak?.checkpoint == nil,
            awaitingHandoff: state.mode == .breaking && state.settings.handoffPrompt
                && state.currentBreak?.handoff == nil,
            suggestion: suggestion(state, elapsed: elapsed, now: now),
            isLunchBreak: state.currentBreak?.isMeal == true,
            movementSuggested: movementSuggested(state, now: now),
            pauseAfterSeconds: pauseAfter(state, now: now),
            partialBreakOptions: state.mode == .working
                ? Engine.partialBreakLengths.filter { $0 < liveBank } : []
        )
    }

    /// The menu bar has little room: a long name is cut short so the timer stays visible.
    private func menuName(_ name: String?) -> String {
        guard let name else { return "Working" }
        guard name.count > Engine.menuNameLimit else { return name }
        return String(name.prefix(Engine.menuNameLimit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// What the app would suggest right now, if anything.
    private func suggestion(_ state: EngineState, elapsed: Double, now: Date) -> Nudge? {
        guard state.mode == .working else { return nil }
        if lunchIsDue(state, now: now) { return .lunch }
        let rhythm = state.rhythm
        let due = nudgesDue(rhythm, elapsed: elapsed, now: now)
        if rhythm.nudgeEnabled, due > 0, due > state.nudgeLog.dismissedNudges { return .pause }
        return nil
    }

    /// How much unbroken work leads to the first pause suggestion right now, if any.
    private func pauseAfter(_ state: EngineState, now: Date) -> Double? {
        let rhythm = state.rhythm
        guard rhythm.nudgeEnabled else { return nil }
        var minutes = rhythm.firstNudgeMinutes
        if rhythm.dipEnabled, minuteOfDay(now) >= Double(rhythm.dipStartMinute),
           minuteOfDay(now) < Double(rhythm.dipEndMinute) {
            minutes = min(minutes, rhythm.dipNudgeMinutes)
        }
        return Double(minutes) * 60
    }

    public static let partialBreakLengths: [Double] = [180, 300, 600]

    /// The checkpoints of a deliverable as text, oldest first, ready to paste.
    public func checkpointLog(_ state: EngineState, deliverableID: UUID?) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return state.checkpoints
            .filter { $0.deliverableID == deliverableID }
            .map { "\(formatter.string(from: $0.time))  \($0.text)" }
            .joined(separator: "\n")
    }

    /// Break time available right now: growing while working, shrinking while on a break.
    private func liveBank(_ state: EngineState, now: Date) -> Double {
        switch state.mode {
        case .idle:
            return state.bankSeconds
        case .working:
            guard let stint = state.stint else { return state.bankSeconds }
            return state.bankSeconds + accrued(stint, ratio: state.ratio, now: now)
        case .breaking:
            guard let b = state.currentBreak else { return state.bankSeconds }
            return max(0, state.bankSeconds - max(0, now.timeIntervalSince(b.start)))
        }
    }

    private func invested(_ state: EngineState, deliverableID: UUID, now: Date) -> Double {
        var total = state.workLog
            .filter { $0.deliverableID == deliverableID }
            .reduce(0.0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) }
        if let stint = state.stint, stint.deliverableID == deliverableID {
            total += max(0, now.timeIntervalSince(stint.start))
        }
        return total
    }

    private func overlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Double {
        max(0, min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart)))
    }
}

// MARK: - What the user sees

public struct DeliverableView: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isDone: Bool
    public var investedSeconds: Double
    public var checkpoints: [Checkpoint]
}

public struct Snapshot: Equatable, Sendable {
    public var mode: Mode
    public var menuTitle: String
    /// Time in the current stint or break.
    public var elapsedSeconds: Double
    /// Only on a break. Negative once the break has run past its end.
    public var breakRemainingSeconds: Double?
    public var bankSeconds: Double
    public var ratioDenominator: Int
    public var currentDeliverableID: UUID?
    public var currentDeliverableName: String?
    public var activeDeliverables: [DeliverableView]
    public var doneDeliverables: [DeliverableView]
    public var todayWorkSeconds: Double
    public var todayBreakSeconds: Double
    public var preselectedDeliverableID: UUID?
    public var returnInfo: ReturnInfo?
    public var awaitingCheckpoint: Bool
    public var awaitingHandoff: Bool
    /// Set while a break would be a good idea; the panel and menu bar show it calmly.
    public var suggestion: Nudge?
    public var isLunchBreak: Bool
    /// On a break around the afternoon dip, when a walk helps most.
    public var movementSuggested: Bool
    /// Unbroken work after which a pause is first suggested; nil when suggestions are off.
    public var pauseAfterSeconds: Double?
    /// Partial break lengths, in seconds, that the bank can cover.
    public var partialBreakOptions: [Double]
}
