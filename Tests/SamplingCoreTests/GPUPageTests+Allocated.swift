import XCTest
@testable import SamplingCore

/// Allocated bytes stay on the accelerator already chosen for in-use memory.
/// The suggested-limit bar needs both byte counts and does not rewrite the text.
extension GPUPageTests {
    func testAllocatedBytesComeFromTheSameNodeAndANonByteCountStaysMissing() {
        let page = succeed([
            node([
                "In use system memory": .bytes(100),
                "Alloc system memory": .bytes(9_000),
                "Device Utilization %": .number(11),
            ]),
            node([
                "In use system memory": .bytes(8_192),
                "Alloc system memory": .bytes(50),
                "Device Utilization %": .number(4),
            ]),
        ], at: 10)

        XCTAssertEqual(page.inUseMemoryBytes, 8_192)
        XCTAssertEqual(page.memoryText, "8 KB")
        XCTAssertEqual(page.allocatedMemoryBytes, 50)
        XCTAssertEqual(page.allocatedText, "50 字节")
        XCTAssertNotEqual(page.allocatedMemoryBytes, 9_000)
        XCTAssertEqual(page.utilizationPercent, 4)

        let borrowed = succeed([
            node([
                "In use system memory": .bytes(8_192),
                "Alloc system memory": .number(9_000),
            ]),
            node([
                "In use system memory": .bytes(100),
                "Alloc system memory": .bytes(9_000),
            ]),
        ], at: 11)
        XCTAssertEqual(borrowed.inUseMemoryBytes, 8_192)
        XCTAssertNil(borrowed.allocatedMemoryBytes)
        XCTAssertEqual(borrowed.allocatedText, "—")

        let unreadable = succeed([
            node([
                "In use system memory": .bytes(32),
                "Alloc system memory": .unreadable,
            ]),
            node([
                "Alloc system memory": .bytes(4_096),
            ]),
        ], at: 12)
        XCTAssertNil(unreadable.allocatedMemoryBytes)
        XCTAssertEqual(unreadable.allocatedText, "—")
        XCTAssertEqual(unreadable.memoryText, "32 字节")

        let zero = succeed([
            node([
                "In use system memory": .bytes(0),
                "Alloc system memory": .bytes(0),
            ]),
        ], at: 13)
        XCTAssertEqual(zero.allocatedMemoryBytes, 0)
        XCTAssertEqual(zero.allocatedText, "0 字节")
        XCTAssertEqual(zero.memoryText, "0 字节")

        XCTAssertEqual(GPUPageCopy.allocated, "已分配")
        XCTAssertEqual(GPUPageProjection.allocSystemMemoryKey, "Alloc system memory")
        XCTAssertFalse(GPUPageCopy.allocated.contains("总量"))
    }

    func testMemoryBarIsAbsentWhenEitherByteCountIsMissing() {
        let noLimit = projectAllocated(
            nodes: [node(["In use system memory": .bytes(512)])],
            limit: nil,
            at: 1
        )
        XCTAssertEqual(noLimit.inUseMemoryBytes, 512)
        XCTAssertNil(noLimit.recommendedMaxWorkingSetBytes)
        XCTAssertNil(noLimit.memoryBarFraction)
        XCTAssertEqual(noLimit.memoryText, "512 字节")
        XCTAssertEqual(noLimit.recommendedLimitText, "—")

        let noUse = projectAllocated(
            nodes: [node(["Device Utilization %": .number(10)])],
            limit: 1_024,
            at: 2
        )
        XCTAssertNil(noUse.inUseMemoryBytes)
        XCTAssertEqual(noUse.memoryText, "—")
        XCTAssertNil(noUse.memoryBarFraction)
        XCTAssertEqual(noUse.recommendedLimitText, "1 KB")

        let neither = projectAllocated(nodes: [], limit: nil, at: 3)
        XCTAssertNil(neither.memoryBarFraction)
        XCTAssertEqual(neither.memoryText, "—")
        XCTAssertEqual(neither.recommendedLimitText, "—")

        let both = projectAllocated(
            nodes: [node(["In use system memory": .bytes(512)])],
            limit: 1_024,
            at: 4
        )
        XCTAssertEqual(both.memoryBarFraction, 0.5)
        XCTAssertEqual(both.memoryText, "512 字节")
        XCTAssertEqual(both.recommendedLimitText, "1 KB")

        let idle = projectAllocated(
            nodes: [node(["In use system memory": .bytes(0)])],
            limit: 1_024,
            at: 5
        )
        XCTAssertEqual(idle.memoryBarFraction, 0)
        XCTAssertEqual(idle.memoryText, "0 字节")
        XCTAssertEqual(idle.recommendedLimitText, "1 KB")
    }

    func testMemoryBarClampsAboveOneWhileTheTextsStayReal() {
        let page = projectAllocated(
            nodes: [
                node([
                    "In use system memory": .bytes(2_097_152),
                    "Alloc system memory": .bytes(3_145_728),
                ]),
            ],
            limit: 1_048_576,
            at: 1
        )

        XCTAssertEqual(page.memoryBarFraction, 1)
        XCTAssertEqual(page.memoryText, "2 MB")
        XCTAssertEqual(page.recommendedLimitText, "1 MB")
        XCTAssertNotEqual(page.memoryText, "1 MB")
        XCTAssertEqual(page.allocatedText, "3 MB")
        XCTAssertEqual(GPUPageCopy.recommendedLimit, "建议上限")
        XCTAssertEqual(GPUPageCopy.recommendedLimitLine("1 MB"), "建议上限 1 MB")
        XCTAssertFalse(GPUPageCopy.recommendedLimitLine("1 MB").contains("总量"))

        let kept = GPUPageProjection.apply(
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: page,
            transition: .stayed
        )
        XCTAssertEqual(kept.allocatedText, "3 MB")
        XCTAssertEqual(kept.memoryText, "2 MB")
        XCTAssertEqual(kept.recommendedLimitText, "1 MB")
        XCTAssertEqual(kept.memoryBarFraction, 1)
    }

    func testDashboardPublishesSameNodeAllocatedBytesAndClampsTheBar() {
        var core = DashboardCore(ownPid: 88)
        let frame = allocatedFrame(
            nodes: [
                GPUAcceleratorNode(statistics: [
                    "In use system memory": .bytes(100),
                    "Alloc system memory": .bytes(9_000),
                ]),
                GPUAcceleratorNode(statistics: [
                    "In use system memory": .bytes(2_097_152),
                    "Alloc system memory": .bytes(50),
                ]),
            ],
            limit: 1_048_576
        )
        _ = core.apply(
            result: Result<SampledFrame, AllocatedProbeError>.success(frame),
            accepted: true,
            page: .memory
        )

        XCTAssertEqual(core.gpu.page.inUseMemoryBytes, 2_097_152)
        XCTAssertEqual(core.gpu.page.memoryText, "2 MB")
        XCTAssertEqual(core.gpu.page.allocatedMemoryBytes, 50)
        XCTAssertEqual(core.gpu.page.allocatedText, "50 字节")
        XCTAssertNotEqual(core.gpu.page.allocatedMemoryBytes, 9_000)
        XCTAssertEqual(core.gpu.page.memoryBarFraction, 1)
        XCTAssertEqual(core.gpu.page.recommendedLimitText, "1 MB")
    }

    private func projectAllocated(
        nodes: [GPUAcceleratorNode],
        limit: UInt64?,
        at time: TimeInterval
    ) -> GPUPageState {
        GPUPageProjection.apply(
            nodes: nodes,
            recommendedMaxWorkingSetBytes: limit,
            frame: .succeeded,
            sampledAt: Date(timeIntervalSince1970: time),
            current: .initial,
            transition: .stayed
        )
    }

    private func allocatedFrame(nodes: [GPUAcceleratorNode], limit: UInt64?) -> SampledFrame {
        let at = Date(timeIntervalSince1970: 1_700_000_230)
        return SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 100,
                totalBytes: 1_000,
                breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
                pressure: .normal,
                pressureMetric: 0.1,
                pressureSeries: [],
                capturedAt: at,
                swapUsedBytes: 0
            ),
            rows: [
                ProcessRow(
                    pid: 7,
                    name: "Mail",
                    bundleIdentifier: nil,
                    executablePath: nil,
                    cpuPercent: 1,
                    memoryBytes: 100,
                    threadCount: 1
                ),
            ],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 10,
            hostNetworkRates: HostNetworkRates(inboundBytesPerSecond: 1, outboundBytesPerSecond: 1),
            hostDiskRates: HostDiskRates(readBytesPerSecond: 1, writeBytesPerSecond: 1),
            gpuNodes: nodes,
            gpuRecommendedMaxWorkingSetBytes: limit
        )
    }
}

private enum AllocatedProbeError: Error {
    case unavailable
}
