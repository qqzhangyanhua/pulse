import XCTest
@testable import SamplingCore

final class ProcessCPUPercentTests: XCTestCase {
    func testFirstFrameIsNil() {
        let tick = CPUTick(userTimeNs: 2_000_000, systemTimeNs: 1_000_000, date: Date(timeIntervalSince1970: 10))
        XCTAssertNil(ProcessCPUPercent.percent(previous: nil, current: tick))
    }

    func testSecondFrameUsesWallClockDelta() {
        let previous = CPUTick(userTimeNs: 0, systemTimeNs: 0, date: Date(timeIntervalSince1970: 0))
        let current = CPUTick(
            userTimeNs: 500_000_000,
            systemTimeNs: 250_000_000,
            date: Date(timeIntervalSince1970: 1.5)
        )
        let percent = ProcessCPUPercent.percent(previous: previous, current: current)
        XCTAssertEqual(percent ?? -1, 50, accuracy: 0.000_001)
    }

    func testMultiThreadLoadMayExceedOneCore() {
        let previous = CPUTick(userTimeNs: 0, systemTimeNs: 0, date: Date(timeIntervalSince1970: 0))
        let current = CPUTick(
            userTimeNs: 2_000_000_000,
            systemTimeNs: 1_000_000_000,
            date: Date(timeIntervalSince1970: 1.5)
        )
        let percent = ProcessCPUPercent.percent(previous: previous, current: current)
        XCTAssertEqual(percent ?? -1, 200, accuracy: 0.000_001)
    }

    func testCounterRegressionIsNil() {
        let previous = CPUTick(userTimeNs: 50, systemTimeNs: 10, date: Date(timeIntervalSince1970: 1))
        let current = CPUTick(userTimeNs: 40, systemTimeNs: 10, date: Date(timeIntervalSince1970: 2))
        XCTAssertNil(ProcessCPUPercent.percent(previous: previous, current: current))
    }

    func testZeroOrNegativeWallClockIsNil() {
        let date = Date(timeIntervalSince1970: 5)
        let previous = CPUTick(userTimeNs: 0, systemTimeNs: 0, date: date)
        let sameInstant = CPUTick(userTimeNs: 100, systemTimeNs: 100, date: date)
        XCTAssertNil(ProcessCPUPercent.percent(previous: previous, current: sameInstant))

        let backwards = CPUTick(userTimeNs: 100, systemTimeNs: 100, date: Date(timeIntervalSince1970: 4))
        XCTAssertNil(ProcessCPUPercent.percent(previous: previous, current: backwards))
    }
}

final class MachTimebaseTests: XCTestCase {
    func testOneToOneTimebaseReturnsTheTickAsNanoseconds() {
        XCTAssertEqual(MachTimebase.nanoseconds(tick: 0, numer: 1, denom: 1), 0)
        XCTAssertEqual(MachTimebase.nanoseconds(tick: 42, numer: 1, denom: 1), 42)
        XCTAssertEqual(MachTimebase.nanoseconds(tick: UInt64.max, numer: 1, denom: 1), UInt64.max)
    }

    func testMultiplyThenDivideKeepsTheRemainder() {
        // 4 * 125 / 3 = 166. Dividing the tick first yields 125.
        XCTAssertEqual(MachTimebase.nanoseconds(tick: 4, numer: 125, denom: 3), 166)
        XCTAssertEqual(MachTimebase.nanoseconds(tick: 2, numer: 125, denom: 3), 83)
        // Not only 125/3: 5 * 10 / 4 = 12. Dividing the tick first yields 10.
        XCTAssertEqual(MachTimebase.nanoseconds(tick: 5, numer: 10, denom: 4), 12)
    }

    func testSaturatedCoreTicksBecomeOneHundredPercentAndTwoCoresStayUncapped() throws {
        let oneCore = try XCTUnwrap(MachTimebase.nanoseconds(tick: 36_000_000, numer: 125, denom: 3))
        XCTAssertEqual(oneCore, 1_500_000_000)
        let previous = CPUTick(userTimeNs: 0, systemTimeNs: 0, date: Date(timeIntervalSince1970: 0))
        let one = CPUTick(userTimeNs: oneCore, systemTimeNs: 0, date: Date(timeIntervalSince1970: 1.5))
        XCTAssertEqual(ProcessCPUPercent.percent(previous: previous, current: one) ?? -1, 100, accuracy: 0.000_001)

        let twoCores = try XCTUnwrap(MachTimebase.nanoseconds(tick: 72_000_000, numer: 125, denom: 3))
        XCTAssertEqual(twoCores, 3_000_000_000)
        let two = CPUTick(userTimeNs: twoCores, systemTimeNs: 0, date: Date(timeIntervalSince1970: 1.5))
        XCTAssertEqual(ProcessCPUPercent.percent(previous: previous, current: two) ?? -1, 200, accuracy: 0.000_001)
    }

    func testNonPositiveFactorsAreMissing() {
        XCTAssertNil(MachTimebase.nanoseconds(tick: 10, numer: 0, denom: 1))
        XCTAssertNil(MachTimebase.nanoseconds(tick: 10, numer: 1, denom: 0))
        XCTAssertNil(MachTimebase.nanoseconds(tick: 10, numer: 0, denom: 0))
        XCTAssertNil(MachTimebase.nanoseconds(tick: 10, numer: -1, denom: 3))
        XCTAssertNil(MachTimebase.nanoseconds(tick: 10, numer: 125, denom: -3))
    }

    func testOverflowingProductIsMissingNotWrapped() {
        XCTAssertEqual(
            MachTimebase.nanoseconds(tick: UInt64.max / 2, numer: 2, denom: 1),
            UInt64.max - 1
        )
        XCTAssertNil(MachTimebase.nanoseconds(tick: UInt64.max / 2 + 1, numer: 2, denom: 1))
        XCTAssertNil(MachTimebase.nanoseconds(tick: UInt64.max, numer: 2, denom: 1))
    }
}

final class SystemCPULoadTests: XCTestCase {
    func testFirstFrameIsNil() {
        let reading = HostCPUTicks(user: 10, system: 5, idle: 80, nice: 5)
        let sample = SystemCPULoad.advance(previous: nil, reading: reading)
        XCTAssertNil(sample.percent)
        XCTAssertEqual(sample.baseline, reading)
    }

    func testBusyTicksIncludeUserSystemAndNice() {
        let previous = HostCPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let current = HostCPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        let percent = SystemCPULoad.percent(previous: previous, current: current)
        XCTAssertEqual(percent ?? -1, 75, accuracy: 0.000_001)
    }

    func testIdleDeltaIsRealZeroNotAPlaceholder() {
        let previous = HostCPUTicks(user: 10, system: 10, idle: 10, nice: 10)
        let current = HostCPUTicks(user: 10, system: 10, idle: 110, nice: 10)
        let percent = SystemCPULoad.percent(previous: previous, current: current)
        XCTAssertEqual(percent ?? -1, 0, accuracy: 0.000_001)
    }

    func testNoTickProgressIsNil() {
        let ticks = HostCPUTicks(user: 4, system: 4, idle: 4, nice: 4)
        XCTAssertNil(SystemCPULoad.percent(previous: ticks, current: ticks))
    }

    func testWrapIsNilAndDoesNotReportZero() {
        let previous = HostCPUTicks(user: 100, system: 0, idle: 0, nice: 0)
        let wrapped = HostCPUTicks(user: 1, system: 0, idle: 1, nice: 0)
        XCTAssertNil(SystemCPULoad.percent(previous: previous, current: wrapped))
    }

    func testFailedReadStaysNilAndKeepsBaseline() {
        let baseline = HostCPUTicks(user: 3, system: 1, idle: 9, nice: 0)
        let failed = SystemCPULoad.advance(previous: baseline, reading: nil)
        XCTAssertNil(failed.percent)
        XCTAssertEqual(failed.baseline, baseline)

        let next = HostCPUTicks(user: 13, system: 1, idle: 19, nice: 0)
        let recovered = SystemCPULoad.advance(previous: failed.baseline, reading: next)
        XCTAssertEqual(recovered.percent ?? -1, 50, accuracy: 0.000_001)
        XCTAssertEqual(recovered.baseline, next)
    }

    func testWrapAdvancesBaselineSoTheNextFrameCanRecover() {
        let previous = HostCPUTicks(user: 100, system: 0, idle: 0, nice: 0)
        let wrapped = HostCPUTicks(user: 1, system: 0, idle: 1, nice: 0)
        let first = SystemCPULoad.advance(previous: previous, reading: wrapped)
        XCTAssertNil(first.percent)
        XCTAssertEqual(first.baseline, wrapped)

        let later = HostCPUTicks(user: 2, system: 0, idle: 2, nice: 0)
        let second = SystemCPULoad.advance(previous: first.baseline, reading: later)
        XCTAssertEqual(second.percent ?? -1, 50, accuracy: 0.000_001)
    }
}

final class SampledFrameCPUTests: XCTestCase {
    func testFrameCarriesOptionalSystemCPU() {
        let missing = makeFrame(systemCpuPercent: nil)
        XCTAssertNil(missing.systemCpuPercent)

        let measured = makeFrame(systemCpuPercent: 12.5)
        XCTAssertEqual(measured.systemCpuPercent ?? -1, 12.5, accuracy: 0.000_001)
        XCTAssertNil(measured.busiestCorePercent)

        let core = makeFrame(systemCpuPercent: nil, busiestCorePercent: 0)
        XCTAssertEqual(core.busiestCorePercent ?? -1, 0, accuracy: 0.000_001)
    }

    func testMissingProcessCPUSortsBelowRealValuesWithoutUsingZero() {
        let row = ProcessRow(
            pid: 7,
            name: "first-frame",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 1,
            threadCount: 1
        )
        XCTAssertNil(row.cpuPercent)
        XCTAssertEqual(row.cpuSortKey, -1)
        XCTAssertLessThan(row.cpuSortKey, 0)
    }

    private func makeFrame(systemCpuPercent: Double?, busiestCorePercent: Double? = nil) -> SampledFrame {
        let now = Date(timeIntervalSince1970: 0)
        let snapshot = MemorySnapshot(
            usedBytes: 1,
            totalBytes: 4,
            breakdown: MemoryBreakdown(
                appBytes: 1,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0
            ),
            pressure: .normal,
            pressureMetric: 0.25,
            pressureSeries: [],
            capturedAt: now
        )
        return SampledFrame(
            snapshot: snapshot,
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: systemCpuPercent,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            busiestCorePercent: busiestCorePercent
        )
    }
}

final class BusiestCoreLoadTests: XCTestCase {
    func testFirstFrameIsNilAndBecomesTheBaseline() {
        let reading = [core(user: 1, idle: 1)]
        let sample = BusiestCoreLoad.advance(previous: nil, reading: reading)
        XCTAssertNil(sample.percent)
        XCTAssertEqual(sample.baseline, reading)
    }

    func testRealZeroStaysZero() {
        let previous = [core(idle: 10), core(user: 4, idle: 4)]
        let current = [core(idle: 20), core(user: 4, idle: 14)]
        let sample = BusiestCoreLoad.advance(previous: previous, reading: current)
        XCTAssertEqual(sample.percent ?? -1, 0, accuracy: 0.000_001)
        XCTAssertNotEqual(sample.percent, nil)
    }

    func testTieKeepsTheEarlierCore() throws {
        let previous = [core(), core(), core()]
        let current = [
            core(user: 40, idle: 60),
            core(user: 40, idle: 60),
            core(user: 10, idle: 90),
        ]
        let sample = BusiestCoreLoad.advance(previous: previous, reading: current)
        XCTAssertEqual(sample.percent ?? -1, 40, accuracy: 0.000_001)

        let laterWins = BusiestCoreLoad.advance(
            previous: [core(), core()],
            reading: [core(user: 10, idle: 90), core(user: 70, idle: 30)]
        )
        XCTAssertEqual(laterWins.percent ?? -1, 70, accuracy: 0.000_001)

        let source = try repoText("Pulse/Sampling/CPULoad.swift")
        let body = try slice(from: "enum BusiestCoreLoad", until: "return BusiestCoreSample(percent: best", in: source)
        XCTAssertTrue(body.contains("percent <= best"))
        XCTAssertFalse(body.contains("percent < best"))
    }

    func testInvalidCoreIsSkippedAndNotStoredAsZero() {
        let previous = [core(user: 100), core()]
        let current = [core(user: 1, idle: 1), core(user: 25, idle: 75)]
        let sample = BusiestCoreLoad.advance(previous: previous, reading: current)
        XCTAssertEqual(sample.percent ?? -1, 25, accuracy: 0.000_001)

        let allInvalid = BusiestCoreLoad.advance(
            previous: [core(user: 100), core(user: 80)],
            reading: [core(user: 1, idle: 1), core(user: 1, idle: 1)]
        )
        XCTAssertNil(allInvalid.percent)
        XCTAssertEqual(allInvalid.baseline, [core(user: 1, idle: 1), core(user: 1, idle: 1)])
    }

    func testFailedReadKeepsBaselineAndPercentStaysNil() {
        let baseline = [core(user: 3, idle: 7)]
        let failed = BusiestCoreLoad.advance(previous: baseline, reading: nil)
        XCTAssertNil(failed.percent)
        XCTAssertEqual(failed.baseline, baseline)

        let recovered = BusiestCoreLoad.advance(
            previous: failed.baseline,
            reading: [core(user: 13, idle: 17)]
        )
        XCTAssertEqual(recovered.percent ?? -1, 50, accuracy: 0.000_001)
        XCTAssertEqual(recovered.baseline, [core(user: 13, idle: 17)])
    }

    func testCoreCountChangeIsAFirstFrame() {
        let previous = [core(), core()]
        let reading = [core(user: 10, idle: 10)]
        let sample = BusiestCoreLoad.advance(previous: previous, reading: reading)
        XCTAssertNil(sample.percent)
        XCTAssertEqual(sample.baseline, reading)

        let second = BusiestCoreLoad.advance(
            previous: sample.baseline,
            reading: [core(user: 20, idle: 20)]
        )
        XCTAssertEqual(second.percent ?? -1, 50, accuracy: 0.000_001)
    }

    private func core(user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0) -> HostCPUTicks {
        HostCPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    private func repoText(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
        else {
            XCTFail("missing slice \(start)")
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }
}

/// Darwin files stay out of the package. This locks the timebase call site as text.
final class ProcessCPUTimebaseWiringTests: XCTestCase {
    func testListConvertsTicksOncePerFrameAndDoesNotStoreZero() throws {
        let reader = try repoText("Pulse/Sampling/ProcessEnumerator.swift")
        XCTAssertEqual(occurrenceCount(of: "mach_timebase_info(", in: reader), 1)
        XCTAssertEqual(occurrenceCount(of: "MachTimebase.nanoseconds(", in: reader), 2)
        XCTAssertTrue(reader.contains("let userTimeNs: UInt64?"))
        XCTAssertTrue(reader.contains("let systemTimeNs: UInt64?"))
        XCTAssertFalse(reader.contains("userTimeNs: 0"))
        XCTAssertFalse(reader.contains("systemTimeNs: 0"))
        XCTAssertFalse(reader.contains("userTimeNs: info.pti_total_user"))
        XCTAssertFalse(reader.contains("systemTimeNs: info.pti_total_system"))

        let list = try functionBody(named: "list", in: reader)
        XCTAssertEqual(occurrenceCount(of: "readMachTimebase()", in: list), 1)
        let timebaseCall = try XCTUnwrap(list.range(of: "readMachTimebase()"))
        let loop = try XCTUnwrap(list.range(of: "for index in"))
        XCTAssertLessThan(timebaseCall.lowerBound, loop.lowerBound)
        XCTAssertFalse(list.contains("mach_timebase_info("))

        let inspect = try functionBody(named: "inspect", in: reader)
        XCTAssertFalse(inspect.contains("mach_timebase_info("))
        XCTAssertFalse(inspect.contains("readMachTimebase("))
        XCTAssertTrue(inspect.contains("userTimeNs: cpu?.user"))
        XCTAssertTrue(inspect.contains("systemTimeNs: cpu?.system"))

        let convert = try functionBody(named: "convertedCPU", in: reader)
        XCTAssertTrue(convert.contains("MachTimebase.nanoseconds(tick: userTick"))
        XCTAssertTrue(convert.contains("MachTimebase.nanoseconds(tick: systemTick"))
    }

    func testSamplerFeedsConvertedNanosecondsAndLeavesHostCPUAlone() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("mach_timebase_info"))
        XCTAssertFalse(sampler.contains("MachTimebase"))
        XCTAssertFalse(sampler.contains("pti_total_user"))
        XCTAssertFalse(sampler.contains("pti_total_system"))
        XCTAssertFalse(sampler.contains("userTimeNs: 0"))
        XCTAssertFalse(sampler.contains("systemTimeNs: 0"))
        XCTAssertTrue(sampler.contains(
            "if let userTimeNs = raw.userTimeNs, let systemTimeNs = raw.systemTimeNs"
        ))
        XCTAssertTrue(sampler.contains(
            "ProcessCPUPercent.percent(previous: cpuTicks[raw.pid], current: tick)"
        ))
        XCTAssertTrue(sampler.contains("if let cpuTick"))
        XCTAssertTrue(sampler.contains("nextTicks[raw.pid] = cpuTick"))
        XCTAssertTrue(sampler.contains("cpuPercent: cpu"))
        XCTAssertTrue(sampler.contains("SystemCPULoad.advance"))
        XCTAssertTrue(sampler.contains("BusiestCoreLoad.advance"))
        XCTAssertTrue(sampler.contains("HostCPUReader.read()"))
        XCTAssertTrue(sampler.contains("HostCPUReader.readCores()"))

        let page = try repoText("Pulse/Models/CPUPage.swift")
        XCTAssertTrue(page.contains("compareDoubles(lhs.cpuSortKey, rhs.cpuSortKey)"))
        let row = try repoText("Pulse/Models/MemoryModels.swift")
        XCTAssertTrue(row.contains("var cpuSortKey: Double { cpuPercent ?? -1 }"))

        let load = try repoText("Pulse/Sampling/CPULoad.swift")
        let hostStart = try XCTUnwrap(load.range(of: "enum SystemCPULoad"))
        XCTAssertFalse(String(load[hostStart.lowerBound...]).contains("MachTimebase"))
        let host = try repoText("Pulse/Sampling/HostCPUReader.swift")
        XCTAssertFalse(host.contains("MachTimebase"))
        XCTAssertFalse(host.contains("mach_timebase_info"))
    }

    private func repoText(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "private func \(name)("]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw TimebaseWiringReadError.missing(name)
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...cursor]) }
            }
            cursor = source.index(after: cursor)
        }
        throw TimebaseWiringReadError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum TimebaseWiringReadError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
