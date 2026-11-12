struct ThermalAdviceCandidate: Equatable, Sendable {
    var pid: Int32
    var name: String
    var cpuPercent: Double?
    var bundleIdentifier: String?
    var executablePath: String?
}

struct ThermalAdviceProcess: Equatable, Sendable {
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var bundleIdentifier: String?
    var executablePath: String?
}

struct ThermalAdvice: Equatable, Sendable {
    var processes: [ThermalAdviceProcess]
    var noHighLoad: Bool
    static let noHighLoadMessage = "系统正在降频，但未检测到高负载进程"
    static let highLoadFloorPercent = 10.0
}

enum ThermalAdviceProjection {
    static func project(_ processes: [ThermalAdviceCandidate], excludingPid pulsePid: Int32) -> ThermalAdvice {
        let ranked = processes.compactMap { candidate -> ThermalAdviceProcess? in
            guard candidate.pid != pulsePid, let cpuPercent = candidate.cpuPercent else { return nil }
            return ThermalAdviceProcess(
                pid: candidate.pid,
                name: candidate.name,
                cpuPercent: cpuPercent,
                bundleIdentifier: candidate.bundleIdentifier,
                executablePath: candidate.executablePath
            )
        }
        .sorted { lhs, rhs in
            if lhs.cpuPercent == rhs.cpuPercent {
                return lhs.pid < rhs.pid
            }
            return lhs.cpuPercent > rhs.cpuPercent
        }
        let top = Array(ranked.prefix(3))
        guard !top.isEmpty else {
            return ThermalAdvice(processes: [], noHighLoad: false)
        }
        if top.allSatisfy({ $0.cpuPercent < ThermalAdvice.highLoadFloorPercent }) {
            return ThermalAdvice(processes: [], noHighLoad: true)
        }
        return ThermalAdvice(processes: top, noHighLoad: false)
    }
}
