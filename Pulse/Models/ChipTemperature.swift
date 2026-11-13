import Foundation

/// One HID temperature service for this frame. The reader does not select or round.
struct ChipTemperatureSensor: Equatable, Sendable {
    var productName: String?
    var celsius: Double?

    init(productName: String? = nil, celsius: Double? = nil) {
        self.productName = productName
        self.celsius = celsius
    }
}

enum ChipTemperatureFrameOutcome: Equatable, Sendable {
    case pending
    case failed
    case succeeded
}

enum ChipTemperaturePageTransition: Equatable, Sendable {
    case stayed
    case justLeft
    case justEntered
}

/// Current chip temperature and this visit's curve. The curve stores raw Celsius.
struct ChipTemperaturePageState: Equatable, Sendable {
    var celsius: Double?
    var history: SystemCPUHistory = SystemCPUHistory()
    var visitSucceeded: Bool

    /// Integer degrees, half away from zero. Missing is 「—」, never 0.
    /// A value from before this visit succeeded is not shown.
    var text: String {
        guard visitSucceeded, let celsius, celsius.isFinite else { return CPUPercentText.missing }
        return ChipTemperatureCopy.degrees(celsius)
    }

    /// Fewer than two points is not a line.
    var showsCurve: Bool { history.samples.count >= 2 }

    /// Sample span, not a 0…100 percent axis, so a small rise or fall stays visible.
    var curveDomain: ClosedRange<Double> {
        let values = history.samples.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max((high - low) * 0.25, 0.5)
        return (low - pad)...(high + pad)
    }

    static let initial = ChipTemperaturePageState(celsius: nil, visitSucceeded: false)
}

enum ChipTemperatureCopy {
    static let title = "芯片温度"

    /// Integer degrees, half away from zero, with a space and the unit.
    static func degrees(_ celsius: Double) -> String {
        let rounded = celsius.rounded(.toNearestOrAwayFromZero)
        return "\(Int(rounded)) °C"
    }
}

enum ChipTemperaturePageProjection {
    static let productPrefix = "PMU tdie"

    static func apply(
        sensors: [ChipTemperatureSensor] = [],
        frame: ChipTemperatureFrameOutcome,
        sampledAt: Date?,
        current: ChipTemperaturePageState,
        transition: ChipTemperaturePageTransition
    ) -> ChipTemperaturePageState {
        switch transition {
        case .justLeft:
            var next = current
            next.history.reset()
            return next
        case .justEntered:
            return applyFrame(frame, sensors: sensors, sampledAt: sampledAt, to: .initial)
        case .stayed:
            return applyFrame(frame, sensors: sensors, sampledAt: sampledAt, to: current)
        }
    }

    private static func applyFrame(
        _ frame: ChipTemperatureFrameOutcome,
        sensors: [ChipTemperatureSensor],
        sampledAt: Date?,
        to current: ChipTemperaturePageState
    ) -> ChipTemperaturePageState {
        switch frame {
        case .pending, .failed:
            return current
        case .succeeded:
            var next = current
            let chosen = hottest(in: sensors)
            next.celsius = chosen
            next.visitSucceeded = true
            if let chosen {
                next.history.record(percent: chosen, at: sampledAt)
            }
            return next
        }
    }

    /// Case-sensitive prefix, then the max finite value. No match is missing.
    private static func hottest(in sensors: [ChipTemperatureSensor]) -> Double? {
        sensors.compactMap { sensor -> Double? in
            guard let name = sensor.productName, name.hasPrefix(productPrefix) else { return nil }
            guard let celsius = sensor.celsius, celsius.isFinite else { return nil }
            return celsius
        }.max()
    }
}
