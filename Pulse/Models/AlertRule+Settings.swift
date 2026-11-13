import Foundation

/// Whole machine, or one app named as it appears in the process list.
enum AlertObject: Equatable, Sendable, Codable {
    case machine
    case app(String)

    var title: String {
        switch self {
        case .machine: return "整机"
        case .app(let name): return name
        }
    }

    /// 「整机 CPU」 has no 的. 「Chrome 的 CPU」 does.
    var phrase: String {
        switch self {
        case .machine: return "整机"
        case .app(let name): return "\(name) 的"
        }
    }
}

enum AlertMetric: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case cpu
    case memoryFootprint
    case memoryPressure
    case chipTemperature
    case diskFree

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memoryFootprint: return "内存占用"
        case .memoryPressure: return "内存压力"
        case .chipTemperature: return "芯片温度"
        case .diskFree: return "磁盘剩余"
        }
    }

    var page: DashboardPage {
        switch self {
        case .cpu: return .cpu
        case .memoryFootprint, .memoryPressure: return .memory
        case .chipTemperature, .diskFree: return .machine
        }
    }

    /// Shown next to the threshold field. Memory pressure has no number.
    var thresholdUnit: String {
        switch self {
        case .cpu: return "%"
        case .memoryFootprint, .diskFree: return "GB"
        case .chipTemperature: return "°C"
        case .memoryPressure: return ""
        }
    }

    /// CPU, memory, and temperature fire above the threshold. Disk free fires below it.
    /// Memory pressure ignores the number: elevated is the only breach.
    func storedThreshold(displayText: String) -> Double? {
        if self == .memoryPressure { return 0 }
        let trimmed = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(trimmed), number.isFinite, number >= 0 else { return nil }
        switch self {
        case .memoryFootprint, .diskFree:
            return number * 1_073_741_824
        case .cpu, .chipTemperature, .memoryPressure:
            return number
        }
    }

    func displayThreshold(_ stored: Double) -> String {
        switch self {
        case .memoryFootprint, .diskFree:
            return AlertThresholdText.plain(stored / 1_073_741_824)
        case .memoryPressure:
            return ""
        case .cpu, .chipTemperature:
            return AlertThresholdText.plain(stored)
        }
    }
}

enum AlertThresholdText {
    static func plain(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value.rounded() == value, abs(value) < 1_000_000_000 {
            return "\(Int(value))"
        }
        return String(format: "%.2f", value)
    }

    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value.rounded() == value, abs(value) < 1_000_000 {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }

    static func degrees(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value.rounded() == value, abs(value) < 1_000_000 {
            return "\(Int(value)) °C"
        }
        return String(format: "%.1f °C", value)
    }
}

enum AlertRuleCopy {
    static let sectionTitle = "告警规则"
    static let addButton = "添加告警规则"
    static let saveButton = "保存告警规则"
    static let builtinNote = "内置规则，不能删除"
    static let incomplete = "这个告警规则还不完整"
    static let emptyCustom = "还没有自定义告警规则"
}

/// A rule the user added. The builtin memory-pressure rule is not one of these.
struct CustomAlertRule: Equatable, Sendable, Codable, Identifiable {
    static let defaultCooldown: TimeInterval = 1_800
    static let defaultDailyLimit = 3
    static let defaultDuration: TimeInterval = 300

    var id: String
    var enabled: Bool
    var object: AlertObject
    var metric: AlertMetric
    var threshold: Double
    var duration: TimeInterval
    var cooldown: TimeInterval
    var dailyLimit: Int

    var isValid: Bool {
        guard !id.isEmpty, id != AlertRule.memoryPressure.id else { return false }
        guard threshold.isFinite, duration >= 0, cooldown >= 0, dailyLimit >= 1 else { return false }
        switch object {
        case .machine:
            return true
        case .app(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, name == trimmed else { return false }
            return metric == .cpu || metric == .memoryFootprint
        }
    }

    var notificationBody: String {
        switch metric {
        case .cpu:
            return "\(object.phrase) CPU 已持续超过 \(AlertThresholdText.percent(threshold))"
        case .memoryFootprint:
            let bytes = UInt64(max(threshold, 0))
            return "\(object.phrase)内存占用已持续超过 \(ByteFormat.memory(bytes))"
        case .memoryPressure:
            return "\(object.phrase)内存压力已持续偏高"
        case .chipTemperature:
            return "\(object.phrase)芯片温度已持续超过 \(AlertThresholdText.degrees(threshold))"
        case .diskFree:
            let bytes = UInt64(max(threshold, 0))
            return "\(object.phrase)磁盘剩余已持续低于 \(ByteFormat.memory(bytes))"
        }
    }

    var listDetail: String {
        let hold = Int(duration / 60)
        let cool = Int(cooldown / 60)
        return "持续 \(hold) 分钟 · 冷却 \(cool) 分钟 · 每日 \(dailyLimit) 次"
    }

    static func make(
        id: String,
        enabled: Bool = true,
        object: AlertObject = .machine,
        metric: AlertMetric = .cpu,
        threshold: Double = 80,
        duration: TimeInterval = defaultDuration,
        cooldown: TimeInterval = defaultCooldown,
        dailyLimit: Int = defaultDailyLimit
    ) -> CustomAlertRule {
        CustomAlertRule(
            id: id,
            enabled: enabled,
            object: object,
            metric: metric,
            threshold: threshold,
            duration: duration,
            cooldown: cooldown,
            dailyLimit: dailyLimit
        )
    }

    func advance(
        state: AlertRule.State,
        breached: Bool?,
        at date: Date,
        calendar: Calendar = .current
    ) -> AlertRule.Decision {
        let machine = AlertRule(
            id: id,
            builtin: false,
            rearm: 0,
            cooldown: cooldown,
            dailyLimit: dailyLimit
        )
        return machine.advance(
            enabled: enabled,
            state: state,
            breached: breached,
            at: date,
            duration: duration,
            calendar: calendar
        )
    }

    func measure(_ frame: AlertFrame) -> AlertMeasurement {
        switch object {
        case .machine:
            return measureMachine(frame)
        case .app(let name):
            return measureApp(name, frame)
        }
    }

    private func measureMachine(_ frame: AlertFrame) -> AlertMeasurement {
        switch metric {
        case .cpu:
            return AlertMeasurement(
                breached: AlertComparison.breached(metric: metric, threshold: threshold, value: finite(frame.systemCpuPercent)),
                pid: AlertComparison.busiestCPU(in: frame.processes)
            )
        case .memoryFootprint:
            return AlertMeasurement(
                breached: AlertComparison.breached(
                    metric: metric,
                    threshold: threshold,
                    value: frame.usedMemoryBytes.map { Double($0) }
                ),
                pid: AlertComparison.heaviestMemory(in: frame.processes)
            )
        case .memoryPressure:
            return AlertMeasurement(
                breached: AlertComparison.breached(
                    metric: metric,
                    threshold: threshold,
                    value: AlertComparison.pressureValue(frame.memoryPressure)
                ),
                pid: AlertComparison.heaviestMemory(in: frame.processes)
            )
        case .chipTemperature:
            return AlertMeasurement(
                breached: AlertComparison.breached(
                    metric: metric,
                    threshold: threshold,
                    value: finite(frame.chipTemperatureCelsius)
                ),
                pid: nil
            )
        case .diskFree:
            return AlertMeasurement(
                breached: AlertComparison.breached(
                    metric: metric,
                    threshold: threshold,
                    value: frame.diskFreeBytes.map { Double($0) }
                ),
                pid: nil
            )
        }
    }

    private func measureApp(_ name: String, _ frame: AlertFrame) -> AlertMeasurement {
        let matches = frame.processes.filter { $0.name == name }
        switch metric {
        case .cpu:
            let ranked = matches.compactMap { sample -> (pid: Int32, value: Double)? in
                guard let cpu = finite(sample.cpuPercent) else { return nil }
                return (sample.pid, cpu)
            }
            guard let best = AlertComparison.pickHighest(ranked) else {
                return AlertMeasurement(breached: nil, pid: nil)
            }
            return AlertMeasurement(
                breached: AlertComparison.breached(metric: .cpu, threshold: threshold, value: best.value),
                pid: best.pid
            )
        case .memoryFootprint:
            let ranked = matches.compactMap { sample -> (pid: Int32, value: Double)? in
                guard let bytes = sample.memoryBytes else { return nil }
                return (sample.pid, Double(bytes))
            }
            guard let best = AlertComparison.pickHighest(ranked) else {
                return AlertMeasurement(breached: nil, pid: nil)
            }
            return AlertMeasurement(
                breached: AlertComparison.breached(metric: .memoryFootprint, threshold: threshold, value: best.value),
                pid: best.pid
            )
        case .memoryPressure, .chipTemperature, .diskFree:
            return AlertMeasurement(breached: nil, pid: nil)
        }
    }

    private func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}

struct AlertRuleCatalog: Equatable, Sendable {
    var custom: [CustomAlertRule]

    static let empty = AlertRuleCatalog(custom: [])

    func adding(_ rule: CustomAlertRule) -> AlertRuleCatalog {
        guard rule.isValid, !custom.contains(where: { $0.id == rule.id }) else { return self }
        var next = self
        next.custom.append(rule)
        return next
    }

    func replacing(_ rule: CustomAlertRule) -> AlertRuleCatalog {
        guard rule.isValid, let index = custom.firstIndex(where: { $0.id == rule.id }) else { return self }
        var next = self
        next.custom[index] = rule
        return next
    }

    /// Builtin id is refused. Unknown ids leave the list unchanged.
    func removing(id: String) -> AlertRuleCatalog {
        guard id != AlertRule.memoryPressure.id else { return self }
        var next = self
        next.custom.removeAll { $0.id == id }
        return next
    }

    /// Builtin enabled state stays on `pulse.pressureNotice`, not in this list.
    func settingEnabled(id: String, enabled: Bool) -> AlertRuleCatalog {
        guard id != AlertRule.memoryPressure.id else { return self }
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return self }
        var next = self
        next.custom[index].enabled = enabled
        return next
    }
}

enum AlertRuleStore {
    static let defaultsKey = "pulse.alertRules"

    static func catalog(stored: String) -> AlertRuleCatalog {
        guard !stored.isEmpty, let data = stored.data(using: .utf8) else { return .empty }
        guard let decoded = try? JSONDecoder().decode([CustomAlertRule].self, from: data) else { return .empty }
        return AlertRuleCatalog(custom: decoded.filter(\.isValid))
    }

    static func stored(_ catalog: AlertRuleCatalog) -> String {
        let valid = catalog.custom.filter(\.isValid)
        guard let data = try? JSONEncoder().encode(valid),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}

struct AlertProcessSample: Equatable, Sendable {
    var pid: Int32
    var name: String
    var cpuPercent: Double?
    var memoryBytes: UInt64?
}

/// One accepted sample. Nil fields are missing, not zero.
struct AlertFrame: Equatable, Sendable {
    var systemCpuPercent: Double? = nil
    var usedMemoryBytes: UInt64? = nil
    var memoryPressure: PressureLevel? = nil
    var chipTemperatureCelsius: Double? = nil
    var diskFreeBytes: UInt64? = nil
    var processes: [AlertProcessSample] = []
}

struct AlertMeasurement: Equatable, Sendable {
    var breached: Bool?
    var pid: Int32?
}

enum AlertComparison {
    /// Nil value stays nil. Disk free is strictly below. Everything else is strictly above.
    /// Memory pressure uses 1 for elevated and 0 for normal, and breaches only above 0.
    static func breached(metric: AlertMetric, threshold: Double, value: Double?) -> Bool? {
        guard let value, value.isFinite, threshold.isFinite else { return nil }
        switch metric {
        case .diskFree:
            return value < threshold
        case .memoryPressure:
            return value > 0
        case .cpu, .memoryFootprint, .chipTemperature:
            return value > threshold
        }
    }

    static func pressureValue(_ level: PressureLevel?) -> Double? {
        switch level {
        case .elevated: return 1
        case .normal: return 0
        case nil: return nil
        }
    }

    static func busiestCPU(in processes: [AlertProcessSample]) -> Int32? {
        let ranked = processes.compactMap { sample -> (pid: Int32, value: Double)? in
            guard let cpu = sample.cpuPercent, cpu.isFinite else { return nil }
            return (sample.pid, cpu)
        }
        return pickHighest(ranked)?.pid
    }

    static func heaviestMemory(in processes: [AlertProcessSample]) -> Int32? {
        let ranked = processes.compactMap { sample -> (pid: Int32, value: Double)? in
            guard let bytes = sample.memoryBytes else { return nil }
            return (sample.pid, Double(bytes))
        }
        return pickHighest(ranked)?.pid
    }

    static func pickHighest(_ samples: [(pid: Int32, value: Double)]) -> (pid: Int32, value: Double)? {
        var best: (pid: Int32, value: Double)?
        for sample in samples {
            guard let current = best else {
                best = sample
                continue
            }
            if sample.value > current.value || (sample.value == current.value && sample.pid < current.pid) {
                best = sample
            }
        }
        return best
    }
}

struct AlertNotice: Equatable, Sendable {
    var id: String
    var body: String
    var page: DashboardPage
    var pid: Int32?
}

/// Click payload stored on a custom notification. Builtin pressure does not use it.
struct AlertNoticeRoute: Equatable, Sendable {
    static let pageKey = "pulse.alert.page"
    static let pidKey = "pulse.alert.pid"

    var page: DashboardPage
    var pid: Int32?

    static func decode(page: String?, pid: String?) -> AlertNoticeRoute? {
        guard let page, let resolved = DashboardPage(rawValue: page) else { return nil }
        guard let pid, !pid.isEmpty else {
            return AlertNoticeRoute(page: resolved, pid: nil)
        }
        guard let value = Int32(pid) else { return nil }
        return AlertNoticeRoute(page: resolved, pid: value)
    }
}

/// Custom rules only. Builtin pressure stays on `AlertRule.memoryPressure.advance`.
struct AlertRuleEngine: Equatable, Sendable {
    private(set) var states: [String: AlertRule.State] = [:]

    mutating func evaluate(
        rules: [CustomAlertRule],
        frame: AlertFrame,
        at date: Date,
        calendar: Calendar = .current
    ) -> [AlertNotice] {
        var notices: [AlertNotice] = []
        for rule in rules {
            let prior = states[rule.id] ?? .armed
            let measurement = rule.measure(frame)
            let decision = rule.advance(
                state: prior,
                breached: measurement.breached,
                at: date,
                calendar: calendar
            )
            states[rule.id] = decision.state
            guard decision.send else { continue }
            notices.append(
                AlertNotice(
                    id: rule.id,
                    body: rule.notificationBody,
                    page: rule.metric.page,
                    pid: measurement.pid
                )
            )
        }
        return notices
    }
}
