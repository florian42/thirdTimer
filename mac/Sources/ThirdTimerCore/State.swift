import Foundation

public enum Mode: String, Codable, Equatable, Sendable {
    case idle, working, breaking
}

public struct Deliverable: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var deadline: Date
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

/// Working hours for one day of the week, in minutes after midnight.
public struct DayHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var startMinute: Int
    public var endMinute: Int

    public init(enabled: Bool, startMinute: Int, endMinute: Int) {
        self.enabled = enabled
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
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

public struct Settings: Codable, Equatable, Sendable {
    public var handoffPrompt: Bool = true
    public var launchAtLogin: Bool = false
}

public struct EngineState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int = EngineState.currentVersion
    public var mode: Mode = .idle
    /// The break ratio is 1 / ratioDenominator. Allowed: 2...6.
    public var ratioDenominator: Int = 3
    /// Banked break time. While on a break this is the bank at the start of the break.
    public var bankSeconds: Double = 0
    public var stint: Stint?
    public var currentBreak: BreakSession?
    public var deliverables: [Deliverable] = []
    public var lastDeliverableID: UUID?
    public var workLog: [WorkEntry] = []
    public var breakLog: [BreakEntry] = []
    public var checkpoints: [Checkpoint] = []
    /// Seven entries, Sunday first.
    public var workingHours: [DayHours] = EngineState.defaultWorkingHours
    public var settings = Settings()
    public var returnInfo: ReturnInfo?

    public init() {}

    public static let defaultWorkingHours: [DayHours] = (0..<7).map { index in
        DayHours(enabled: index >= 1 && index <= 5, startMinute: 9 * 60, endMinute: 17 * 60)
    }

    public var ratio: Double { 1.0 / Double(ratioDenominator) }
}

public enum Event: Equatable, Sendable {
    /// The app has started; lets the engine re-arm a pending alarm.
    case launch
    case startWork(deliverableID: UUID?)
    /// `seconds` nil means take the whole bank.
    case startBreak(seconds: Double?)
    case recordCheckpoint(String)
    case recordHandoff(String)
    case resumeWork(deliverableID: UUID?)
    case alarmFired
    case setRatio(denominator: Int)
    case addDeliverable(id: UUID, name: String, deadline: Date)
    case editDeliverable(id: UUID, name: String, deadline: Date)
    case completeDeliverable(id: UUID)
    case setWorkingHours([DayHours])
    case setHandoffPrompt(Bool)
    case setLaunchAtLogin(Bool)
    case resetSession
}

public enum Effect: Equatable, Sendable {
    case scheduleAlarm(at: Date)
    case cancelAlarm
    case askCheckpoint
    case askHandoff
    case showReturn(ReturnInfo)
    case setLaunchAtLogin(Bool)
    case save
}
