import Foundation

public enum Mode: String, Codable, Equatable, Sendable {
    case idle, working, breaking
}

public struct Deliverable: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isDone: Bool
    public var completedAt: Date?
}

/// A running work stint. Break time earned so far at earlier ratios is kept
/// in `earnedSeconds`; work since `earnAnchor` earns at the current ratio.
public struct Stint: Codable, Equatable, Sendable {
    public var start: Date
    public var deliverableID: UUID?
    public var earnedSeconds: Double
    public var earnAnchor: Date
}

public struct BreakSession: Codable, Equatable, Sendable {
    public var start: Date
    /// How long the user chose to take. The countdown and alarm use this.
    public var allowanceSeconds: Double
    /// The deliverable of the stint this break closed.
    public var deliverableID: UUID?
    public var checkpoint: String?
    public var handoff: String?
    public var alarmFired: Bool
    /// True for a lunch break: it lasts as long as you choose and starts the
    /// afternoon with an empty bank. Absent in state saved by earlier versions.
    public var isMeal: Bool?
}

public struct WorkEntry: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var deliverableID: UUID?
}

public struct BreakEntry: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
}

public struct Checkpoint: Codable, Equatable, Sendable {
    public var time: Date
    public var text: String
    public var deliverableID: UUID?
}

/// What to show the user when they come back to work.
public struct ReturnInfo: Codable, Equatable, Sendable {
    public var checkpoint: String?
    public var handoff: String?

    public init(checkpoint: String?, handoff: String?) {
        self.checkpoint = checkpoint
        self.handoff = handoff
    }
}

/// When the app suggests a break. Times of day are minutes after midnight.
public struct Rhythm: Codable, Equatable, Sendable {
    /// Suggest a break after this much unbroken work, and again at each repeat.
    public var nudgeEnabled = true
    public var firstNudgeMinutes = 60
    public var repeatNudgeMinutes = 30
    /// Suggest lunch at this time of day.
    public var lunchEnabled = true
    public var lunchMinuteOfDay = 12 * 60
    public var lunchLengthMinutes = 60
    /// The early-afternoon dip in energy: suggest a pause sooner, and a walk.
    public var dipEnabled = true
    public var dipStartMinute = 13 * 60
    public var dipEndMinute = 14 * 60 + 30
    public var dipNudgeMinutes = 45
    /// Ring the bell with a suggestion and at the end of a break.
    public var bellEnabled = true

    public init() {}

    /// Every field falls back to its default, so settings saved by an older
    /// version that lacked a field still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Rhythm()
        nudgeEnabled = try c.decodeIfPresent(Bool.self, forKey: .nudgeEnabled) ?? d.nudgeEnabled
        firstNudgeMinutes = try c.decodeIfPresent(Int.self, forKey: .firstNudgeMinutes) ?? d.firstNudgeMinutes
        repeatNudgeMinutes = try c.decodeIfPresent(Int.self, forKey: .repeatNudgeMinutes) ?? d.repeatNudgeMinutes
        lunchEnabled = try c.decodeIfPresent(Bool.self, forKey: .lunchEnabled) ?? d.lunchEnabled
        lunchMinuteOfDay = try c.decodeIfPresent(Int.self, forKey: .lunchMinuteOfDay) ?? d.lunchMinuteOfDay
        lunchLengthMinutes = try c.decodeIfPresent(Int.self, forKey: .lunchLengthMinutes) ?? d.lunchLengthMinutes
        dipEnabled = try c.decodeIfPresent(Bool.self, forKey: .dipEnabled) ?? d.dipEnabled
        dipStartMinute = try c.decodeIfPresent(Int.self, forKey: .dipStartMinute) ?? d.dipStartMinute
        dipEndMinute = try c.decodeIfPresent(Int.self, forKey: .dipEndMinute) ?? d.dipEndMinute
        dipNudgeMinutes = try c.decodeIfPresent(Int.self, forKey: .dipNudgeMinutes) ?? d.dipNudgeMinutes
        bellEnabled = try c.decodeIfPresent(Bool.self, forKey: .bellEnabled) ?? d.bellEnabled
    }

    /// How long after lunchtime a lunch suggestion still makes sense.
    public static let lunchWindowMinutes = 120
    /// A walk is suggested for breaks during the dip and for this long after it.
    public static let movementTailMinutes = 60
}

/// What has already been suggested, so nothing is suggested twice.
public struct NudgeLog: Codable, Equatable, Sendable {
    public var nudgesThisStint = 0
    public var lunchSuggestedOn: Date?
    public var lunchTakenOn: Date?
    /// "Not now": the pause suggestion stays hidden until the next one is due.
    public var dismissedNudges = 0
    public var lunchDismissedOn: Date?

    public init() {}
}

/// A suggestion to take a break.
public enum Nudge: Equatable, Sendable {
    case pause
    case lunch
}

public struct Settings: Codable, Equatable, Sendable {
    public var handoffPrompt: Bool = true
    public var launchAtLogin: Bool = false
}

/// Meetings from the calendar: they pause the timer by themselves.
public struct Meetings: Codable, Equatable, Sendable {
    public var pauseEnabled = true
    /// What the calendar last said.
    public var inMeeting = false
    /// The timer was paused by a meeting, so it starts again when the meeting ends.
    public var pausedByMeeting = false
    /// What was being worked on when the meeting began.
    public var resumeDeliverableID: UUID?

    public init() {}
}

/// Whether the user is at the Mac. Away means the screen is locked, the display
/// is off, the Mac slept, the app was not running, or nothing was touched for a while.
public struct Presence: Codable, Equatable, Sendable {
    public var pauseEnabled = true
    public var away = false
    public var awaySince: Date?
    /// Work was stopped by going away, so it starts again on the way back.
    public var pausedByAway = false
    /// What was being worked on when the user left.
    public var resumeDeliverableID: UUID?
    /// Hold suggestions back while the microphone is in use, as in a call.
    public var quietOnCalls = true

    public init() {}

    /// A long enough absence around lunchtime counts as lunch.
    public static let lunchAbsenceMinutes = 20
}

/// What the user is doing right now. One case at a time, so a stint and a
/// break can never exist together.
public enum Session: Codable, Equatable, Sendable {
    case idle
    case working(Stint)
    case breaking(BreakSession)
}

public struct EngineState: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int = EngineState.currentVersion
    public var session: Session = .idle
    /// The break ratio is 1 / ratioDenominator. Allowed: 2...6.
    public var ratioDenominator: Int = 3
    /// Banked break time. While on a break this is the bank at the start of the break.
    public var bankSeconds: Double = 0
    public var deliverables: [Deliverable] = []
    public var lastDeliverableID: UUID?
    public var workLog: [WorkEntry] = []
    public var breakLog: [BreakEntry] = []
    public var checkpoints: [Checkpoint] = []
    public var settings = Settings()
    public var returnInfo: ReturnInfo?
    /// Optional so that state saved before these existed still loads.
    public var savedRhythm: Rhythm?
    public var savedNudgeLog: NudgeLog?
    /// Set while the timer is paused, for a meeting or anything else that is
    /// neither work on a deliverable nor a break.
    public var pausedSince: Date?
    public var savedMeetings: Meetings?
    public var savedPresence: Presence?

    public init() {}

    public var presence: Presence {
        get { savedPresence ?? Presence() }
        set { savedPresence = newValue }
    }

    public var meetings: Meetings {
        get { savedMeetings ?? Meetings() }
        set { savedMeetings = newValue }
    }

    public var rhythm: Rhythm {
        get { savedRhythm ?? Rhythm() }
        set { savedRhythm = newValue }
    }

    public var nudgeLog: NudgeLog {
        get { savedNudgeLog ?? NudgeLog() }
        set { savedNudgeLog = newValue }
    }

    public var ratio: Double { 1.0 / Double(ratioDenominator) }

    public var mode: Mode {
        switch session {
        case .idle: .idle
        case .working: .working
        case .breaking: .breaking
        }
    }

    public var stint: Stint? {
        if case .working(let stint) = session { stint } else { nil }
    }

    public var currentBreak: BreakSession? {
        if case .breaking(let current) = session { current } else { nil }
    }
}

public enum Event: Equatable, Sendable {
    /// The app has started; lets the engine re-arm a pending alarm.
    case launch
    case startWork(deliverableID: UUID?)
    /// Time has passed. Lets the engine decide whether a break suggestion is due.
    case tick
    /// `seconds` nil means take the whole bank.
    case startBreak(seconds: Double?)
    /// A lunch break of the length set in the rhythm settings.
    case startLunch
    case recordCheckpoint(String)
    case recordHandoff(String)
    case resumeWork(deliverableID: UUID?)
    case alarmFired
    /// Stop counting, for a meeting or anything else that is neither work nor a break.
    /// The bank is kept, nothing is earned or spent, and nothing rings.
    case pause
    /// The calendar says a meeting is running now, or that none is.
    case meeting(Bool)
    case setMeetingPause(Bool)
    /// The user has left the Mac (locked it, say), or is back.
    case away(Bool)
    /// Nothing ran between `since` and now: the Mac slept or the app was closed.
    case absence(since: Date)
    case setAwayPause(Bool)
    case setQuietOnCalls(Bool)
    case setRatio(denominator: Int)
    case addDeliverable(id: UUID, name: String)
    case renameDeliverable(id: UUID, name: String)
    case completeDeliverable(id: UUID)
    /// "Not now" on the current suggestion.
    case dismissSuggestion
    case setRhythm(Rhythm)
    case setHandoffPrompt(Bool)
    case setLaunchAtLogin(Bool)
    case resetSession
}

public enum Effect: Equatable, Sendable {
    case nudge(Nudge)
    case scheduleAlarm(at: Date)
    case cancelAlarm
    case askCheckpoint
    case askHandoff
    case showReturn(ReturnInfo)
    case setLaunchAtLogin(Bool)
    case save
}
