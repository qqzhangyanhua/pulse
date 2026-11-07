import AppKit

/// Mac-only policy check. A missing application, an accessory, or a prohibited agent is not windowed.
enum WindowedAppLookup {
    static func pids(in rows: [ProcessRow]) -> Set<Int32> {
        var windowed: Set<Int32> = []
        windowed.reserveCapacity(rows.count)
        for row in rows {
            guard let app = NSRunningApplication(processIdentifier: row.pid),
                  app.activationPolicy == .regular
            else { continue }
            windowed.insert(row.pid)
        }
        return windowed
    }
}
