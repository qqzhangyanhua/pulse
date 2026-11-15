import Foundation

/// Numbers for one active screen. The Darwin reader fills these.
/// Zero hertz is variable refresh, not a missing reading.
struct GPUDisplayReading: Equatable, Sendable {
    var isBuiltIn: Bool
    var pixelWidth: Int
    var pixelHeight: Int
    /// Current mode refresh in hertz. Zero is variable refresh.
    /// Nil, negative, or non-finite is missing.
    var modeRefreshHertz: Double?
    /// Matching `NSScreen.maximumFramesPerSecond`. Used only when the mode is 0 Hz.
    /// Nil or a non-positive value means that fallback is also missing.
    var maximumFramesPerSecond: Int?
}

struct GPUDisplayRow: Equatable, Sendable {
    var kindText: String
    var resolutionText: String
    var refreshText: String
}

/// One card. `showsMissing` is the whole card as 「—」, not a row of dashes.
struct GPUDisplaysCard: Equatable, Sendable {
    var rows: [GPUDisplayRow]
    var showsMissing: Bool

    static let missing = GPUDisplaysCard(rows: [], showsMissing: true)
}

enum GPUDisplayCopy {
    static let title = "显示器"
    static let builtIn = "内建"
    static let external = "外接"
    static let missing = "—"
}

enum GPUDisplayProjection {
    /// Built-in screens first, then external. Each group keeps input order.
    /// No readings is one 「—」 for the whole card.
    static func present(_ readings: [GPUDisplayReading]?) -> GPUDisplaysCard {
        guard let readings, !readings.isEmpty else { return .missing }
        let ordered = readings.filter(\.isBuiltIn) + readings.filter { !$0.isBuiltIn }
        return GPUDisplaysCard(rows: ordered.map(row), showsMissing: false)
    }

    private static func row(_ reading: GPUDisplayReading) -> GPUDisplayRow {
        GPUDisplayRow(
            kindText: reading.isBuiltIn ? GPUDisplayCopy.builtIn : GPUDisplayCopy.external,
            resolutionText: resolutionText(width: reading.pixelWidth, height: reading.pixelHeight),
            refreshText: refreshText(reading)
        )
    }

    private static func resolutionText(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return GPUDisplayCopy.missing }
        return "\(width) × \(height)"
    }

    /// A positive mode rate is shown as-is. Zero uses the screen maximum.
    /// Anything else, including a missing maximum, stays 「—」 and is not written as 0 Hz.
    private static func refreshText(_ reading: GPUDisplayReading) -> String {
        guard let hertz = reading.modeRefreshHertz, hertz.isFinite, hertz >= 0 else {
            return GPUDisplayCopy.missing
        }
        if hertz == 0 {
            guard let maximum = reading.maximumFramesPerSecond, maximum > 0 else {
                return GPUDisplayCopy.missing
            }
            return "\(maximum) Hz"
        }
        return hertzText(hertz)
    }

    /// Whole numbers stay whole. Other rates keep two decimal places, trailing zeros dropped.
    private static func hertzText(_ hertz: Double) -> String {
        let scaled = (hertz * 100).rounded()
        guard scaled.isFinite, scaled >= 1, scaled <= Double(Int.max) else {
            return GPUDisplayCopy.missing
        }
        let hundredths = Int(scaled)
        let whole = hundredths / 100
        let fraction = hundredths % 100
        if fraction == 0 {
            return "\(whole) Hz"
        }
        if fraction % 10 == 0 {
            return "\(whole).\(fraction / 10) Hz"
        }
        let digits = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(whole).\(digits) Hz"
    }
}
