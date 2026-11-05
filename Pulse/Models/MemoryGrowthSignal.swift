import Foundation

/// Soft trend over one selected-process memory series (`ChartSample.value` is bytes).
///
/// The input is that series in sample order (the ring's append order). The whole array
/// is the window. Short series stay `.insufficient`. A full window is `.rising` only when
/// the net increase and the share of upward steps both clear the bars below; otherwise
/// `.none`. No slope fit, no host usage series, no other process.
enum MemoryGrowthSignal: Equatable, Sendable {
    /// Fewer than `minSamples` points. The window is still filling.
    case insufficient
    /// Net increase and a majority of adjacent steps are up.
    case rising
    /// The window is full, and the two rise conditions are not both met.
    case none

    /// Points required before a rise can be reported. A shorter prefix stays `.insufficient`.
    static let minSamples = 80

    /// Strict net byte increase from the first sample to the last.
    /// 8 MiB sits above megabyte-scale jitter without requiring a huge climb.
    static let deltaThreshold: Double = 8 * 1024 * 1024

    /// Minimum share of adjacent steps with a positive delta.
    /// Compared as 3/5 so the boundary is exact: `positiveSteps * 5 >= stepCount * 3`.
    static let riseFloor = 0.6

    private static let riseFloorNumerator = 3
    private static let riseFloorDenominator = 5

    static func evaluate(_ samples: [ChartSample]) -> MemoryGrowthSignal {
        guard samples.count >= minSamples else {
            return .insufficient
        }

        let netIncrease = samples[samples.count - 1].value - samples[0].value
        guard netIncrease > deltaThreshold else {
            return .none
        }

        let stepCount = samples.count - 1
        var positiveSteps = 0
        for index in 1..<samples.count where samples[index].value > samples[index - 1].value {
            positiveSteps += 1
        }
        guard positiveSteps * riseFloorDenominator >= stepCount * riseFloorNumerator else {
            return .none
        }
        return .rising
    }
}
