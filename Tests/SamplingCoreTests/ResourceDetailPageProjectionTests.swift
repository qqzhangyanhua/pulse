import XCTest
@testable import SamplingCore

/// Phase 18 pure page projection.
///
/// Linux SamplingCore only. Frozen denominators are passed in as values.
/// These cases do not step the last-live reducer. A pass is not a SwiftUI
/// sidebar, not a snapshot, and not a Mac click.
final class ResourceDetailPageProjectionTests: XCTestCase {
    private let gib: UInt64 = 1_073_741_824
    private let pidA: Int32 = 4
    private let pidB: Int32 = 9

    func testCPUNetworkAndDiskShareTheRowAndKeepSeriesIdentity() throws {
        let memorySeries = samples([10, 12, 15])
        let cpuSeries = samples([1.5, 2.5])
        let detail = detail(
            pid: pidA,
            cpu: 12.5,
            memory: 8 * gib,
            read: nil,
            write: 0,
            memorySeries: memorySeries,
            cpuSeries: cpuSeries
        )
        let original = detail
        let cpu = try cpu(project(.cpu, detail, total: 16 * gib, frozen: nil))
        let network = try network(project(.network, detail, total: 16 * gib, frozen: nil))
        let disk = try disk(project(.disk, detail, total: 16 * gib, frozen: nil))

        XCTAssertEqual(detail, original)
        XCTAssertEqual(cpu.pid, pidA)
        XCTAssertEqual(cpu.cpuPercent, 12.5)
        XCTAssertEqual(cpu.memoryBytes, 8 * gib)
        XCTAssertEqual(cpu.cpuSeries, cpuSeries)
        XCTAssertEqual(cpu.cpuSeries.map(\.id), cpuSeries.map(\.id))
        XCTAssertEqual(cpu.cpuSeries.map(\.date), cpuSeries.map(\.date))
        XCTAssertEqual(cpu.cpuSeries.map(\.value), cpuSeries.map(\.value))
        XCTAssertEqual(cpu.memorySeries, memorySeries)
        XCTAssertEqual(network.pid, pidA)
        XCTAssertEqual(network.cpuPercent, cpu.cpuPercent)
        XCTAssertEqual(network.memoryBytes, cpu.memoryBytes)
        XCTAssertEqual(network.memorySeries, memorySeries)
        XCTAssertEqual(disk.pid, pidA)
        XCTAssertEqual(disk.cpuPercent, cpu.cpuPercent)
        XCTAssertEqual(disk.memoryBytes, cpu.memoryBytes)
        XCTAssertEqual(disk.memorySeries, memorySeries)
        XCTAssertNil(disk.readBytesPerSecond)
        XCTAssertEqual(disk.writeBytesPerSecond, 0)

        XCTAssertEqual(
            labels(of: cpu),
            ["pid", "cpuPercent", "cpuSeries", "memory", "memoryBytes", "memorySeries"]
        )
        XCTAssertEqual(
            labels(of: network),
            ["pid", "notice", "cpuPercent", "memory", "memoryBytes", "memorySeries"]
        )
        XCTAssertFalse(labels(of: network).contains("cpuSeries"))
        XCTAssertFalse(labels(of: network).contains("readBytesPerSecond"))
        XCTAssertEqual(
            labels(of: disk),
            ["pid", "readBytesPerSecond", "writeBytesPerSecond", "cpuPercent", "memory", "memoryBytes", "memorySeries"]
        )
        XCTAssertFalse(labels(of: disk).contains("cpuSeries"))
        XCTAssertFalse(labels(of: cpu).contains("readBytesPerSecond"))
        XCTAssertFalse(labels(of: cpu).contains("notice"))
    }

    func testMemoryStaysExistingAndGPUDoesNotEnterThatBranch() throws {
        let memorySeries = samples([4, 8])
        let cpuSeries = samples([3])
        let detail = detail(
            pid: pidA,
            cpu: 1,
            memory: 8 * gib,
            memorySeries: memorySeries,
            cpuSeries: cpuSeries
        )
        let memory = try memoryExisting(project(.memory, detail, total: 16 * gib, frozen: nil))
        XCTAssertEqual(memory.pid, pidA)
        XCTAssertEqual(memory.memoryBytes, 8 * gib)
        XCTAssertEqual(memory.memorySeries, memorySeries)
        XCTAssertEqual(memory.cpuSeries, cpuSeries)
        XCTAssertEqual(
            labels(of: memory),
            ["pid", "memoryBytes", "memorySeries", "cpuSeries"]
        )

        let gpu = try noUpgrade(project(.gpu, detail, total: 16 * gib, frozen: nil))
        XCTAssertEqual(gpu.pid, pidA)
        XCTAssertEqual(gpu.cpuPercent, 1)
        XCTAssertEqual(gpu.memoryBytes, 8 * gib)
        XCTAssertEqual(gpu.memorySeries, memorySeries)
        XCTAssertEqual(gpu.memory.title, "内存")
        XCTAssertNotEqual(gpu.memory.title, "驻留内存")
        XCTAssertEqual(
            gpu.memory,
            MemoryDetailPresentation.field(page: .gpu, part: 8 * gib, total: 16 * gib)
        )
        XCTAssertEqual(
            labels(of: gpu),
            ["pid", "cpuPercent", "memory", "memoryBytes", "memorySeries"]
        )
        XCTAssertFalse(labels(of: gpu).contains("cpuSeries"))
        XCTAssertFalse(labels(of: gpu).contains("readBytesPerSecond"))
        XCTAssertFalse(labels(of: gpu).contains("notice"))

        let asMemory = project(.memory, detail, total: 16 * gib, frozen: nil)
        guard case .memoryExisting = asMemory else {
            return XCTFail("memory page must stay .memoryExisting")
        }
        let asGPU = project(.gpu, detail, total: 16 * gib, frozen: nil)
        guard case .noResourceUpgrade = asGPU else {
            return XCTFail("gpu page must stay .noResourceUpgrade")
        }
    }

    func testAlternatingPidsDoNotLeakAndLeaveTheInputEqual() throws {
        let detailA = detail(pid: pidA, cpu: 3, memory: 100, read: 5, write: 7, memorySeries: samples([1]), cpuSeries: samples([2]))
        let detailB = detail(pid: pidB, cpu: 9, memory: 200, read: 0, write: nil, memorySeries: samples([4, 5]), cpuSeries: samples([6, 7]))
        let originalA = detailA
        let originalB = detailB
        let first = try cpu(project(.cpu, detailA, total: nil, frozen: nil))
        let second = try cpu(project(.cpu, detailB, total: nil, frozen: nil))
        let third = try cpu(project(.cpu, detailA, total: nil, frozen: nil))
        XCTAssertEqual(first.pid, pidA)
        XCTAssertEqual(first.cpuPercent, 3)
        XCTAssertEqual(first.memoryBytes, 100)
        XCTAssertEqual(second.pid, pidB)
        XCTAssertEqual(second.cpuPercent, 9)
        XCTAssertEqual(second.memoryBytes, 200)
        XCTAssertEqual(third, first)
        XCTAssertEqual(detailA, originalA)
        XCTAssertEqual(detailB, originalB)

        let diskA = try disk(project(.disk, detailA, total: nil, frozen: nil))
        let diskB = try disk(project(.disk, detailB, total: nil, frozen: nil))
        XCTAssertEqual(diskA.readBytesPerSecond, 5)
        XCTAssertEqual(diskA.writeBytesPerSecond, 7)
        XCTAssertEqual(diskB.readBytesPerSecond, 0)
        XCTAssertNil(diskB.writeBytesPerSecond)
    }

    func testNetworkNoticeIsExactAndNeverAShamZero() throws {
        XCTAssertEqual(ResourceDetailPageProjection.processNetworkUnavailable, "当前进程网络暂不可用")
        XCTAssertNotEqual(ResourceDetailPageProjection.processNetworkUnavailable, "暂不可用")
        XCTAssertNotEqual(ResourceDetailPageProjection.processNetworkUnavailable, "0 字节/秒")
        XCTAssertNotEqual(
            ResourceDetailPageProjection.processNetworkUnavailable,
            NetworkPageCopy.processNetworkUnavailable
        )
        XCTAssertEqual(NetworkPageCopy.processNetworkUnavailable, "暂不可用")
        XCTAssertEqual(ProcessNetworkAvailability.unavailable.label, "暂不可用")
        XCTAssertFalse(ResourceDetailPageProjection.processNetworkUnavailable.contains("下行"))
        XCTAssertFalse(ResourceDetailPageProjection.processNetworkUnavailable.contains("0"))
        XCTAssertFalse(ResourceDetailPageProjection.processNetworkUnavailable.contains("字节"))

        for series in [[ChartSample](), samples([1, 2, 3])] {
            let projected = try network(
                project(
                    .network,
                    detail(pid: pidA, cpu: nil, memory: 10, memorySeries: series, cpuSeries: samples([9])),
                    total: nil,
                    frozen: nil
                )
            )
            XCTAssertEqual(projected.notice, .unavailable)
            XCTAssertEqual(projected.memorySeries, series)
            XCTAssertTrue(Mirror(reflecting: projected.notice).children.isEmpty)
        }
    }

    func testDiskNilAndZeroStayOnTheirOwnSides() throws {
        let cases: [(Double?, Double?, String, String)] = [
            (nil, 0, "—", "0 字节/秒"),
            (0, nil, "0 字节/秒", "—"),
            (nil, nil, "—", "—"),
            (0, 0, "0 字节/秒", "0 字节/秒"),
        ]
        for (read, write, readText, writeText) in cases {
            let projected = try disk(
                project(
                    .disk,
                    detail(pid: pidA, cpu: 1, memory: 10, read: read, write: write),
                    total: nil,
                    frozen: nil
                )
            )
            XCTAssertEqual(projected.readBytesPerSecond, read)
            XCTAssertEqual(projected.writeBytesPerSecond, write)
            XCTAssertEqual(DiskRateText.string(projected.readBytesPerSecond), readText)
            XCTAssertEqual(DiskRateText.string(projected.writeBytesPerSecond), writeText)
            if read == nil {
                XCTAssertNotEqual(DiskRateText.string(projected.readBytesPerSecond), "0 字节/秒")
            }
            if write == nil {
                XCTAssertNotEqual(DiskRateText.string(projected.writeBytesPerSecond), "0 字节/秒")
            }
        }
    }

    func testNilCPUKeepsExistingPointsAndEmptyMemorySeriesStaysEmpty() throws {
        let cpuSeries = samples([4, 5, 6])
        let detail = detail(pid: pidA, cpu: nil, memory: 10, memorySeries: [], cpuSeries: cpuSeries)
        let cpu = try self.cpu(project(.cpu, detail, total: nil, frozen: nil))
        XCTAssertNil(cpu.cpuPercent)
        XCTAssertEqual(cpu.cpuSeries, cpuSeries)
        XCTAssertEqual(cpu.cpuSeries.count, 3)
        XCTAssertEqual(cpu.memorySeries.count, 0)

        let one = samples([42])
        for page in DashboardPage.allCases {
            let projected = project(
                page,
                self.detail(pid: pidA, cpu: 0, memory: 10, memorySeries: one, cpuSeries: []),
                total: nil,
                frozen: nil
            )
            switch projected {
            case .memoryExisting(let value):
                XCTAssertEqual(value.memorySeries, one)
                XCTAssertEqual(value.cpuSeries.count, 0)
            case .cpu(let value):
                XCTAssertEqual(value.memorySeries, one)
                XCTAssertEqual(value.cpuSeries.count, 0)
                XCTAssertEqual(value.cpuPercent, 0)
            case .network(let value):
                XCTAssertEqual(value.memorySeries, one)
                XCTAssertEqual(value.cpuPercent, 0)
            case .disk(let value):
                XCTAssertEqual(value.memorySeries, one)
                XCTAssertEqual(value.cpuPercent, 0)
            case .noResourceUpgrade(let value):
                XCTAssertEqual(value.memorySeries, one)
                XCTAssertEqual(value.cpuPercent, 0)
            }
        }
    }

    func testCPUMemoryCopyMatchesFieldAndNilTotalHasNoFakeZeroPercent() throws {
        let part = 8 * gib
        let total = 16 * gib
        let detail = detail(pid: pidA, cpu: 2, memory: part)
        let cpu = try self.cpu(project(.cpu, detail, total: total, frozen: nil))
        XCTAssertEqual(
            cpu.memory,
            MemoryDetailPresentation.field(page: .cpu, part: part, total: total)
        )
        let pages: [DashboardPage] = [.cpu, .network, .disk, .gpu]
        for page in pages {
            for physical in [UInt64?.none, UInt64(0)] {
                let copy = memoryCopy(project(page, detail, total: physical, frozen: nil))
                XCTAssertEqual(copy.title, "内存", "\(page) \(String(describing: physical))")
                XCTAssertEqual(copy.caption, "占物理内存")
                XCTAssertNil(copy.help)
                XCTAssertFalse(copy.caption.contains("%"))
                XCTAssertFalse(copy.caption.contains("0%"))
                XCTAssertEqual(
                    copy,
                    MemoryDetailPresentation.field(page: page, part: part, total: nil)
                )
            }
        }
    }
    func testFrozenSemanticsKeepTheCapturedTotalWhenTheSnapshotIsEighteen() throws {
        let eight = 8 * gib
        let nine = 9 * gib
        let sixteen = 16 * gib
        let eighteen = 18 * gib
        let semantics = FrozenMemoryFieldSemantics(
            pid: pidA,
            memoryBytes: eight,
            physicalTotalBytes: sixteen
        )
        XCTAssertEqual(
            ResourceDetailPageProjection.memoryTotal(
                detailPid: pidA,
                physicalTotalBytes: eighteen,
                frozen: semantics
            ),
            sixteen
        )
        XCTAssertNil(
            ResourceDetailPageProjection.memoryTotal(
                detailPid: pidB,
                physicalTotalBytes: eighteen,
                frozen: semantics
            )
        )
        let resident = MemoryDetailPresentation.field(page: .memory, part: eight, total: sixteen)
        XCTAssertEqual(resident.title, "驻留内存")
        XCTAssertEqual(resident.caption, "占物理内存的 50%（按驻留内存计算）")
        XCTAssertFalse(resident.caption.contains("18"))
        let auxiliary = MemoryDetailPresentation.field(page: .cpu, part: eight, total: sixteen)
        XCTAssertEqual(auxiliary.title, "内存")
        XCTAssertEqual(auxiliary.caption, "占 16 GB 的 50%")
        let row = detail(pid: pidA, cpu: 1, memory: nine)
        let cpu = try self.cpu(project(.cpu, row, total: eighteen, frozen: semantics))
        XCTAssertEqual(cpu.memory, MemoryDetailPresentation.field(page: .cpu, part: nine, total: sixteen))
        XCTAssertNotEqual(cpu.memory, MemoryDetailPresentation.field(page: .cpu, part: eight, total: sixteen))
        XCTAssertFalse(cpu.memory.caption.contains("18"))
        let eightRow = detail(pid: pidA, cpu: 1, memory: eight)
        let network = memoryCopy(project(.network, eightRow, total: eighteen, frozen: semantics))
        let disk = memoryCopy(project(.disk, eightRow, total: 1, frozen: semantics))
        XCTAssertEqual(network.caption, disk.caption)
        XCTAssertEqual(network.caption, "占 16 GB 的 50%")
        let missing = FrozenMemoryFieldSemantics(pid: pidA, memoryBytes: eight, physicalTotalBytes: nil)
        XCTAssertNil(
            ResourceDetailPageProjection.memoryTotal(
                detailPid: pidA,
                physicalTotalBytes: eighteen,
                frozen: missing
            )
        )
        let noShare = memoryCopy(project(.cpu, row, total: eighteen, frozen: missing))
        XCTAssertEqual(noShare.caption, "占物理内存")
        XCTAssertFalse(noShare.caption.contains("%"))
        XCTAssertFalse(noShare.caption.contains("0%"))
    }

    private func project(
        _ page: DashboardPage,
        _ detail: ProcessDetail,
        total: UInt64?,
        frozen: FrozenMemoryFieldSemantics?
    ) -> ResourceDetailProjection {
        ResourceDetailPageProjection.project(
            page: page,
            detail: detail,
            physicalTotalBytes: total,
            frozen: frozen
        )
    }

    private func memoryCopy(_ projection: ResourceDetailProjection) -> MemoryDetailFieldCopy {
        switch projection {
        case .cpu(let value):
            return value.memory
        case .network(let value):
            return value.memory
        case .disk(let value):
            return value.memory
        case .noResourceUpgrade(let value):
            return value.memory
        case .memoryExisting:
            XCTFail("memory page has no auxiliary field payload")
            return MemoryDetailFieldCopy(title: "", caption: "", help: nil)
        }
    }

    private func cpu(_ projection: ResourceDetailProjection, file: StaticString = #filePath, line: UInt = #line) throws -> CPUDetailProjection {
        guard case .cpu(let value) = projection else {
            XCTFail("expected .cpu", file: file, line: line)
            throw ProjectionTestError.wrongCase
        }
        return value
    }

    private func network(_ projection: ResourceDetailProjection, file: StaticString = #filePath, line: UInt = #line) throws -> NetworkDetailProjection {
        guard case .network(let value) = projection else {
            XCTFail("expected .network", file: file, line: line)
            throw ProjectionTestError.wrongCase
        }
        return value
    }

    private func disk(_ projection: ResourceDetailProjection, file: StaticString = #filePath, line: UInt = #line) throws -> DiskDetailProjection {
        guard case .disk(let value) = projection else {
            XCTFail("expected .disk", file: file, line: line)
            throw ProjectionTestError.wrongCase
        }
        return value
    }

    private func memoryExisting(_ projection: ResourceDetailProjection, file: StaticString = #filePath, line: UInt = #line) throws -> MemoryExistingProjection {
        guard case .memoryExisting(let value) = projection else {
            XCTFail("expected .memoryExisting", file: file, line: line)
            throw ProjectionTestError.wrongCase
        }
        return value
    }

    private func noUpgrade(_ projection: ResourceDetailProjection, file: StaticString = #filePath, line: UInt = #line) throws -> NoResourceUpgradeProjection {
        guard case .noResourceUpgrade(let value) = projection else {
            XCTFail("expected .noResourceUpgrade", file: file, line: line)
            throw ProjectionTestError.wrongCase
        }
        return value
    }

    private func labels<T>(of value: T) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    private func detail(
        pid: Int32,
        cpu: Double?,
        memory: UInt64,
        read: Double? = nil,
        write: Double? = nil,
        memorySeries: [ChartSample] = [],
        cpuSeries: [ChartSample] = []
    ) -> ProcessDetail {
        ProcessDetail(
            row: ProcessRow(
                pid: pid,
                name: "p\(pid)",
                bundleIdentifier: nil,
                executablePath: nil,
                cpuPercent: cpu,
                memoryBytes: memory,
                threadCount: 1,
                diskReadBytesPerSecond: read,
                diskWriteBytesPerSecond: write
            ),
            memorySeries: memorySeries,
            cpuSeries: cpuSeries
        )
    }

    private func samples(_ values: [Double]) -> [ChartSample] {
        values.enumerated().map { index, value in
            ChartSample(
                id: UInt64(index + 1),
                date: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 10),
                value: value
            )
        }
    }
}

private enum ProjectionTestError: Error {
    case wrongCase
}
