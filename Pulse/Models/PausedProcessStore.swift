import Foundation

/// Thin `UserDefaults` adapter. Tests talk to `PausedProcessLedger`, not this key.
enum PausedProcessStore {
    static let key = "pulse.pausedProcesses"

    static func load(from defaults: UserDefaults = .standard) -> PausedProcessLedger {
        guard let items = defaults.array(forKey: key) else { return PausedProcessLedger() }
        var ledger = PausedProcessLedger()
        for item in items {
            guard let fields = item as? [String: Any],
                  let pid = intValue(fields["pid"]),
                  let start = intValue(fields["startTimeSeconds"])
            else { continue }
            ledger.record(pid: Int32(pid), startTimeSeconds: UInt64(start))
        }
        return ledger
    }

    static func save(_ ledger: PausedProcessLedger, to defaults: UserDefaults = .standard) {
        if ledger.records.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        let items: [[String: Int]] = ledger.records.map {
            ["pid": Int($0.pid), "startTimeSeconds": Int($0.startTimeSeconds)]
        }
        defaults.set(items, forKey: key)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
