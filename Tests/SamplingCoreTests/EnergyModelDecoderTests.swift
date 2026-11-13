import XCTest
@testable import SamplingCore

/// Literals are joule-to-watt conversions. A missing previous sample is nil, never 0.
final class EnergyModelDecoderTests: XCTestCase {
    func testFirstSampleHasNoDelta() {
        let current = EnergyModelChannel(name: "CPU", unit: "mJ", cumulative: 3_000)
        XCTAssertNil(EnergyModelDecoder.deltaWatts(previous: nil, current: current, elapsed: 2))
    }

    func testMillijoulesOverTwoSecondsAreOneWatt() {
        let previous = EnergyModelChannel(name: "CPU", unit: "mJ", cumulative: 1_000)
        let current = EnergyModelChannel(name: "CPU", unit: "mJ", cumulative: 3_000)
        XCTAssertEqual(EnergyModelDecoder.deltaWatts(previous: previous, current: current, elapsed: 2), 1)
    }

    func testNanojoulesOverTwoSecondsAreOneWatt() {
        let previous = EnergyModelChannel(name: "GPU", unit: "nJ", cumulative: 0)
        let current = EnergyModelChannel(name: "GPU", unit: "nJ", cumulative: 2_000_000_000)
        XCTAssertEqual(EnergyModelDecoder.deltaWatts(previous: previous, current: current, elapsed: 2), 1)
    }

    func testUnknownUnitStaysMissing() {
        let previous = EnergyModelChannel(name: "CPU", unit: "furlong", cumulative: 1)
        let current = EnergyModelChannel(name: "CPU", unit: "furlong", cumulative: 5)
        XCTAssertNil(EnergyModelDecoder.deltaWatts(previous: previous, current: current, elapsed: 2))
    }

    func testUnknownChannelIsIgnored() {
        let previous = EnergyModelChannel(name: "mystery", unit: "mJ", cumulative: 0)
        let current = EnergyModelChannel(name: "mystery", unit: "mJ", cumulative: 5_000)
        let reading = EnergyModelDecoder.cpuReading(
            channels: [(previous: previous, current: current)],
            elapsed: 2,
            performanceHertz: 3_000_000_000,
            efficiencyHertz: 1_500_000_000
        )
        XCTAssertNil(reading.cpuWatts)
    }

    func testKnownCPUChannelAndCoreFrequencies() {
        let previous = EnergyModelChannel(name: "CPU Energy", unit: "mJ", cumulative: 0)
        let current = EnergyModelChannel(name: "CPU Energy", unit: "mJ", cumulative: 4_000)
        let reading = EnergyModelDecoder.cpuReading(
            channels: [(previous: previous, current: current)],
            elapsed: 2,
            performanceHertz: 3_200_000_000,
            efficiencyHertz: nil
        )
        XCTAssertEqual(reading.cpuWatts, 2)
        XCTAssertEqual(reading.performanceHertz, 3_200_000_000)
        XCTAssertNil(reading.efficiencyHertz)
    }

    func testStateNameBecomesHertzOnlyWhenTheUnitIsWritten() {
        XCTAssertEqual(EnergyModelDecoder.hertz(fromStateName: "3.2 GHz"), 3_200_000_000)
        XCTAssertEqual(EnergyModelDecoder.hertz(fromStateName: "2400 MHz"), 2_400_000_000)
        XCTAssertEqual(EnergyModelDecoder.hertz(fromStateName: "600MHz"), 600_000_000)
        XCTAssertEqual(EnergyModelDecoder.hertz(fromStateName: "2400"), 2_400_000_000)
        XCTAssertNil(EnergyModelDecoder.hertz(fromStateName: "P-Cluster"))
        XCTAssertNil(EnergyModelDecoder.hertz(fromStateName: "0"))
    }

    func testNonFiniteFrequencyStaysMissing() {
        XCTAssertNil(EnergyModelDecoder.frequencyHertz(.infinity))
        XCTAssertNil(EnergyModelDecoder.frequencyHertz(.nan))
        XCTAssertEqual(EnergyModelDecoder.frequencyHertz(2_400_000_000), 2_400_000_000)
    }
}
