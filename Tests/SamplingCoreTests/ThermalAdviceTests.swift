import XCTest
@testable import SamplingCore

final class ThermalAdviceTests: XCTestCase {
    func testTopThreeOrdersByDescendingCPUAndAscendingPid() {
        let ranked = ThermalAdviceProjection.project([
            candidate(pid: 41, name: "seven", cpu: 7),
            candidate(pid: 11, name: "busy", cpu: 80, bundle: "b.busy", path: "/busy"),
            candidate(pid: 51, name: "gap", cpu: nil, bundle: "b.gap", path: "/gap"),
            candidate(pid: 31, name: "eight", cpu: 8),
            candidate(pid: 21, name: "nine", cpu: 9),
        ], excludingPid: 1)

        XCTAssertFalse(ranked.noHighLoad)
        XCTAssertEqual(ranked.processes, [
            ThermalAdviceProcess(pid: 11, name: "busy", cpuPercent: 80, bundleIdentifier: "b.busy", executablePath: "/busy"),
            ThermalAdviceProcess(pid: 21, name: "nine", cpuPercent: 9, bundleIdentifier: nil, executablePath: nil),
            ThermalAdviceProcess(pid: 31, name: "eight", cpuPercent: 8, bundleIdentifier: nil, executablePath: nil),
        ])

        let tied = ThermalAdviceProjection.project([
            candidate(pid: 5, name: "later", cpu: 40, bundle: "b.later", path: "/later"),
            candidate(pid: 3, name: "earlier", cpu: 40, bundle: "b.earlier", path: "/earlier"),
            candidate(pid: 4, name: "third", cpu: 12),
            candidate(pid: 6, name: "dropped", cpu: 11),
        ], excludingPid: 1)

        XCTAssertFalse(tied.noHighLoad)
        XCTAssertEqual(tied.processes, [
            ThermalAdviceProcess(pid: 3, name: "earlier", cpuPercent: 40, bundleIdentifier: "b.earlier", executablePath: "/earlier"),
            ThermalAdviceProcess(pid: 5, name: "later", cpuPercent: 40, bundleIdentifier: "b.later", executablePath: "/later"),
            ThermalAdviceProcess(pid: 4, name: "third", cpuPercent: 12, bundleIdentifier: nil, executablePath: nil),
        ])
    }

    func testExcludingPulsePromotesTheFourthProcess() {
        let advice = ThermalAdviceProjection.project([
            candidate(pid: 10, name: "Pulse", cpu: 99, bundle: "app.pulse", path: "/Apps/Pulse"),
            candidate(pid: 1, name: "one", cpu: 40, bundle: "app.one", path: "/Apps/One"),
            candidate(pid: 2, name: "two", cpu: 30),
            candidate(pid: 3, name: "three", cpu: 20, bundle: "app.three", path: "/Apps/Three"),
            candidate(pid: 4, name: "four", cpu: 15),
        ], excludingPid: 10)

        XCTAssertFalse(advice.noHighLoad)
        XCTAssertEqual(advice.processes, [
            ThermalAdviceProcess(pid: 1, name: "one", cpuPercent: 40, bundleIdentifier: "app.one", executablePath: "/Apps/One"),
            ThermalAdviceProcess(pid: 2, name: "two", cpuPercent: 30, bundleIdentifier: nil, executablePath: nil),
            ThermalAdviceProcess(pid: 3, name: "three", cpuPercent: 20, bundleIdentifier: "app.three", executablePath: "/Apps/Three"),
        ])
    }

    func testAllUnderTenPercentReturnsEmptyAndNoHighLoad() {
        let advice = ThermalAdviceProjection.project([
            candidate(pid: 3, name: "c", cpu: 7),
            candidate(pid: 1, name: "a", cpu: 9),
            candidate(pid: 2, name: "b", cpu: 8),
        ], excludingPid: 99)

        XCTAssertTrue(advice.noHighLoad)
        XCTAssertEqual(advice.processes, [])
        XCTAssertEqual(ThermalAdvice.noHighLoadMessage, "系统正在降频，但未检测到高负载进程")
    }

    func testFewerThanThreeQualifyingProcessesAreReturnedInFull() {
        let advice = ThermalAdviceProjection.project([
            candidate(pid: 8, name: "unread", cpu: nil, bundle: "app.unread", path: "/Apps/Unread"),
            candidate(pid: 7, name: "solo", cpu: 50, bundle: "app.solo", path: "/Apps/Solo"),
        ], excludingPid: 1)

        XCTAssertFalse(advice.noHighLoad)
        XCTAssertEqual(advice.processes, [
            ThermalAdviceProcess(pid: 7, name: "solo", cpuPercent: 50, bundleIdentifier: "app.solo", executablePath: "/Apps/Solo"),
        ])
    }

    func testExactlyTenPercentIsKept() {
        let advice = ThermalAdviceProjection.project([
            candidate(pid: 5, name: "edge", cpu: 10, bundle: "app.edge", path: "/bin/edge"),
            candidate(pid: 6, name: "under", cpu: 9),
        ], excludingPid: 0)

        XCTAssertEqual(ThermalAdvice.highLoadFloorPercent, 10)
        XCTAssertFalse(advice.noHighLoad)
        XCTAssertEqual(advice.processes, [
            ThermalAdviceProcess(pid: 5, name: "edge", cpuPercent: 10, bundleIdentifier: "app.edge", executablePath: "/bin/edge"),
            ThermalAdviceProcess(pid: 6, name: "under", cpuPercent: 9, bundleIdentifier: nil, executablePath: nil),
        ])
    }

    private func candidate(
        pid: Int32,
        name: String,
        cpu: Double?,
        bundle: String? = nil,
        path: String? = nil
    ) -> ThermalAdviceCandidate {
        ThermalAdviceCandidate(
            pid: pid,
            name: name,
            cpuPercent: cpu,
            bundleIdentifier: bundle,
            executablePath: path
        )
    }
}
