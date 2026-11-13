import XCTest
@testable import SamplingCore

/// Lifetime max footprint shown in the memory detail. Forged bytes and uids only.
final class MemoryPeakTests: XCTestCase {
    func testOwnUserPeakUsesTheMemoryByteFormat() {
        XCTAssertEqual(MemoryPeakText.title, "内存占用峰值")
        XCTAssertEqual(
            MemoryPeakText.string(bytes: 1_073_741_824, rowUid: 501, selfUid: 501),
            "1 GB"
        )
        XCTAssertEqual(
            MemoryPeakText.string(bytes: 0, rowUid: 501, selfUid: 501),
            "0 字节"
        )
        XCTAssertEqual(
            MemoryPeakText.string(bytes: 2_097_152, rowUid: 0, selfUid: 0),
            "2 MB"
        )
    }

    func testMissingPeakStaysDash() {
        XCTAssertEqual(
            MemoryPeakText.string(bytes: nil, rowUid: 501, selfUid: 501),
            "—"
        )
    }

    func testOtherUserPeakStaysDash() {
        XCTAssertEqual(
            MemoryPeakText.string(bytes: 1_073_741_824, rowUid: 0, selfUid: 501),
            "—"
        )
        XCTAssertEqual(
            MemoryPeakText.string(bytes: 0, rowUid: 501, selfUid: 0),
            "—"
        )
        XCTAssertEqual(
            MemoryPeakText.string(bytes: 1_073_741_824, rowUid: nil, selfUid: 501),
            "—"
        )
        XCTAssertEqual(
            MemoryPeakText.string(bytes: nil, rowUid: 0, selfUid: 501),
            "—"
        )
    }

    func testGroupedRowsKeepTheLeadPeak() {
        let heavy = peakRow(pid: 2, memory: 100, userID: 501, peak: 4_096)
        let light = peakRow(pid: 9, memory: 10, userID: 0, peak: 9_999)
        let missing = peakRow(pid: 4, memory: 200, userID: 501, peak: nil)
        let grouped = AppGroupProjection.combine([light, heavy])
        XCTAssertEqual(grouped.pid, 2)
        XCTAssertEqual(grouped.lifetimeMaxFootprintBytes, 4_096)
        XCTAssertEqual(grouped.userID, 501)

        let leadMissing = AppGroupProjection.combine([heavy, missing])
        XCTAssertEqual(leadMissing.pid, 4)
        XCTAssertNil(leadMissing.lifetimeMaxFootprintBytes)

        let energy = EnergyPage.display(rows: [light, heavy], windowRates: [:], grouped: true)
        XCTAssertEqual(energy.rows.map(\.pid), [2])
        XCTAssertEqual(energy.rows.first?.lifetimeMaxFootprintBytes, 4_096)
    }

    private func peakRow(pid: Int32, memory: UInt64, userID: UInt32, peak: UInt64?) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: "Mail",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: memory,
            threadCount: 1,
            userID: userID,
            lifetimeMaxFootprintBytes: peak
        )
    }
}
