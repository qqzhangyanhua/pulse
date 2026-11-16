import XCTest
@testable import SamplingCore

/// Display card projection. Readings in, row text out. No CoreGraphics.
final class GPUDisplayTests: XCTestCase {
    func testBuiltInScreensStayAheadOfExternalScreens() {
        let card = GPUDisplayProjection.present([
            reading(builtIn: false, width: 1920, height: 1080, hertz: 60),
            reading(builtIn: true, width: 3024, height: 1964, hertz: 120),
            reading(builtIn: true, width: 1512, height: 982, hertz: 60),
            reading(builtIn: false, width: 2560, height: 1440, hertz: 144),
        ])

        XCTAssertFalse(card.showsMissing)
        XCTAssertEqual(card.rows.map(\.kindText), ["内建", "内建", "外接", "外接"])
        XCTAssertEqual(card.rows.map(\.resolutionText), [
            "3024 × 1964",
            "1512 × 982",
            "1920 × 1080",
            "2560 × 1440",
        ])
        XCTAssertEqual(card.rows.map(\.refreshText), ["120 Hz", "60 Hz", "60 Hz", "144 Hz"])
    }

    func testZeroHertzUsesTheScreenMaximumAndARealRateDoesNot() {
        let variable = GPUDisplayProjection.present([
            reading(builtIn: true, width: 3024, height: 1964, hertz: 0, maximumFramesPerSecond: 120),
        ])
        XCTAssertEqual(variable.rows.map(\.refreshText), ["120 Hz"])
        XCTAssertEqual(variable.rows.map(\.kindText), ["内建"])
        XCTAssertFalse(variable.showsMissing)

        let fixed = GPUDisplayProjection.present([
            reading(builtIn: false, width: 1920, height: 1080, hertz: 60, maximumFramesPerSecond: 120),
        ])
        XCTAssertEqual(fixed.rows.map(\.refreshText), ["60 Hz"])
        XCTAssertEqual(fixed.rows.map(\.resolutionText), ["1920 × 1080"])
    }

    func testFractionalRefreshKeepsTheModeRate() {
        let card = GPUDisplayProjection.present([
            reading(builtIn: false, width: 1920, height: 1080, hertz: 59.94, maximumFramesPerSecond: 60),
        ])
        XCTAssertEqual(card.rows.map(\.refreshText), ["59.94 Hz"])
    }

    func testZeroHertzWithoutAMaximumIsADashNotZero() {
        let missingMaximum = GPUDisplayProjection.present([
            reading(builtIn: true, width: 3024, height: 1964, hertz: 0, maximumFramesPerSecond: nil),
        ])
        XCTAssertEqual(missingMaximum.rows.count, 1)
        XCTAssertEqual(missingMaximum.rows[0].refreshText, "—")
        XCTAssertEqual(missingMaximum.rows[0].resolutionText, "3024 × 1964")
        XCTAssertFalse(missingMaximum.showsMissing)

        let zeroMaximum = GPUDisplayProjection.present([
            reading(builtIn: true, width: 3024, height: 1964, hertz: 0, maximumFramesPerSecond: 0),
        ])
        XCTAssertEqual(zeroMaximum.rows[0].refreshText, "—")
        XCTAssertNotEqual(zeroMaximum.rows[0].refreshText, "0 Hz")
    }

    func testUnreadableRefreshStaysADashAndDoesNotUseTheMaximum() {
        let missingMode = GPUDisplayProjection.present([
            reading(builtIn: false, width: 2560, height: 1440, hertz: nil, maximumFramesPerSecond: 144),
        ])
        XCTAssertEqual(missingMode.rows.map(\.kindText), ["外接"])
        XCTAssertEqual(missingMode.rows.map(\.refreshText), ["—"])

        let notANumber = GPUDisplayProjection.present([
            reading(builtIn: true, width: 3024, height: 1964, hertz: .nan, maximumFramesPerSecond: 120),
        ])
        XCTAssertEqual(notANumber.rows.map(\.refreshText), ["—"])
        XCTAssertNotEqual(notANumber.rows[0].refreshText, "120 Hz")
    }

    func testNoScreenInfoIsADashForTheWholeCard() {
        let absent = GPUDisplayProjection.present(nil)
        XCTAssertTrue(absent.showsMissing)
        XCTAssertTrue(absent.rows.isEmpty)

        let empty = GPUDisplayProjection.present([])
        XCTAssertTrue(empty.showsMissing)
        XCTAssertTrue(empty.rows.isEmpty)
        XCTAssertEqual(absent, GPUDisplaysCard.missing)
    }

    func testAScreenWithoutPixelSizeDoesNotShowZero() {
        let card = GPUDisplayProjection.present([
            reading(builtIn: true, width: 0, height: 0, hertz: 60),
        ])
        XCTAssertEqual(card.rows.map(\.resolutionText), ["—"])
        XCTAssertNotEqual(card.rows[0].resolutionText, "0 × 0")
        XCTAssertFalse(card.showsMissing)
    }

    func testNilPixelSizeStaysNilAndShowsADash() {
        let unread = reading(builtIn: true, width: nil, height: nil, hertz: nil, maximumFramesPerSecond: 120)
        XCTAssertNil(unread.pixelWidth)
        XCTAssertNil(unread.pixelHeight)
        XCTAssertNotEqual(unread.pixelWidth, 0)
        XCTAssertNotEqual(unread.pixelHeight, 0)

        let card = GPUDisplayProjection.present([unread])
        XCTAssertEqual(card.rows.map(\.resolutionText), ["—"])
        XCTAssertEqual(card.rows.map(\.refreshText), ["—"])
        XCTAssertNotEqual(card.rows[0].resolutionText, "0 × 0")
        XCTAssertFalse(card.showsMissing)

        let widthOnly = GPUDisplayProjection.present([
            reading(builtIn: false, width: nil, height: 1080, hertz: 60),
        ])
        XCTAssertEqual(widthOnly.rows.map(\.resolutionText), ["—"])
        XCTAssertNotEqual(widthOnly.rows[0].resolutionText, "0 × 1080")
    }

    func testDisplaySnapshotStaysOffTheSampleAndOffHistory() {
        var core = DashboardCore(ownPid: 1)
        XCTAssertTrue(core.gpuDisplays.showsMissing)
        XCTAssertTrue(core.gpuDisplays.rows.isEmpty)

        XCTAssertEqual(core.apply(gpuDisplays: [
            reading(builtIn: false, width: 1920, height: 1080, hertz: 60),
            reading(builtIn: true, width: 3024, height: 1964, hertz: 0, maximumFramesPerSecond: 120),
        ]), [])
        XCTAssertEqual(core.gpuDisplays.rows.map(\.kindText), ["内建", "外接"])
        XCTAssertEqual(core.gpuDisplays.rows.map(\.refreshText), ["120 Hz", "60 Hz"])
        XCTAssertNil(core.historyDraft)

        let shown = core.gpuDisplays
        _ = core.apply(
            result: Result<SampledFrame, GPUDisplayProbeError>.success(frame()),
            accepted: true,
            page: .gpu
        )
        XCTAssertEqual(core.gpuDisplays, shown)
        let draft = core.historyDraft
        XCTAssertEqual(core.apply(gpuDisplays: [
            reading(builtIn: false, width: 2560, height: 1440, hertz: 144),
        ]), [])
        XCTAssertEqual(core.historyDraft, draft)
        XCTAssertEqual(core.gpuDisplays.rows.map(\.refreshText), ["144 Hz"])

        let left = core.selectPage(.memory)
        XCTAssertTrue(left.contains(.stopGPUDisplayWatch))
        XCTAssertFalse(left.contains(.startGPUDisplayWatch))
        XCTAssertEqual(core.gpuDisplays.rows.map(\.refreshText), ["144 Hz"])

        let entered = core.selectPage(.gpu)
        XCTAssertTrue(entered.contains(.startGPUDisplayWatch))
        XCTAssertFalse(entered.contains(.stopGPUDisplayWatch))
        XCTAssertEqual(core.gpuDisplays.rows.map(\.kindText), ["外接"])
    }

    private func frame() -> SampledFrame {
        SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 1_000,
                totalBytes: 2_000,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
                pressure: .normal,
                pressureMetric: 0,
                pressureSeries: [],
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 10,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            gpuNodes: [
                GPUAcceleratorNode(statistics: [
                    GPUPageProjection.deviceUtilizationKey: .number(41),
                    GPUPageProjection.inUseSystemMemoryKey: .bytes(8_192),
                ]),
            ]
        )
    }

    private enum GPUDisplayProbeError: Error {}

    private func reading(
        builtIn: Bool,
        width: Int?,
        height: Int?,
        hertz: Double?,
        maximumFramesPerSecond: Int? = nil
    ) -> GPUDisplayReading {
        GPUDisplayReading(
            isBuiltIn: builtIn,
            pixelWidth: width,
            pixelHeight: height,
            modeRefreshHertz: hertz,
            maximumFramesPerSecond: maximumFramesPerSecond
        )
    }
}
