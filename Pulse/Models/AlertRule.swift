import Foundation

/// Pure 告警规则 state machine. The builtin memory-pressure rule matches the old notice,
/// including a 5-minute rearm. It does not use a 30-minute cooldown.
struct AlertRule: Equatable, Sendable {
    struct State: Equatable, Sendable {
        enum Phase: Equatable, Sendable {
            case armed
            case fired(clearSince: Date?)
        }

        var phase: Phase
        var cooldownUntil: Date? = nil
        var sendsOnDay: Int = 0
        var dayStart: Date? = nil

        static let armed = State(phase: .armed)
    }

    struct Decision: Equatable, Sendable {
        var send: Bool
        var state: State
    }

    /// Stable id. The builtin id is the `pulse.pressureNotice` defaults key.
    var id: String
    /// The memory-pressure rule cannot be removed. Custom rules are not builtin.
    var builtin: Bool
    /// Continuous normal readings for this long return a fired episode to armed.
    var rearm: TimeInterval
    /// Minimum gap after a send before the next episode may notify. Zero adds no extra wait.
    var cooldown: TimeInterval
    /// Nil means no daily cap.
    var dailyLimit: Int?

    /// Builtin memory pressure. Five minutes of continuous normal rearms it.
    /// Cooldown stays 0 and there is no daily cap, so an old install behaves the same.
    static let memoryPressure = AlertRule(
        id: "pulse.pressureNotice",
        builtin: true,
        rearm: 300,
        cooldown: 0,
        dailyLimit: nil
    )

    func advance(
        enabled: Bool,
        state: State,
        pressure: PressureLevel?,
        at date: Date,
        calendar: Calendar = .current
    ) -> Decision {
        guard enabled, let pressure else {
            return Decision(send: false, state: state)
        }
        var next = state
        if dailyLimit != nil {
            let start = calendar.startOfDay(for: date)
            if next.dayStart != start {
                next.dayStart = start
                next.sendsOnDay = 0
            }
        }
        switch (next.phase, pressure) {
        case (.armed, .elevated):
            if let until = next.cooldownUntil, date < until {
                return Decision(send: false, state: next)
            }
            if let limit = dailyLimit, next.sendsOnDay >= limit {
                return Decision(send: false, state: next)
            }
            next.phase = .fired(clearSince: nil)
            if dailyLimit != nil {
                next.sendsOnDay += 1
            }
            if cooldown > 0 {
                next.cooldownUntil = date.addingTimeInterval(cooldown)
            }
            return Decision(send: true, state: next)
        case (.armed, .normal):
            return Decision(send: false, state: next)
        case (.fired, .elevated):
            next.phase = .fired(clearSince: nil)
            return Decision(send: false, state: next)
        case (.fired(let clearSince), .normal):
            let started = clearSince ?? date
            if date.timeIntervalSince(started) >= rearm {
                next.phase = .armed
            } else {
                next.phase = .fired(clearSince: started)
            }
            return Decision(send: false, state: next)
        }
    }
}

enum PressureNoticeCopy {
    static let permissionDenied = "系统通知未授权"

    static func body(heaviestAppName: String?) -> String {
        let base = "内存压力偏高，可以看看谁占得最多"
        guard let name = heaviestAppName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return base
        }
        return "\(base)：\(name)"
    }
}

/// A failed or unaccepted frame is not a reading. Retained snapshot pressure stays unused.
enum PressureNoticeReading {
    static func pressure(
        accepted: Bool,
        samplingFailed: Bool,
        snapshotPressure: PressureLevel?
    ) -> PressureLevel? {
        guard accepted, samplingFailed == false else { return nil }
        return snapshotPressure
    }
}

enum PressureNoticePreference {
    static let defaultsKey = AlertRule.memoryPressure.id

    /// Absent key stays on, so an upgrade notifies until the user turns it off.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}
