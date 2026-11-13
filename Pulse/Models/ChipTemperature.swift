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

/// Current chip temperature for this visit.
struct ChipTemperaturePageState: Equatable, Sendable {
    var celsius: Double?
    var visitSucceeded: Bool

    /// Integer degrees, half away from zero. Missing is 「—」, never 0.
    /// A value from before this visit succeeded is not shown.
    var text: String {
        guard visitSucceeded, let celsius, celsius.isFinite else { return CPUPercentText.missing }
        let rounded = celsius.rounded(.toNearestOrAwayFromZero)
        return "\(Int(rounded)) °C"
    }

    static let initial = ChipTemperaturePageState(celsius: nil, visitSucceeded: false)
}

enum ChipTemperatureCopy {
    static let title = "芯片温度"
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
            return current
        case .justEntered:
            return applyFrame(frame, sensors: sensors, to: .initial)
        case .stayed:
            return applyFrame(frame, sensors: sensors, to: current)
        }
    }

    private static func applyFrame(
        _ frame: ChipTemperatureFrameOutcome,
        sensors: [ChipTemperatureSensor],
        to current: ChipTemperaturePageState
    ) -> ChipTemperaturePageState {
        switch frame {
        case .pending, .failed:
            return current
        case .succeeded:
            var next = current
            next.celsius = hottest(in: sensors)
            next.visitSucceeded = true
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
