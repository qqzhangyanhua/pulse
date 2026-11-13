import XCTest
@testable import SamplingCore

final class ProcessRowCopyTests: XCTestCase {
    func testMemoryLineIsNamePidAndTheTableReadings() {
        let row = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4
        )
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: row), "Safari\t42\t12.5%\t1 MB\t4")
    }

    func testGroupedMemoryLineUsesMemberCountNotTheLeadPid() {
        let grouped = AppGroupProjection.combine([
            makeRow(pid: 2, name: "Chrome", memory: 0, threads: 2, cpu: 1),
            makeRow(pid: 9, name: "Chrome", memory: 2_097_152, threads: 4, cpu: 2.5),
        ])
        XCTAssertEqual(grouped.groupedMemberCount, 2)
        XCTAssertEqual(grouped.pid, 9)
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: grouped), "Chrome\t2\t3.5%\t2 MB\t6")

        let alone = AppGroupProjection.combine([
            makeRow(pid: 4, name: "Mail", memory: 0, threads: 1, cpu: 0),
        ])
        XCTAssertEqual(alone.groupedMemberCount, 1)
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: alone), "Mail\t1\t0.0%\t0 字节\t1")
    }

    func testCPULineUsesTheCPUTableReadingsAndKeepsMissingApartFromZero() {
        let row = makeRow(pid: 42, name: "Safari", memory: 1_048_576, threads: 4, cpu: 12.5)
        XCTAssertEqual(ProcessRowCopy.line(page: .cpu, row: row), "Safari\t42\t12.5%\t1 MB\t—\t—\t4")

        let missing = makeRow(pid: 42, name: "Safari", memory: 1_048_576, threads: 4, cpu: nil)
        XCTAssertEqual(ProcessRowCopy.line(page: .cpu, row: missing), "Safari\t42\t—\t1 MB\t—\t—\t4")
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: missing), "Safari\t42\t—\t1 MB\t4")
        XCTAssertNotEqual(
            ProcessRowCopy.line(page: .cpu, row: missing),
            ProcessRowCopy.line(page: .cpu, row: makeRow(pid: 42, name: "Safari", memory: 1_048_576, threads: 4, cpu: 0))
        )
    }

    func testCPULineIncludesEnergyWattsAndIdleWakeups() {
        let row = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            energyWatts: 1.5,
            wakeupsPerSecond: 3
        )
        XCTAssertEqual(ProcessRowCopy.line(page: .cpu, row: row), "Safari\t42\t12.5%\t1 MB\t1.5 W\t3.0 次/秒\t4")
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: row), "Safari\t42\t12.5%\t1 MB\t4")

        let missing = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            energyWatts: nil,
            wakeupsPerSecond: nil
        )
        XCTAssertEqual(ProcessRowCopy.line(page: .cpu, row: missing), "Safari\t42\t12.5%\t1 MB\t—\t—\t4")

        let idle = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            energyWatts: 0,
            wakeupsPerSecond: 0
        )
        XCTAssertEqual(ProcessRowCopy.line(page: .cpu, row: idle), "Safari\t42\t12.5%\t1 MB\t0.0 W\t0.0 次/秒\t4")
        XCTAssertNotEqual(ProcessRowCopy.line(page: .cpu, row: missing), ProcessRowCopy.line(page: .cpu, row: idle))
    }

    func testDiskLineIncludesReadAndWriteAndKeepsMissingApartFromZero() {
        let row = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            diskReadBytesPerSecond: 1_024,
            diskWriteBytesPerSecond: nil
        )
        XCTAssertEqual(ProcessRowCopy.line(page: .disk, row: row), "Safari\t42\t12.5%\t1 MB\t1 KB/秒\t—\t4")

        let idle = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            diskReadBytesPerSecond: 0,
            diskWriteBytesPerSecond: 0
        )
        XCTAssertEqual(ProcessRowCopy.line(page: .disk, row: idle), "Safari\t42\t12.5%\t1 MB\t0 字节/秒\t0 字节/秒\t4")
        XCTAssertNotEqual(ProcessRowCopy.line(page: .disk, row: row), ProcessRowCopy.line(page: .disk, row: idle))
    }

    func testNetworkLineUsesEmDashForMissingRatesAndKeepsARealZero() {
        let row = makeRow(pid: 42, name: "Safari", memory: 0, threads: 1, cpu: nil)
        XCTAssertEqual(ProcessRowCopy.line(page: .network, row: row), "Safari\t42\t—\t0 字节\t—\t—\t1")
        XCTAssertFalse(ProcessRowCopy.line(page: .network, row: row).contains("0 字节/秒"))
        XCTAssertFalse(ProcessRowCopy.line(page: .network, row: row).contains("暂不可用"))
        let measured = ProcessRowCopy.line(
            page: .network,
            row: row,
            networkRate: ProcessNetworkRate(downloadBytesPerSecond: 1024, uploadBytesPerSecond: 0)
        )
        XCTAssertEqual(measured, "Safari\t42\t—\t0 字节\t1 KB/秒\t0 字节/秒\t1")
    }

    private func makeRow(
        pid: Int32,
        name: String,
        memory: UInt64,
        threads: Int,
        cpu: Double?
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: cpu,
            memoryBytes: memory,
            threadCount: threads
        )
    }
}
