import XCTest
@testable import SamplingCore

/// Frequency-distribution bars from one GPU Performance States delta.
/// Expected percents are one-decimal literals, not recomputed in the assertion.
final class GPUFrequencyDistributionTests: XCTestCase {
    func testShareIsThatStatesResidencyOverTheTotal() {
        // OFF 1 and P2 2. 1/3 and 2/3 are 33.3% and 66.7%. P2 is 486 MHz.
        // A zero P1 and another subgroup's 9 must not move the total.
        let distribution = EnergyModelDecoder.gpuFrequencyDistribution(
            states: [
                GPUFrequencyState(subgroup: "GPU Performance States", name: "OFF", residency: 1),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P1", residency: 0),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P2", residency: 2),
                GPUFrequencyState(subgroup: "GPU SW States", name: "P6", residency: 9),
            ],
            table: m1ProVoltageTable()
        )
        guard case .bars(let bars) = distribution else {
            return XCTFail("expected two bars, got \(distribution)")
        }
        XCTAssertEqual(bars.map(\.label), ["关闭", "486 MHz"])
        XCTAssertEqual(bars.map(\.percentText), ["33.3%", "66.7%"])
    }

    func testZeroResidencyStatesAreHidden() {
        // OFF 10 and P3 30. 10/40 and 30/40 are 25.0% and 75.0%. P3 is 648 MHz.
        let distribution = EnergyModelDecoder.gpuFrequencyDistribution(
            states: [
                GPUFrequencyState(subgroup: "GPU Performance States", name: "OFF", residency: 10),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P1", residency: 0),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P3", residency: 30),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P5", residency: 0),
            ],
            table: m1ProVoltageTable()
        )
        guard case .bars(let bars) = distribution else {
            return XCTFail("expected two bars, got \(distribution)")
        }
        XCTAssertEqual(bars.map(\.label), ["关闭", "648 MHz"])
        XCTAssertEqual(bars.map(\.percentText), ["25.0%", "75.0%"])
        XCTAssertFalse(bars.contains { $0.label == "P1" || $0.label == "P5" || $0.label == "389 MHz" || $0.label == "972 MHz" })
        XCTAssertEqual(
            EnergyModelDecoder.gpuFrequencyDistribution(
                states: [
                    GPUFrequencyState(subgroup: "GPU Performance States", name: "OFF", residency: 0),
                    GPUFrequencyState(subgroup: "GPU Performance States", name: "P1", residency: 0),
                ],
                table: m1ProVoltageTable()
            ),
            .missing
        )
        XCTAssertEqual(EnergyModelDecoder.gpuFrequencyDistribution(states: [], table: m1ProVoltageTable()), .missing)
    }

    func testRawLabelsWhenNoStateMaps() {
        let distribution = EnergyModelDecoder.gpuFrequencyDistribution(
            states: [
                GPUFrequencyState(subgroup: "GPU Performance States", name: "OFF", residency: 10),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P1", residency: 20),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P2", residency: 70),
            ],
            table: nil
        )
        guard case .bars(let bars) = distribution else {
            return XCTFail("expected raw bars, got \(distribution)")
        }
        XCTAssertEqual(bars.map(\.label), ["关闭", "P1", "P2"])
        XCTAssertEqual(bars.map(\.percentText), ["10.0%", "20.0%", "70.0%"])
        XCTAssertFalse(bars.contains { $0.label.contains("MHz") || $0.label.contains("Hz") })

        let unmapped = EnergyModelDecoder.gpuFrequencyDistribution(
            states: [
                GPUFrequencyState(subgroup: "GPU Performance States", name: "FAST", residency: 1),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P2", residency: 0),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P99", residency: 2),
            ],
            table: m1ProVoltageTable()
        )
        guard case .bars(let raw) = unmapped else {
            return XCTFail("expected raw bars, got \(unmapped)")
        }
        XCTAssertEqual(raw.map(\.label), ["FAST", "P99"])
        XCTAssertEqual(raw.map(\.percentText), ["33.3%", "66.7%"])
    }

    func testOffIsItsOwnBarLabeledClosed() {
        let distribution = EnergyModelDecoder.gpuFrequencyDistribution(
            states: [
                GPUFrequencyState(subgroup: "GPU Performance States", name: " OFF ", residency: 40),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P1", residency: 0),
            ],
            table: nil
        )
        guard case .bars(let bars) = distribution else {
            return XCTFail("expected the OFF bar, got \(distribution)")
        }
        XCTAssertEqual(bars.map(\.label), ["关闭"])
        XCTAssertEqual(bars.map(\.percentText), ["100.0%"])
        XCTAssertFalse(bars[0].label.contains("OFF"))
        XCTAssertNotEqual(bars[0].label, "空闲")
        XCTAssertNotEqual(bars[0].percentText, "—")
        XCTAssertNotEqual(bars[0].percentText, "0.0%")
    }

    /// The Darwin reader and the card cannot run here. Lock the shared delta and the places that must stay clear.
    func testTheCardUsesTheSamePerformanceDeltaAndStaysOffHistory() throws {
        let reader = try distributionRepoText("Pulse/Sampling/HostEnergyModelReader.swift")
        XCTAssertEqual(occurrenceCount(of: "let states = gpuPerformanceStates(symbols: symbols)", in: reader), 1)
        XCTAssertEqual(
            occurrenceCount(of: "let table = voltageStates9Bytes().flatMap(VoltageStates9.parse)", in: reader),
            1
        )
        XCTAssertTrue(reader.contains("EnergyModelDecoder.gpuFrequency(states: states, table: table)"))
        XCTAssertTrue(reader.contains("EnergyModelDecoder.gpuFrequencyDistribution(states: states, table: table)"))
        XCTAssertTrue(reader.contains("reading.gpuFrequencyDistribution == .missing"))
        XCTAssertFalse(reader.contains("IOServiceOpen"))

        let card = try distributionRepoText("Pulse/Views/GPUOverviewSection+Distribution.swift")
        XCTAssertTrue(card.contains("vm.gpuFrequencyDistribution"))
        XCTAssertTrue(card.contains("GPUFrequencyDistributionCopy.title"))
        XCTAssertTrue(card.contains("GPUFrequencyDistributionCopy.missing"))
        XCTAssertFalse(card.contains("vm.cpuEnergy"))

        let page = try distributionRepoText("Pulse/Views/GPUOverviewSection.swift")
        let curve = page.range(of: "chartAndShare")
        let distribution = page.range(of: "frequencyDistributionCard")
        XCTAssertNotNil(curve)
        XCTAssertNotNil(distribution)
        if let curve, let distribution {
            XCTAssertLessThan(curve.lowerBound, distribution.lowerBound)
        }

        let package = try distributionRepoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[1].contains("\"Models/EnergyModelSample.swift\""))
        XCTAssertFalse(parts[1].contains("GPUOverviewSection+Distribution.swift"))
        XCTAssertFalse(parts[1].contains("HostEnergyModelReader.swift"))

        let project = try distributionRepoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("GPUOverviewSection+Distribution.swift in Sources"))

        for relative in [
            "Pulse/Models/HistoryPolicy.swift",
            "Pulse/Models/DashboardCore+History.swift",
            "Pulse/Models/SnapshotExport.swift",
            "Pulse/MenuBar/MenuBarStatus.swift",
            "Pulse/MenuBar/MenuBarPopoverView.swift",
            "Pulse/Models/MenuBarReading.swift",
        ] {
            let text = try distributionRepoText(relative)
            XCTAssertFalse(text.contains("频率分布"), relative)
            XCTAssertFalse(text.contains("gpuFrequencyDistribution"), relative)
        }
    }

    private func distributionRepoText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private func m1ProVoltageTable() -> [VoltageState9] {
        [
            VoltageState9(hertz: 0, millivolts: 0),
            VoltageState9(hertz: 389_000_000, millivolts: 0),
            VoltageState9(hertz: 486_000_000, millivolts: 0),
            VoltageState9(hertz: 648_000_000, millivolts: 0),
            VoltageState9(hertz: 778_000_000, millivolts: 0),
            VoltageState9(hertz: 972_000_000, millivolts: 0),
            VoltageState9(hertz: 1_296_000_000, millivolts: 0),
        ]
    }
}
