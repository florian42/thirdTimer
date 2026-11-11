import Foundation

public enum Format {
    /// "6:12" or "1:02:03".
    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h):\(pad(m)):\(pad(s))" }
        return "\(m):\(pad(s))"
    }

    /// "34m" or "1h 05m".
    public static func short(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds).rounded(.down)) / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(pad(minutes % 60))m"
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

public enum Persistence {
    public enum Failure: Error, Equatable {
        case newerVersion(Int)
    }

    public static func encode(_ state: EngineState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    public static func decode(_ data: Data) throws -> EngineState {
        let decoder = JSONDecoder()
        let version = try decoder.decode(VersionProbe.self, from: data).version
        if version > EngineState.currentVersion {
            throw Failure.newerVersion(version)
        }
        if version == 1 {
            return try decoder.decode(StateV1.self, from: data).migrated()
        }
        return try decoder.decode(EngineState.self, from: data)
    }

    private struct VersionProbe: Decodable {
        var version: Int
    }

    /// The first saved format, which kept the mode, the stint and the break
    /// as three separate fields.
    private struct StateV1: Decodable {
        var mode: Mode
        var ratioDenominator: Int
        var bankSeconds: Double
        var stint: Stint?
        var currentBreak: BreakSession?
        var deliverables: [Deliverable]
        var lastDeliverableID: UUID?
        var workLog: [WorkEntry]
        var breakLog: [BreakEntry]
        var checkpoints: [Checkpoint]
        var settings: Settings
        var returnInfo: ReturnInfo?

        func migrated() -> EngineState {
            var state = EngineState()
            switch (mode, stint, currentBreak) {
            case (.working, let stint?, _): state.session = .working(stint)
            case (.breaking, _, let current?): state.session = .breaking(current)
            default: state.session = .idle
            }
            state.ratioDenominator = ratioDenominator
            state.bankSeconds = bankSeconds
            state.deliverables = deliverables
            state.lastDeliverableID = lastDeliverableID
            state.workLog = workLog
            state.breakLog = breakLog
            state.checkpoints = checkpoints
            state.settings = settings
            state.returnInfo = returnInfo
            return state
        }
    }
}
