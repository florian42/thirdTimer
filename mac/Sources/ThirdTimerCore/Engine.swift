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

        case .startWork(let deliverableID):
            guard s.mode == .idle else { return (state, []) }
            beginStint(&s, deliverableID: deliverableID, handoff: nil, now: now, effects: &effects)

        case .startBreak(let seconds):
            guard s.mode == .working, let stint = s.stint else { return (state, []) }
            s.bankSeconds += accrued(stint, ratio: s.ratio, now: now)
            s.workLog.append(WorkEntry(start: stint.start, end: now, deliverableID: stint.deliverableID))
            let allowance = min(max(0, seconds ?? s.bankSeconds), s.bankSeconds)
            s.returnInfo = nil
            s.session = .breaking(BreakSession(
                start: now,
                allowanceSeconds: allowance,
                deliverableID: stint.deliverableID,
                checkpoint: nil,
                handoff: nil,
                alarmFired: false
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
            s.bankSeconds = max(0, s.bankSeconds - taken)
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

        case .addDeliverable(let id, let rawName, let deadline):
            let name = oneLine(rawName, limit: Engine.nameLimit)
            guard !name.isEmpty, !s.deliverables.contains(where: { $0.id == id }) else { return (state, []) }
            s.deliverables.append(Deliverable(id: id, name: name, deadline: deadline, isDone: false, completedAt: nil))

        case .editDeliverable(let id, let rawName, let deadline):
            let name = oneLine(rawName, limit: Engine.nameLimit)
            guard !name.isEmpty, let index = s.deliverables.firstIndex(where: { $0.id == id }) else {
                return (state, [])
            }
            s.deliverables[index].name = name
            s.deliverables[index].deadline = deadline

        case .completeDeliverable(let id):
            guard let index = s.deliverables.firstIndex(where: { $0.id == id }), !s.deliverables[index].isDone else {
                return (state, [])
            }
            s.deliverables[index].isDone = true
            s.deliverables[index].completedAt = now

        case .setWorkingHours(let hours):
            guard hours.count == 7 else { return (state, []) }
            s.workingHours = hours.map { day in
                let start = min(max(0, day.startMinute), 24 * 60)
                let end = min(max(start, day.endMinute), 24 * 60)
                return DayHours(enabled: day.enabled, startMinute: start, endMinute: end)
            }

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
                deadline: d.deadline,
                isDone: d.isDone,
                deadlinePassed: d.deadline <= now,
                investedSeconds: invested(state, deliverableID: d.id, now: now),
                runwaySeconds: runway(state, deadline: d.deadline, liveBank: liveBank, now: now),
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

    /// Work time left until the deadline. Of the working hours that remain,
    /// the banked break time is already spoken for, and the rest splits into
    /// work and the breaks that work will earn. So an hour of work lowers
    /// runway by an hour, and an earned break leaves it unchanged.
    private func runway(_ state: EngineState, deadline: Date, liveBank: Double, now: Date) -> Double {
        let available = workingSeconds(from: now, to: deadline, hours: state.workingHours)
        return max(0, available - liveBank) / (1 + state.ratio)
    }

    /// Seconds inside the configured working hours between two moments.
    public func workingSeconds(from: Date, to: Date, hours: [DayHours]) -> Double {
        guard to > from, hours.count == 7 else { return 0 }
        var total = 0.0
        var day = calendar.startOfDay(for: from)
        while day < to {
            let weekday = calendar.component(.weekday, from: day)
            let h = hours[weekday - 1]
            if h.enabled, h.endMinute > h.startMinute {
                let start = moment(day, minute: h.startMinute)
                let end = moment(day, minute: h.endMinute)
                total += overlap(start, end, from, to)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    private func moment(_ day: Date, minute: Int) -> Date {
        if minute < 24 * 60,
           let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) {
            return date
        }
        return day.addingTimeInterval(Double(minute) * 60)
    }

    private func overlap(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Double {
        max(0, min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart)))
    }
}

// MARK: - What the user sees

public struct DeliverableView: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var deadline: Date
    public var isDone: Bool
    public var deadlinePassed: Bool
    public var investedSeconds: Double
    public var runwaySeconds: Double
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
    /// Partial break lengths, in seconds, that the bank can cover.
    public var partialBreakOptions: [Double]
}
