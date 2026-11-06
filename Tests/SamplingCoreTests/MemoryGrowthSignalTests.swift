import XCTest
@testable import SamplingCore

final class MemoryGrowthSignalTests: XCTestCase {
    private let baseline = 200_000_000.0

    func testPinnedThresholds() {
        XCTAssertEqual(MemoryGrowthSignal.minSamples, 80)
        XCTAssertEqual(MemoryGrowthSignal.deltaThreshold, 8 * 1024 * 1024)
        XCTAssertEqual(MemoryGrowthSignal.riseFloor, 0.6)
    }

    func testSteadyClimbAcrossTheFullWindowIsRising() {
        let samples = series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(samples), .rising)
    }

    func testShortSeriesStaysInsufficientEvenWhenEveryStepClimbs() {
        let almost = series(count: MemoryGrowthSignal.minSamples - 1, step: 8_388_608)
        XCTAssertEqual(almost.count, 79)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(almost), .insufficient)
        XCTAssertEqual(MemoryGrowthSignal.evaluate([]), .insufficient)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(series(count: 1, step: 0)), .insufficient)
    }

    func testFullFlatWindowIsNone() {
        XCTAssertEqual(
            MemoryGrowthSignal.evaluate(series(count: 90, step: 0)),
            .none
        )
    }

    func testNetIncreaseMustBeStrictlyAboveTheThreshold() {
        let exact = line(count: MemoryGrowthSignal.minSamples, net: MemoryGrowthSignal.deltaThreshold)
        XCTAssertEqual(exact.last!.value - exact.first!.value, MemoryGrowthSignal.deltaThreshold)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(exact), .none)

        let justOver = line(count: MemoryGrowthSignal.minSamples, net: MemoryGrowthSignal.deltaThreshold + 1)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(justOver), .rising)
    }

    func testRiseFloorBoundaryIsExact() {
        let steps = 80
        let atFloor = saw(stepCount: steps, positiveSteps: 48, up: 1_048_576, down: 0)
        XCTAssertEqual(atFloor.count, MemoryGrowthSignal.minSamples + 1)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(atFloor), .rising)

        let underFloor = saw(stepCount: steps, positiveSteps: 47, up: 1_048_576, down: 0)
        XCTAssertGreaterThan(underFloor.last!.value - underFloor.first!.value, MemoryGrowthSignal.deltaThreshold)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(underFloor), .none)
    }

    func testEndHighWithFewUpStepsIsNone() {
        var values = [Double](repeating: baseline, count: MemoryGrowthSignal.minSamples)
        for index in 1..<(values.count - 1) {
            values[index] = baseline - Double(index) * 1_000
        }
        values[values.count - 1] = baseline + 64 * 1_024 * 1_024

        let samples = samples(values)
        var positive = 0
        for index in 1..<samples.count where samples[index].value > samples[index - 1].value {
            positive += 1
        }
        XCTAssertEqual(positive, 1)
        XCTAssertGreaterThan(samples.last!.value - samples.first!.value, MemoryGrowthSignal.deltaThreshold)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(samples), .none)
    }

    func testDipThenRecoverUsesFirstAndLastNotTheRange() {
        var values = [Double](repeating: baseline, count: MemoryGrowthSignal.minSamples)
        values[1] = 10_000_000
        let recovered = baseline + 4 * 1_024 * 1_024
        for index in 2..<values.count {
            let progress = Double(index - 1) / Double(values.count - 2)
            values[index] = values[1] + (recovered - values[1]) * progress
        }

        let samples = samples(values)
        XCTAssertEqual(samples.last!.value - samples.first!.value, 4 * 1_024 * 1_024)
        XCTAssertLessThan(samples.last!.value - samples.first!.value, MemoryGrowthSignal.deltaThreshold)
        XCTAssertGreaterThan(samples.last!.value - samples.map(\.value).min()!, MemoryGrowthSignal.deltaThreshold)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(samples), .none)
    }

    /// Real downward steps inside a full window still rise when net and the 3/5 floor hold.
    /// `evaluate` is not changed for this case.
    func testWindowWithRealDownticksStillRisesWhenThresholdsHold() {
        let count = MemoryGrowthSignal.minSamples
        XCTAssertGreaterThanOrEqual(count, 80)
        let upSteps = 60
        let downSteps = count - 1 - upSteps
        XCTAssertGreaterThan(downSteps, 0)

        var values = [baseline]
        for index in 0..<(count - 1) {
            let delta = index < upSteps ? 1_048_576.0 : -4_096.0
            values.append(values[values.count - 1] + delta)
        }
        let series = samples(values)
        XCTAssertEqual(series.count, count)

        var downs = 0
        var ups = 0
        for index in 1..<series.count {
            if series[index].value < series[index - 1].value { downs += 1 }
            if series[index].value > series[index - 1].value { ups += 1 }
        }
        XCTAssertEqual(ups, upSteps)
        XCTAssertEqual(downs, downSteps)
        XCTAssertGreaterThan(series.last!.value - series.first!.value, MemoryGrowthSignal.deltaThreshold)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(series), .rising)
    }

    func testANewSeriesDoesNotKeepThePreviousRisingResult() {
        let earlier = series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(earlier), .rising)

        let openedLater = series(count: 12, step: 8_388_608)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(openedLater), .insufficient)

        let replacement = series(count: 90, step: 0)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(replacement), .none)

        XCTAssertEqual(MemoryGrowthSignal.evaluate(earlier), .rising)
    }

    func testSignalNamesDoNotClaimALeakOrDanger() {
        let names = [
            String(describing: MemoryGrowthSignal.insufficient),
            String(describing: MemoryGrowthSignal.rising),
            String(describing: MemoryGrowthSignal.none),
        ]
        for name in names {
            XCTAssertFalse(name.contains("泄漏"))
            XCTAssertFalse(name.contains("危险"))
            XCTAssertFalse(name.localizedCaseInsensitiveContains("leak"))
        }
    }

    private func series(count: Int, step: Double) -> [ChartSample] {
        samples((0..<count).map { baseline + Double($0) * step })
    }

    private func line(count: Int, net: Double) -> [ChartSample] {
        let lastIndex = count - 1
        let values = (0..<count).map { index -> Double in
            if index == lastIndex { return baseline + net }
            return baseline + net * Double(index) / Double(lastIndex)
        }
        return samples(values)
    }

    /// `positiveSteps` upward moves first, then the remaining moves of `down` (0 keeps them flat).
    private func saw(stepCount: Int, positiveSteps: Int, up: Double, down: Double) -> [ChartSample] {
        var values = [baseline]
        for index in 0..<stepCount {
            let delta = index < positiveSteps ? up : -down
            values.append(values[values.count - 1] + delta)
        }
        return samples(values)
    }

    private func samples(_ values: [Double]) -> [ChartSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return values.enumerated().map { index, value in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index) * 1.5),
                value: value
            )
        }
    }
}
