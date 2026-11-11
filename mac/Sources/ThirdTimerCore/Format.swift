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
        let state = try JSONDecoder().decode(EngineState.self, from: data)
        if state.version > EngineState.currentVersion {
            throw Failure.newerVersion(state.version)
        }
        return state
    }
}
