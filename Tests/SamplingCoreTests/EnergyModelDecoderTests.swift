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

    func testGPUChannelDoesNotCountAsCPU() {
        let reading = EnergyModelDecoder.cpuReading(
            channels: [pair("GPU", "mJ", 0, 4_000)],
            elapsed: 2,
            performanceHertz: nil,
            efficiencyHertz: nil
        )
        XCTAssertNil(reading.cpuWatts)
    }

    func testGPUChannelsSumMillijoulesAndNanojoules() {
        // 2 000 mJ over 2 s is 1 W. 2e9 nJ over 2 s is 1 W.
        let watts = EnergyModelDecoder.gpuWatts(
            channels: [
                pair("GPU", "mJ", 0, 2_000),
                pair("GPU SRAM", "nJ", 0, 2_000_000_000),
            ],
            elapsed: 2
        )
        XCTAssertEqual(watts, 2)
    }

    func testGPUEnergyChannelIsUsedAloneNotAddedToItsParts() {
        // Measured on an M1 Pro over 1 s: GPU Energy already includes GPU0 and GPU SRAM0.
        let watts = EnergyModelDecoder.gpuWatts(
            channels: [
                pair("GPU0", "mJ", 0, 285),
                pair("GPU SRAM0", "mJ", 0, 11),
                pair("GPU Energy", "nJ", 0, 303_000_000),
            ],
            elapsed: 1
        )
        XCTAssertEqual(try XCTUnwrap(watts), 0.303, accuracy: 1e-9)
    }

    func testWithoutGPUEnergyTheGPUChannelsAreSummed() {
        let watts = EnergyModelDecoder.gpuWatts(
            channels: [
                pair("GPU0", "mJ", 0, 285),
                pair("GPU SRAM0", "mJ", 0, 11),
                pair("CPU Energy", "mJ", 0, 900),
            ],
            elapsed: 1
        )
        XCTAssertEqual(try XCTUnwrap(watts), 0.296, accuracy: 1e-9)
    }

    func testUnreadableGPUEnergyStaysMissingInsteadOfFallingBackToItsParts() {
        let channels = [
            pair("GPU0", "mJ", 0, 285),
            pair("GPU SRAM0", "mJ", 0, 11),
        ]
        let negativeDelta = channels + [pair("GPU Energy", "nJ", 5_000, 1_000)]
        XCTAssertNil(EnergyModelDecoder.gpuWatts(channels: negativeDelta, elapsed: 1))

        let unknownUnit = channels + [pair("GPU Energy", "furlong", 0, 1_000)]
        XCTAssertNil(EnergyModelDecoder.gpuWatts(channels: unknownUnit, elapsed: 1))
    }

    func testZeroDeltaGPUEnergyIsRealZero() {
        let channels = [
            pair("GPU0", "mJ", 0, 285),
            pair("GPU SRAM0", "mJ", 0, 11),
            pair("GPU Energy", "nJ", 7, 7),
        ]
        XCTAssertEqual(EnergyModelDecoder.gpuWatts(channels: channels, elapsed: 1), 0)
    }

    func testANEMatchesEitherNameAndIgnoresCase() {
        let watts = EnergyModelDecoder.aneWatts(
            channels: [
                pair("ane", "mJ", 0, 1_000),
                pair("Neural Engine", "nJ", 0, 1_000_000_000),
            ],
            elapsed: 1
        )
        XCTAssertEqual(watts, 1 + 1)
    }

    func testDRAMSumsOnlyDRAMChannels() {
        let watts = EnergyModelDecoder.dramWatts(
            channels: [
                pair("DRAM", "mJ", 1_000, 1_000),
                pair("DRAM2", "mJ", 0, 2_000),
                pair("GPU", "mJ", 0, 9_000),
            ],
            elapsed: 2
        )
        XCTAssertEqual(watts, 1)
    }

    func testUnknownNameUnitNegativeAndNonFiniteStayNil() {
        XCTAssertNil(EnergyModelDecoder.gpuWatts(channels: [pair("mystery", "mJ", 0, 5_000)], elapsed: 2))
        XCTAssertNil(EnergyModelDecoder.aneWatts(channels: [pair("ANE", "furlong", 0, 5_000)], elapsed: 2))
        XCTAssertNil(EnergyModelDecoder.dramWatts(channels: [pair("DRAM", "mJ", 5_000, 1_000)], elapsed: 2))
        XCTAssertNil(
            EnergyModelDecoder.gpuWatts(
                channels: [pair("GPU", "mJ", 0, .infinity)],
                elapsed: 2
            )
        )
        XCTAssertNil(EnergyModelDecoder.gpuWatts(channels: [pair("gpu", "mJ", 0, 2_000)], elapsed: 2))
        XCTAssertNil(EnergyModelDecoder.dramWatts(channels: [pair("dram", "mJ", 0, 2_000)], elapsed: 2))
    }

    func testRealZeroWattsStayZeroAndABadSiblingIsLeftOut() {
        XCTAssertEqual(EnergyModelDecoder.gpuWatts(channels: [pair("GPU", "mJ", 4_000, 4_000)], elapsed: 2), 0)
        XCTAssertEqual(
            EnergyModelDecoder.aneWatts(
                channels: [
                    pair("ANE", "mJ", 0, 2_000),
                    pair("ANE Other", "mJ", 5_000, 1_000),
                ],
                elapsed: 2
            ),
            1
        )
    }

    func testGPUFrequencyIsTheResidencyWeightedAverageOfWorkingStates() {
        // P2 for 3 and P4 for 1. OFF is not a frequency: (486e6 * 3 + 778e6) / 4 = 559e6.
        let frequency = EnergyModelDecoder.gpuFrequency(
            states: [
                GPUFrequencyState(subgroup: "GPU Performance States", name: "OFF", residency: 100),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P2", residency: 3),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P4", residency: 1),
            ],
            table: m1ProVoltageTable()
        )
        XCTAssertEqual(frequency, .hertz(559_000_000))
    }

    func testWholeIntervalOffShowsIdleRatherThanZeroOrMissing() {
        let frequency = EnergyModelDecoder.gpuFrequency(
            states: [
                GPUFrequencyState(subgroup: "GPU Performance States", name: "OFF", residency: 40),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P1", residency: 0),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P99", residency: 0),
            ],
            table: nil
        )
        XCTAssertEqual(frequency, .idle)
        XCTAssertEqual(EnergyModelCopy.gpuFrequencyLine(frequency), "GPU 频率 · 空闲")
        XCTAssertEqual(EnergyModelCopy.gpuFrequencyReading(frequency), "空闲")
        XCTAssertFalse(EnergyModelCopy.gpuFrequencyLine(frequency).contains("—"))
        XCTAssertFalse(EnergyModelCopy.gpuFrequencyLine(frequency).contains("0"))
        XCTAssertFalse(EnergyModelCopy.gpuFrequencyReading(frequency).contains("—"))
        XCTAssertFalse(EnergyModelCopy.gpuFrequencyReading(frequency).contains("0"))
    }

    func testMissingTableOrUnmappedGearStaysMissing() {
        let working = GPUFrequencyState(subgroup: "GPU Performance States", name: "P2", residency: 3)
        let unknown = GPUFrequencyState(subgroup: "GPU Performance States", name: "FAST", residency: 1)
        XCTAssertEqual(
            EnergyModelDecoder.gpuFrequency(states: [working, unknown], table: m1ProVoltageTable()),
            .missing
        )
        let beyondTable = GPUFrequencyState(subgroup: "GPU Performance States", name: "P7", residency: 1)
        XCTAssertEqual(
            EnergyModelDecoder.gpuFrequency(states: [working, beyondTable], table: m1ProVoltageTable()),
            .missing
        )
        XCTAssertEqual(EnergyModelDecoder.gpuFrequency(states: [working], table: nil), .missing)
        let offAndWorking = [
            GPUFrequencyState(subgroup: "GPU Performance States", name: "OFF", residency: 50),
            working,
        ]
        XCTAssertEqual(EnergyModelDecoder.gpuFrequency(states: offAndWorking, table: nil), .missing)
        XCTAssertEqual(EnergyModelCopy.gpuFrequencyLine(.missing), "GPU 频率 · —")
        XCTAssertEqual(EnergyModelCopy.gpuFrequencyReading(.missing), "—")
        XCTAssertNotEqual(
            EnergyModelCopy.gpuFrequencyLine(.missing),
            EnergyModelCopy.gpuFrequencyLine(.idle)
        )
        XCTAssertNotEqual(
            EnergyModelCopy.gpuFrequencyReading(.missing),
            EnergyModelCopy.gpuFrequencyReading(.idle)
        )
    }

    func testGPUFrequencyWithoutASampleDeltaStaysMissing() {
        XCTAssertEqual(EnergyModelDecoder.gpuFrequency(states: [], table: m1ProVoltageTable()), .missing)
        let untouched = [
            GPUFrequencyState(subgroup: "GPU Performance States", name: "OFF", residency: 0),
            GPUFrequencyState(subgroup: "GPU Performance States", name: "P1", residency: 0),
        ]
        XCTAssertEqual(
            EnergyModelDecoder.gpuFrequency(states: untouched, table: m1ProVoltageTable()),
            .missing
        )
    }

    func testGPUFrequencyIgnoresStatesOutsidePerformanceStates() {
        // Same 559 MHz average. Another subgroup's P6 must not move it.
        let frequency = EnergyModelDecoder.gpuFrequency(
            states: [
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P2", residency: 3),
                GPUFrequencyState(subgroup: "GPU Performance States", name: "P4", residency: 1),
                GPUFrequencyState(subgroup: "GPU SW States", name: "P6", residency: 100),
            ],
            table: m1ProVoltageTable()
        )
        XCTAssertEqual(frequency, .hertz(559_000_000))
    }

    func testDisplayedWattsAndFrequencyKeepMissingAndRealZeroApart() {
        XCTAssertEqual(EnergyModelCopy.gpuPowerLine(watts: nil), "GPU 功耗 · —")
        XCTAssertFalse(EnergyModelCopy.gpuPowerLine(watts: nil).contains("0"))
        XCTAssertEqual(EnergyModelCopy.gpuPowerLine(watts: 0), "GPU 功耗 · 0.0 W")
        XCTAssertEqual(EnergyModelCopy.gpuPowerLine(watts: 1.5), "GPU 功耗 · 1.5 W")
        XCTAssertEqual(EnergyModelCopy.gpuPowerLine(watts: .infinity), "GPU 功耗 · —")
        XCTAssertEqual(EnergyModelCopy.gpuFrequencyLine(hertz: nil), "GPU 频率 · —")
        XCTAssertFalse(EnergyModelCopy.gpuFrequencyLine(hertz: nil).contains("0"))
        XCTAssertEqual(EnergyModelCopy.gpuFrequencyLine(hertz: 0), "GPU 频率 · 0.00 GHz")
        XCTAssertEqual(EnergyModelCopy.gpuFrequencyLine(hertz: 2_400_000_000), "GPU 频率 · 2.40 GHz")
        XCTAssertEqual(EnergyModelCopy.gpuFrequencyLine(hertz: .nan), "GPU 频率 · —")
        XCTAssertEqual(EnergyModelCopy.aneLine(watts: nil), "ANE 功耗 · —")
        XCTAssertEqual(EnergyModelCopy.aneLine(watts: 1.5), "ANE 功耗 · 1.5 W")
        XCTAssertEqual(EnergyModelCopy.dramLine(watts: 0), "DRAM 功耗 · 0.0 W")
        XCTAssertEqual(EnergyModelCopy.dramLine(watts: nil), "DRAM 功耗 · —")
    }

    func testCPUClusterFrequencyStaysOnTheDominantNamedState() {
        XCTAssertEqual(
            cpuDominantHertz([
                (name: "3.2 GHz", residency: 10),
                (name: "2400 MHz", residency: 40),
            ]),
            2_400_000_000
        )
        XCTAssertNil(cpuDominantHertz([(name: "P1", residency: 90)]))
        XCTAssertNil(EnergyModelDecoder.hertz(fromStateName: "P6"))
    }

    func testGPUFrequencyReaderSuppliesThePerformanceSubgroupAndRegistryBytes() throws {
        let reader = try repoText("Pulse/Sampling/HostEnergyModelReader.swift")
        XCTAssertTrue(reader.contains("\"GPU Performance States\""))
        XCTAssertTrue(reader.contains("EnergyModelDecoder.gpuFrequency"))
        XCTAssertTrue(reader.contains("voltageStates9Bytes"))
        XCTAssertFalse(reader.contains("dominantHertz"))
        XCTAssertFalse(reader.contains("IOServiceOpen"))
        XCTAssertFalse(reader.contains("import IOKit"))
        XCTAssertTrue(reader.contains("hertz(fromStateName:"))

        let registry = try repoText("Pulse/Sampling/HostEnergyModelReader+VoltageStates.swift")
        XCTAssertTrue(registry.contains("\"voltage-states9\""))
        XCTAssertTrue(registry.contains("\"pmgr\""))
        XCTAssertTrue(registry.contains("IORegistryEntryCreateCFProperties"))
        XCTAssertFalse(registry.contains("IOServiceOpen"))

        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("\"Sampling/HostEnergyModelReader+VoltageStates.swift\""))
        XCTAssertTrue(parts[1].contains("\"Models/VoltageStates9.swift\""))
        XCTAssertFalse(parts[1].contains("HostEnergyModelReader"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("VoltageStates9.swift in Sources"))
        XCTAssertTrue(project.contains("HostEnergyModelReader+VoltageStates.swift in Sources"))
    }

    func testPagesReadGPUAndMachineRailsOnlyWhileVisible() throws {
        let call = "sampler.sample(readChipTemperature: selectedPage == .machine, readEnergyModel: selectedPage == .cpu, readGPUEnergy: selectedPage == .gpu, readMachineRails: selectedPage == .energy)"
        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(vm.contains(call))
        XCTAssertEqual(occurrenceCount(of: "selectedPage == .gpu", in: vm), 1)
        XCTAssertFalse(vm.contains("readGPUEnergy: readsGPUShare"))
        XCTAssertFalse(vm.contains("readMachineRails: readsGPUShare"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("selectedPage == .gpu"))
        XCTAssertFalse(sampler.contains("selectedPage == .energy"))
        XCTAssertFalse(sampler.contains("readGPU:"))
        XCTAssertTrue(sampler.contains("gpu: readGPUEnergy"))
        XCTAssertTrue(sampler.contains("rails: readMachineRails"))
        XCTAssertTrue(sampler.contains("cpu: readEnergyModel"))

        let reader = try repoText("Pulse/Sampling/HostEnergyModelReader.swift")
        XCTAssertTrue(reader.contains("\"GPU Stats\""))
        XCTAssertTrue(reader.contains("cumulative: 0"))
        XCTAssertFalse(reader.contains("IOServiceOpen"))
        XCTAssertFalse(reader.contains("import IOKit"))
        let gpuReader = try repoText("Pulse/Sampling/HostGPUReader.swift")
        XCTAssertFalse(gpuReader.contains("Energy Model"))
        XCTAssertFalse(gpuReader.contains("IOServiceOpen"))

        let selection = try repoText("Pulse/Models/DashboardCore+Selection.swift")
        XCTAssertTrue(selection.contains(".setGPUSampling(on: true)"))
        XCTAssertFalse(selection.contains("readGPUEnergy"))

        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let column = dashboard.components(separatedBy: "private var energyResourceColumn")[1]
            .components(separatedBy: "private var resourceColumn")[0]
        XCTAssertTrue(column.contains("EnergyModelRailsView()"))
        let batteryIf = try braceBody(after: "if vm.energyBatteryCard != nil", in: column)
        XCTAssertTrue(batteryIf.contains("EnergyBatteryCardView()"))
        XCTAssertFalse(batteryIf.contains("EnergyModelRailsView"))
        XCTAssertLessThan(
            column.range(of: "EnergyBatteryCardView()")!.lowerBound,
            column.range(of: "EnergyHistoryChart()")!.lowerBound
        )

        let overview = try repoText("Pulse/Views/GPUOverviewSection.swift")
        XCTAssertTrue(overview.contains("vm.gpu.powerLine"))
        XCTAssertFalse(overview.contains("Text(EnergyModelCopy.gpuFrequencyLine"))
        XCTAssertFalse(overview.contains("dominantHertz"))
        let frequencyCall = "vm.gpu.frequencyLine"
        XCTAssertEqual(occurrenceCount(of: frequencyCall, in: overview), 1)
        let label = try braceBody(after: "private var accessibilityLabel", in: overview)
        XCTAssertTrue(label.contains(frequencyCall))
        let readings = try repoText("Pulse/Views/GPUOverviewSection+Readings.swift")
        let cardCall = "vm.gpu.frequencyText"
        XCTAssertEqual(occurrenceCount(of: cardCall, in: readings), 1)
        let state = try repoText("Pulse/Models/GPUState.swift")
        XCTAssertTrue(state.contains("EnergyModelCopy.gpuPowerLine(watts: watts)"))
        XCTAssertTrue(state.contains("EnergyModelCopy.gpuFrequencyLine(frequency)"))
        XCTAssertTrue(state.contains("EnergyModelCopy.gpuFrequencyReading(frequency)"))
        XCTAssertTrue(state.contains("frequency = energy?.gpuFrequency ?? .missing"))
        XCTAssertFalse(readings.contains("gpuHertz"))
        XCTAssertFalse(readings.contains("dominantHertz"))

        for relative in [
            "Pulse/MenuBar/MenuBarStatus.swift",
            "Pulse/MenuBar/MenuBarPopoverView.swift",
            "Pulse/Models/MenuBarReading.swift",
            "Pulse/Models/SnapshotExport.swift",
            "Pulse/Views/ProcessTablePane.swift",
            "Pulse/Views/EnergyProcessTable.swift",
        ] {
            let text = try repoText(relative)
            for token in ["GPU 功耗", "GPU 频率", "ANE 功耗", "DRAM 功耗"] {
                XCTAssertFalse(text.contains(token), "\(relative) \(token)")
            }
        }
    }

    /// CPU clusters still take the state that spent the most time, then parse its name.
    /// GPU frequency no longer uses this rule.
    private func cpuDominantHertz(_ states: [(name: String, residency: Int64)]) -> Double? {
        var winner: (name: String, residency: Int64)?
        for state in states where state.residency > 0 {
            if state.residency > (winner?.residency ?? -1) {
                winner = state
            }
        }
        guard let winner else { return nil }
        return EnergyModelDecoder.hertz(fromStateName: winner.name)
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

    private func pair(
        _ name: String,
        _ unit: String,
        _ previous: Double,
        _ current: Double
    ) -> (previous: EnergyModelChannel, current: EnergyModelChannel) {
        (
            previous: EnergyModelChannel(name: name, unit: unit, cumulative: previous),
            current: EnergyModelChannel(name: name, unit: unit, cumulative: current)
        )
    }

    private func repoText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw EnergyModelSourceError.missing(needle) }
        var depth = 0
        var cursor = brace
        while cursor < source.endIndex {
            if source[cursor] == "{" { depth += 1 }
            if source[cursor] == "}" {
                depth -= 1
                if depth == 0 { return String(source[brace...cursor]) }
            }
            cursor = source.index(after: cursor)
        }
        throw EnergyModelSourceError.missing(needle)
    }
}

private enum EnergyModelSourceError: Error {
    case missing(String)
}
