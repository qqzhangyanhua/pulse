import Foundation

enum SymptomKind: String, Equatable, CaseIterable, Sendable {
    case slow
    case hot
    case fan
    case battery
    case disk
    case sleep

    var title: String {
        switch self {
        case .slow: return "慢"
        case .hot: return "热"
        case .fan: return "风扇响"
        case .battery: return "掉电快"
        case .disk: return "磁盘满"
        case .sleep: return "不睡眠"
        }
    }
}

struct SymptomProcess: Equatable, Sendable {
    var pid: Int32
    var name: String
    var cpuPercent: Double?
    var energyWatts: Double?
}

struct SymptomHeldSleep: Equatable, Sendable {
    var pid: Int32
    var name: String
    var typeText: String
}

/// `unread` is not the same as a successful read that found nobody.
enum SymptomSleepFacts: Equatable, Sendable {
    case unread
    case none
    case held([SymptomHeldSleep])
}

struct SymptomInput: Equatable, Sendable {
    var systemCpuPercent: Double?
    var processes: [SymptomProcess] = []
    var memoryPressure: PressureLevel?
    var thermalName: String?
    var gpuPercent: Double?
    /// Negative is discharge. Nil has not been read.
    var dischargeMilliamps: Int?
    var diskFreeBytes: UInt64?
    var diskTotalBytes: UInt64?
    /// Nil means this Mac has no purgeable reading. Never treat that as zero.
    var purgeableBytes: UInt64?
    var sleep: SymptomSleepFacts = .unread
    /// CPU percents from the last hour. Nil entries are gaps, not zero.
    var recentCPU: [Double?] = []
}

struct SymptomCause: Equatable, Sendable {
    var title: String
    var evidence: String
    var page: DashboardPage
    var pid: Int32?
}

struct SymptomFinding: Equatable, Sendable {
    var causes: [SymptomCause]
    var note: String?

    var headline: String {
        causes.isEmpty ? Self.unknown : causes[0].title
    }

    static let unknown = "看不出原因"
    static let fanUnreadable = "读不到风扇转速"
}

enum SymptomDiagnosis {
    static func finding(_ kind: SymptomKind, input: SymptomInput) -> SymptomFinding {
        switch kind {
        case .slow:
            return SymptomFinding(causes: Array(slow(input).prefix(3)), note: nil)
        case .hot:
            return SymptomFinding(causes: Array(heat(input).prefix(3)), note: nil)
        case .fan:
            return SymptomFinding(causes: Array(heat(input).prefix(3)), note: SymptomFinding.fanUnreadable)
        case .battery:
            return SymptomFinding(causes: Array(battery(input).prefix(3)), note: nil)
        case .disk:
            return SymptomFinding(causes: disk(input), note: nil)
        case .sleep:
            return sleep(input)
        }
    }

    private static func slow(_ input: SymptomInput) -> [SymptomCause] {
        var causes: [SymptomCause] = []
        if input.memoryPressure == .elevated {
            causes.append(SymptomCause(
                title: "内存压力偏高",
                evidence: "压力档是偏高",
                page: .memory,
                pid: nil
            ))
        }
        let recent = input.recentCPU.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        if recent.count >= 3 {
            let average = recent.reduce(0, +) / Double(recent.count)
            if average >= 80 {
                causes.append(SymptomCause(
                    title: "这一小时整机 CPU 偏高",
                    evidence: "有读数的样本平均不低于 80%",
                    page: .cpu,
                    pid: nil
                ))
            }
        }
        let busy = input.processes
            .compactMap { process -> (SymptomProcess, Double)? in
                guard let cpu = process.cpuPercent, cpu.isFinite, cpu >= 70 else { return nil }
                return (process, cpu)
            }
            .sorted { $0.1 > $1.1 }
        for (process, cpu) in busy {
            causes.append(SymptomCause(
                title: process.name,
                evidence: String(format: "CPU %.0f%%", cpu),
                page: .cpu,
                pid: process.pid
            ))
        }
        return causes
    }

    private static func heat(_ input: SymptomInput) -> [SymptomCause] {
        var causes: [SymptomCause] = []
        if input.thermalName == "serious" || input.thermalName == "critical" {
            causes.append(SymptomCause(
                title: "系统正在为温度降频",
                evidence: "热状态是 \(input.thermalName ?? "")",
                page: .machine,
                pid: nil
            ))
        }
        if let cpu = input.systemCpuPercent, cpu.isFinite, cpu >= 85 {
            causes.append(SymptomCause(
                title: "整机 CPU 偏高",
                evidence: String(format: "整机 CPU %.0f%%", cpu),
                page: .cpu,
                pid: nil
            ))
        }
        if let gpu = input.gpuPercent, gpu.isFinite, gpu >= 85 {
            causes.append(SymptomCause(
                title: "GPU 使用率偏高",
                evidence: String(format: "GPU %.0f%%", gpu),
                page: .gpu,
                pid: nil
            ))
        }
        return causes
    }

    private static func battery(_ input: SymptomInput) -> [SymptomCause] {
        var causes: [SymptomCause] = []
        if let milliamps = input.dischargeMilliamps, milliamps <= -1_500 {
            causes.append(SymptomCause(
                title: "电池正在较快放电",
                evidence: "放电 \(milliamps) mA",
                page: .energy,
                pid: nil
            ))
        }
        let heavy = input.processes
            .compactMap { process -> (SymptomProcess, Double)? in
                guard let watts = process.energyWatts, watts.isFinite, watts >= 8 else { return nil }
                return (process, watts)
            }
            .sorted { $0.1 > $1.1 }
        for (process, watts) in heavy {
            causes.append(SymptomCause(
                title: process.name,
                evidence: String(format: "能耗影响 %.1f W", watts),
                page: .energy,
                pid: process.pid
            ))
        }
        return causes
    }

    private static func disk(_ input: SymptomInput) -> [SymptomCause] {
        guard let free = input.diskFreeBytes, let total = input.diskTotalBytes, total > 0 else {
            return []
        }
        guard free < total / 10 else { return [] }
        var evidence = "可用 \(ByteFormat.memory(free))"
        if let purgeable = input.purgeableBytes {
            evidence += "。可清除 \(ByteFormat.memory(purgeable))"
        } else {
            evidence += "。可清除空间读不到"
        }
        return [SymptomCause(
            title: "磁盘剩余不多",
            evidence: evidence,
            page: .machine,
            pid: nil
        )]
    }

    private static func sleep(_ input: SymptomInput) -> SymptomFinding {
        switch input.sleep {
        case .unread:
            return SymptomFinding(causes: [], note: nil)
        case .none:
            return SymptomFinding(causes: [], note: SleepAssertionCopy.empty)
        case .held(let rows):
            let causes = rows.prefix(3).map { row in
                SymptomCause(
                    title: row.name,
                    evidence: row.typeText,
                    page: .energy,
                    pid: row.pid
                )
            }
            return SymptomFinding(causes: Array(causes), note: nil)
        }
    }
}
