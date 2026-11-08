import Foundation

enum PressureNoticePhase: Equatable, Sendable {
    case armed
    case fired(normalSince: Date?)
}

struct PressureNoticeDecision: Equatable, Sendable {
    let send: Bool
    let phase: PressureNoticePhase
}

enum PressureNotice {
    /// Continuous normal readings for this long return a fired episode to armed.
    private static let rearmInterval: TimeInterval = 300

    static func advance(
        enabled: Bool,
        phase: PressureNoticePhase,
        pressure: PressureLevel?,
        at date: Date
    ) -> PressureNoticeDecision {
        guard enabled, let pressure else {
            return PressureNoticeDecision(send: false, phase: phase)
        }
        switch (phase, pressure) {
        case (.armed, .elevated):
            return PressureNoticeDecision(send: true, phase: .fired(normalSince: nil))
        case (.armed, .normal):
            return PressureNoticeDecision(send: false, phase: .armed)
        case (.fired, .elevated):
            return PressureNoticeDecision(send: false, phase: .fired(normalSince: nil))
        case (.fired(let normalSince), .normal):
            let started = normalSince ?? date
            if date.timeIntervalSince(started) >= rearmInterval {
                return PressureNoticeDecision(send: false, phase: .armed)
            }
            return PressureNoticeDecision(send: false, phase: .fired(normalSince: started))
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
    static let defaultsKey = "pulse.pressureNotice"

    /// Absent key stays on, so an upgrade notifies until the user turns it off.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: defaultsKey) != nil else { return true }
        return defaults.bool(forKey: defaultsKey)
    }
}
