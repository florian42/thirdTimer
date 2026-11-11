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

public struct Settings: Codable, Equatable, Sendable {
    public var handoffPrompt: Bool = true
    public var launchAtLogin: Bool = false
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

    public init() {}

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
    /// `seconds` nil means take the whole bank.
    case startBreak(seconds: Double?)
    case recordCheckpoint(String)
    case recordHandoff(String)
    case resumeWork(deliverableID: UUID?)
    case alarmFired
    case setRatio(denominator: Int)
    case addDeliverable(id: UUID, name: String)
    case renameDeliverable(id: UUID, name: String)
    case completeDeliverable(id: UUID)
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
