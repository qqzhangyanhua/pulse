import XCTest
@testable import SamplingCore

final class SwapUsageTests: XCTestCase {
    func testSuccessfulReadKeepsTheReportedBytes() {
        let sample = SwapUsageSample(status: 0, returnedSize: 32, expectedSize: 32, usedBytes: 2_097_152)
        XCTAssertEqual(SwapUsage.usedBytes(from: sample), 2_097_152)
        let display = SwapUsage.display(usedBytes: 2_097_152)
        XCTAssertEqual(display.value, "2 MB")
        XCTAssertEqual(display.caption, "已用")
    }

    func testSuccessfulZeroStaysZeroBytes() {
        let sample = SwapUsageSample(status: 0, returnedSize: 32, expectedSize: 32, usedBytes: 0)
        XCTAssertEqual(SwapUsage.usedBytes(from: sample), 0)
        let display = SwapUsage.display(usedBytes: 0)
        XCTAssertEqual(display.value, "0 字节")
        XCTAssertEqual(display.caption, "已用")
        XCTAssertNotEqual(display.caption, SwapUsage.missingCaption)
    }

    func testFailedReadAndWrongSizeStayUnsampled() {
        let failed = SwapUsageSample(status: 1, returnedSize: 32, expectedSize: 32, usedBytes: 99)
        let short = SwapUsageSample(status: 0, returnedSize: 24, expectedSize: 32, usedBytes: 99)
        let empty = SwapUsageSample(status: 0, returnedSize: 0, expectedSize: 0, usedBytes: 0)
        XCTAssertNil(SwapUsage.usedBytes(from: failed))
        XCTAssertNil(SwapUsage.usedBytes(from: short))
        XCTAssertNil(SwapUsage.usedBytes(from: empty))
        let display = SwapUsage.display(usedBytes: nil)
        XCTAssertEqual(display.value, "—")
        XCTAssertEqual(display.caption, "未采样")
    }

    func testReadyOverviewReadsTheSnapshotAndSamplerKeepsSwapOffTheHostError() throws {
        let overview = try source("Pulse/Views/OverviewSection.swift")
        XCTAssertTrue(overview.contains("SwapUsage.display(usedBytes: snapshot.swapUsedBytes)"))
        XCTAssertFalse(overview.contains("value: \"—\""))
        XCTAssertFalse(overview.contains("caption: \"未采样\""))

        let sampler = try source("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(sampler.contains("let swapUsedBytes = SwapUsageReader.read()"))
        XCTAssertTrue(sampler.contains("swapUsedBytes: swapUsedBytes"))
        let catchAt = try XCTUnwrap(sampler.range(of: "catch let error as HostMemoryError"))
        let swapAt = try XCTUnwrap(sampler.range(of: "SwapUsageReader.read()"))
        XCTAssertLessThan(catchAt.upperBound, swapAt.lowerBound)

        let reader = try source("Pulse/Sampling/HostMemoryReader.swift")
        let hostRead = reader.split(separator: "struct SwapUsageRaw").first.map(String.init) ?? reader
        XCTAssertFalse(hostRead.contains("vm.swapusage"))
        XCTAssertTrue(reader.contains("sysctlbyname(\"vm.swapusage\""))

        let menu = try source("Pulse/MenuBar/MenuBarStatus.swift")
        XCTAssertFalse(menu.contains("swapUsedBytes"))
        let package = try source("Package.swift")
        XCTAssertTrue(package.contains("\"Models/SwapUsage.swift\""))
        XCTAssertTrue(package.contains("\"Sampling/HostMemoryReader.swift\""))
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
