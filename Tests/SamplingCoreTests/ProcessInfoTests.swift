import XCTest
@testable import SamplingCore

/// Process-info behavior: own-user check, signature labels, Rosetta, start time.
/// Forged inputs only. No SecCode, sysctl, or live pid.
final class ProcessInfoTests: XCTestCase {
    func testSameUidIsOwnUser() {
        XCTAssertTrue(isOwnUser(rowUid: 501, selfUid: 501))
        XCTAssertTrue(isOwnUser(rowUid: 0, selfUid: 0))
    }

    func testDifferentOrMissingUidIsNotOwnUser() {
        XCTAssertFalse(isOwnUser(rowUid: 501, selfUid: 0))
        XCTAssertFalse(isOwnUser(rowUid: nil, selfUid: 501))
        XCTAssertFalse(isOwnUser(rowUid: nil, selfUid: 0))
    }

    func testApplePlatformLeafIsLabeledApple() {
        let facts = ProcessSigningFacts(
            status: 0,
            teamIdentifier: nil,
            certificateSummaries: [
                "Software Signing",
                "Apple Code Signing Certification Authority",
                "Apple Root CA",
            ],
            flags: 0
        )
        XCTAssertEqual(ProcessSignatureDecoder.text(for: facts), "Apple")
    }

    func testDeveloperLabelUsesTheTeamName() {
        let facts = ProcessSigningFacts(
            status: 0,
            teamIdentifier: "ABCDE12345",
            certificateSummaries: ["Developer ID Application: Northwind (ABCDE12345)"],
            flags: 0
        )
        XCTAssertEqual(ProcessSignatureDecoder.text(for: facts), "开发者：Northwind")
    }

    func testDeveloperLabelFallsBackToTheTeamIdentifier() {
        let facts = ProcessSigningFacts(
            status: 0,
            teamIdentifier: "ABCDE12345",
            certificateSummaries: [],
            flags: 0
        )
        XCTAssertEqual(ProcessSignatureDecoder.text(for: facts), "开发者：ABCDE12345")
    }

    func testUnsignedStatusStaysUnsignedEvenWithATeam() {
        let facts = ProcessSigningFacts(
            status: -67062,
            teamIdentifier: "ABCDE12345",
            certificateSummaries: ["Developer ID Application: Northwind (ABCDE12345)"],
            flags: 0
        )
        XCTAssertEqual(ProcessSignatureDecoder.text(for: facts), "未签名")
    }

    func testUnreadableSignatureStaysMissing() {
        XCTAssertEqual(ProcessSignatureDecoder.text(for: nil), "—")
        let failed = ProcessSigningFacts(
            status: -50,
            teamIdentifier: nil,
            certificateSummaries: [],
            flags: 0
        )
        XCTAssertEqual(ProcessSignatureDecoder.text(for: failed), "—")
        let unnamed = ProcessSigningFacts(
            status: 0,
            teamIdentifier: "  ",
            certificateSummaries: ["Not a signer"],
            flags: 0
        )
        XCTAssertEqual(ProcessSignatureDecoder.text(for: unnamed), "—")
    }

    func testAdhocFlagIsUnsigned() {
        let facts = ProcessSigningFacts(
            status: 0,
            teamIdentifier: "ABCDE12345",
            certificateSummaries: [],
            flags: 0x2
        )
        XCTAssertEqual(ProcessSignatureDecoder.text(for: facts), "未签名")
    }

    func testTranslatedProcessShowsRosettaLine() {
        XCTAssertEqual(ProcessRosettaDecoder.line(processFlags: 0x00020000), "通过 Rosetta 运行")
        XCTAssertEqual(ProcessRosettaDecoder.line(processFlags: 0x00020000 | 0x1), "通过 Rosetta 运行")
    }

    func testNativeOrUnreadProcessHidesRosettaLine() {
        XCTAssertNil(ProcessRosettaDecoder.line(processFlags: 0))
        XCTAssertNil(ProcessRosettaDecoder.line(processFlags: 0x00040000))
        XCTAssertNil(ProcessRosettaDecoder.line(processFlags: nil))
    }

    func testMissingStartTimeStaysDash() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(ProcessStartTimeText.string(seconds: nil, timeZone: utc), "—")
    }

    func testKnownUnixSecondFormatsInTheGivenZone() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            ProcessStartTimeText.string(seconds: 1_700_000_000, timeZone: utc),
            "2023年11月14日 22:13"
        )
    }

    func testZeroStartTimeIsARealReading() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            ProcessStartTimeText.string(seconds: 0, timeZone: utc),
            "1970年1月1日 00:00"
        )
    }

    func testBSDInfoBufferReadsParentUidAndStart() {
        var bytes = [UInt8](repeating: 0, count: 136)
        writeLE(UInt32(1), at: 16, into: &bytes)
        writeLE(UInt32(501), at: 20, into: &bytes)
        writeLE(UInt64(1_700_000_000), at: 120, into: &bytes)
        let identity = ProcessBSDInfo.identity(from: bytes)
        XCTAssertEqual(identity?.parentPid, 1)
        XCTAssertEqual(identity?.userID, 501)
        XCTAssertEqual(identity?.startTimeSeconds, 1_700_000_000)
    }

    func testShortBSDInfoBufferStaysMissing() {
        XCTAssertNil(ProcessBSDInfo.identity(from: [UInt8](repeating: 0, count: 135)))
        XCTAssertNil(ProcessBSDInfo.identity(from: []))
        XCTAssertNil(ProcessBSDInfo.identity(from: [UInt8](repeating: 0, count: 137)))
    }

    func testGroupedRowsKeepTheLeadUserAndStartTime() {
        let heavy = identityRow(pid: 2, memory: 100, userID: 501, start: 1_700_000_000)
        let light = identityRow(pid: 9, memory: 10, userID: 0, start: 10)
        let grouped = AppGroupProjection.combine([light, heavy])
        XCTAssertEqual(grouped.pid, 2)
        XCTAssertEqual(grouped.userID, 501)
        XCTAssertEqual(grouped.startTimeSeconds, 1_700_000_000)

        let energy = EnergyPage.display(rows: [light, heavy], windowRates: [:], grouped: true)
        XCTAssertEqual(energy.rows.map(\.pid), [2])
        XCTAssertEqual(energy.rows.first?.userID, 501)
        XCTAssertEqual(energy.rows.first?.startTimeSeconds, 1_700_000_000)
    }

    private func identityRow(pid: Int32, memory: UInt64, userID: UInt32, start: UInt64) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: "Mail",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: memory,
            threadCount: 1,
            userID: userID,
            startTimeSeconds: start
        )
    }

    private func writeLE<T: FixedWidthInteger>(_ value: T, at offset: Int, into bytes: inout [UInt8]) {
        var remaining = value
        for index in 0..<MemoryLayout<T>.size {
            bytes[offset + index] = UInt8(truncatingIfNeeded: remaining)
            remaining >>= 8
        }
    }
}
