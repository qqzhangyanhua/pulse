import XCTest
@testable import SamplingCore

final class NettopDecoderTests: XCTestCase {
    func testNormalRowsDecodePidAndKeepARealZero() {
        let sample = """
        ,bytes_in,bytes_out
        Safari.42,1536,512
        kernel_task.0,0,128
        com.apple.WebKit.99,100,0
        """
        let counts = NettopDecoder.decode(sample)
        guard case .counts(let rows) = counts else {
            return XCTFail("expected counts, got \(counts)")
        }
        XCTAssertEqual(rows[42], ProcessNetworkByteCounts(downloadBytes: 1536, uploadBytes: 512))
        XCTAssertEqual(rows[0], ProcessNetworkByteCounts(downloadBytes: 0, uploadBytes: 128))
        XCTAssertEqual(rows[99], ProcessNetworkByteCounts(downloadBytes: 100, uploadBytes: 0))
    }

    func testMalformedLinesAreSkippedAndDoNotBecomeZero() {
        let sample = """
        ,bytes_in,bytes_out
        not-a-process,10,20
        Safari.42,1536,512
        ,,,
        Google Chrome H.487,8,9
        """
        guard case .counts(let rows) = NettopDecoder.decode(sample) else {
            return XCTFail("expected counts")
        }
        XCTAssertNil(rows.values.first { $0.downloadBytes == 10 && $0.uploadBytes == 20 })
        XCTAssertEqual(rows[42], ProcessNetworkByteCounts(downloadBytes: 1536, uploadBytes: 512))
        XCTAssertEqual(rows[487], ProcessNetworkByteCounts(downloadBytes: 8, uploadBytes: 9))
        XCTAssertEqual(rows.count, 2)
    }

    func testMissingOrNonNumericFieldsStayNilInsteadOfZero() {
        let sample = """
        ,bytes_in,bytes_out
        Safari.42,1536
        Mail.7,nope,20
        Notes.8,,40
        """
        guard case .counts(let rows) = NettopDecoder.decode(sample) else {
            return XCTFail("expected counts")
        }
        XCTAssertEqual(rows[42], ProcessNetworkByteCounts(downloadBytes: 1536, uploadBytes: nil))
        XCTAssertEqual(rows[7], ProcessNetworkByteCounts(downloadBytes: nil, uploadBytes: 20))
        XCTAssertEqual(rows[8], ProcessNetworkByteCounts(downloadBytes: nil, uploadBytes: 40))
        XCTAssertNotEqual(rows[42]?.uploadBytes, 0)
        XCTAssertNotEqual(rows[7]?.downloadBytes, 0)
        XCTAssertNotEqual(rows[8]?.downloadBytes, 0)
    }

    func testHeaderNamesChooseTheColumnsInsteadOfPosition() {
        let sample = """
        ,bytes_out,bytes_in
        Safari.42,9,100
        """
        guard case .counts(let rows) = NettopDecoder.decode(sample) else {
            return XCTFail("expected counts")
        }
        XCTAssertEqual(rows[42], ProcessNetworkByteCounts(downloadBytes: 100, uploadBytes: 9))
    }

    func testASampleWithoutByteColumnsIsUnreadable() {
        let sample = """
        time,state
        Safari.42,Established
        """
        XCTAssertEqual(NettopDecoder.decode(sample), .unreadable)
        XCTAssertEqual(NettopDecoder.decode(""), .unreadable)
        XCTAssertEqual(NettopDecoder.decode("Safari.42,1,2"), .unreadable)
    }

    func testLaterRowForTheSamePidReplacesTheEarlierOne() {
        let sample = """
        ,bytes_in,bytes_out
        Safari.42,10,1
        Safari.42,20,2
        """
        guard case .counts(let rows) = NettopDecoder.decode(sample) else {
            return XCTFail("expected counts")
        }
        XCTAssertEqual(rows[42], ProcessNetworkByteCounts(downloadBytes: 20, uploadBytes: 2))
    }

    func testRateUsesTheElapsedIntervalAndKeepsAZeroDelta() {
        let previous: [Int32: ProcessNetworkByteCounts] = [
            42: ProcessNetworkByteCounts(downloadBytes: 1000, uploadBytes: 50),
            7: ProcessNetworkByteCounts(downloadBytes: 10, uploadBytes: 10),
        ]
        let current: [Int32: ProcessNetworkByteCounts] = [
            42: ProcessNetworkByteCounts(downloadBytes: 3000, uploadBytes: 50),
            7: ProcessNetworkByteCounts(downloadBytes: 10, uploadBytes: 12),
        ]
        let rates = ProcessNetworkRateMath.perSecond(previous: previous, current: current, elapsedSeconds: 2)
        XCTAssertEqual(rates?[42]?.downloadBytesPerSecond, 1000)
        XCTAssertEqual(rates?[42]?.uploadBytesPerSecond, 0)
        XCTAssertEqual(rates?[7]?.downloadBytesPerSecond, 0)
        XCTAssertEqual(rates?[7]?.uploadBytesPerSecond, 1)
    }

    func testFirstSightingDecreasedCounterAndBadIntervalStayMissing() {
        let previous: [Int32: ProcessNetworkByteCounts] = [
            42: ProcessNetworkByteCounts(downloadBytes: 1000, uploadBytes: nil),
        ]
        let current: [Int32: ProcessNetworkByteCounts] = [
            42: ProcessNetworkByteCounts(downloadBytes: 900, uploadBytes: 4),
            3: ProcessNetworkByteCounts(downloadBytes: 80, uploadBytes: 0),
        ]
        let rates = ProcessNetworkRateMath.perSecond(previous: previous, current: current, elapsedSeconds: 2)
        XCTAssertNil(rates?[42]?.downloadBytesPerSecond)
        XCTAssertNil(rates?[42]?.uploadBytesPerSecond)
        XCTAssertNil(rates?[3]?.downloadBytesPerSecond)
        XCTAssertNil(rates?[3]?.uploadBytesPerSecond)
        XCTAssertNil(ProcessNetworkRateMath.perSecond(previous: previous, current: current, elapsedSeconds: 0))
        XCTAssertNil(ProcessNetworkRateMath.perSecond(previous: previous, current: current, elapsedSeconds: -1))
        XCTAssertNil(
            ProcessNetworkRateMath.perSecond(
                previous: previous,
                current: current,
                elapsedSeconds: Double.nan
            )
        )
    }

    func testFramerClosesASampleOnABlankLineOrTheNextHeader() {
        var framer = NettopSampleFramer()
        XCTAssertNil(framer.append(",bytes_in,bytes_out"))
        XCTAssertNil(framer.append("Safari.42,100,50"))
        let blank = framer.append("")
        XCTAssertEqual(blank, ",bytes_in,bytes_out\nSafari.42,100,50")

        XCTAssertNil(framer.append(",bytes_in,bytes_out"))
        XCTAssertNil(framer.append("Safari.42,200,50"))
        let nextHeader = framer.append(",bytes_in,bytes_out")
        XCTAssertEqual(nextHeader, ",bytes_in,bytes_out\nSafari.42,200,50")
        XCTAssertNil(framer.append("Mail.7,1,2"))
        XCTAssertEqual(framer.append(""), ",bytes_in,bytes_out\nMail.7,1,2")
    }

    func testCommandIsTheFixedNettopPathAndNotAShell() {
        XCTAssertEqual(NettopCommand.executablePath, "/usr/bin/nettop")
        XCTAssertEqual(
            NettopCommand.arguments,
            ["-P", "-x", "-c", "-L", "0", "-s", "1", "-n", "-J", "bytes_in,bytes_out"]
        )
        XCTAssertFalse(NettopCommand.arguments.contains("/bin/sh"))
        XCTAssertFalse(NettopCommand.arguments.contains("-d"))
        XCTAssertTrue(NettopCommand.arguments.contains("-x"))
        XCTAssertTrue(NettopCommand.arguments.contains("-s"))
        XCTAssertTrue(NettopCommand.arguments.contains("1"))
    }

    func testMissingRatesSortLastInBothDirectionsAndARealZeroDoesNot() {
        let rows = [
            process(1, "Missing"),
            process(2, "Idle"),
            process(3, "Busy"),
        ]
        let rates: [Int32: ProcessNetworkRate] = [
            2: ProcessNetworkRate(downloadBytesPerSecond: 0, uploadBytesPerSecond: 5),
            3: ProcessNetworkRate(downloadBytesPerSecond: 1500, uploadBytesPerSecond: 0),
        ]
        let downloadAscending = ProcessNetworkTable.ordered(
            rows,
            rates: rates,
            sort: ProcessTableSort(column: .networkDownload, descending: false)
        )
        let downloadDescending = ProcessNetworkTable.ordered(
            rows,
            rates: rates,
            sort: ProcessTableSort(column: .networkDownload, descending: true)
        )
        XCTAssertEqual(downloadAscending.map(\.pid), [2, 3, 1])
        XCTAssertEqual(downloadDescending.map(\.pid), [3, 2, 1])

        let uploadAscending = ProcessNetworkTable.ordered(
            rows,
            rates: rates,
            sort: ProcessTableSort(column: .networkUpload, descending: false)
        )
        let uploadDescending = ProcessNetworkTable.ordered(
            rows,
            rates: rates,
            sort: ProcessTableSort(column: .networkUpload, descending: true)
        )
        XCTAssertEqual(uploadAscending.map(\.pid), [3, 2, 1])
        XCTAssertEqual(uploadDescending.map(\.pid), [2, 3, 1])
    }

    func testEqualRatesAndSharedNilsBreakTiesByPidAscending() {
        let rows = [process(30, "Same"), process(10, "Same"), process(20, "Gone")]
        let rates: [Int32: ProcessNetworkRate] = [
            30: ProcessNetworkRate(downloadBytesPerSecond: 4, uploadBytesPerSecond: nil),
            10: ProcessNetworkRate(downloadBytesPerSecond: 4, uploadBytesPerSecond: nil),
        ]
        let descending = ProcessNetworkTable.ordered(
            rows,
            rates: rates,
            sort: ProcessTableSort(column: .networkDownload, descending: true)
        )
        let ascending = ProcessNetworkTable.ordered(
            rows,
            rates: rates,
            sort: ProcessTableSort(column: .networkUpload, descending: false)
        )
        XCTAssertEqual(descending.map(\.pid), [10, 30, 20])
        XCTAssertEqual(ascending.map(\.pid), [10, 20, 30])
    }

    func testNameSortDoesNotSinkAMissingNetworkRate() {
        let rows = [process(2, "Beta"), process(1, "Alpha")]
        let rates: [Int32: ProcessNetworkRate] = [
            2: ProcessNetworkRate(downloadBytesPerSecond: 9, uploadBytesPerSecond: 9),
        ]
        let ascending = ProcessNetworkTable.ordered(
            rows,
            rates: rates,
            sort: ProcessTableSort(column: .name, descending: false)
        )
        let descending = ProcessNetworkTable.ordered(
            rows,
            rates: rates,
            sort: ProcessTableSort(column: .name, descending: true)
        )
        XCTAssertEqual(ascending.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(descending.map(\.name), ["Beta", "Alpha"])
    }

    func testReaderUsesTheFixedCommandAndIsNotTheSampler() throws {
        let reader = try repoText("Pulse/Sampling/NettopReader.swift")
        XCTAssertTrue(reader.contains("NettopCommand.executablePath"))
        XCTAssertTrue(reader.contains("NettopCommand.arguments"))
        XCTAssertTrue(reader.contains("Pipe()"))
        XCTAssertFalse(reader.contains("nullDevice"))
        XCTAssertFalse(reader.contains("/bin/sh"))
        XCTAssertTrue(reader.contains("SIGKILL"))
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("nettop"))
        XCTAssertFalse(sampler.contains("NettopReader"))
        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM+NetworkRates.swift")
        XCTAssertFalse(vm.contains("@MainActor"))
        XCTAssertFalse(vm.contains("@Published"))
        let delegate = try repoText("Pulse/MenuBar/PulseAppDelegate.swift")
        XCTAssertTrue(delegate.contains("stopProcessNetworkWatch()"))
        let package = try repoText("Package.swift")
        XCTAssertEqual(package.components(separatedBy: "\"Models/NettopDecoder.swift\"").count - 1, 1)
        XCTAssertEqual(package.components(separatedBy: "\"Sampling/NettopReader.swift\"").count - 1, 1)
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("NettopDecoder.swift in Sources"))
        XCTAssertTrue(project.contains("NettopReader.swift in Sources"))
        XCTAssertTrue(project.contains("MemoryDashboardVM+NetworkRates.swift in Sources"))
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

    private func process(_ pid: Int32, _ name: String) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 1,
            memoryBytes: 1,
            threadCount: 1
        )
    }
}
