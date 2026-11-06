import Foundation

enum TopAppLocation {
    enum NameFilterWrite: Equatable, Sendable {
        case keep
        case replace(String)
    }

    struct Reveal: Equatable, Sendable {
        var pid: Int32
        var generation: UInt64
    }

    struct Plan: Equatable, Sendable {
        var nameFilter: NameFilterWrite
        var risingOnly: Bool
        var acceptedPid: Int32
        var reveal: Reveal
    }

    static func plan(
        name: String,
        pid: Int32,
        rows: [ProcessRow],
        page: DashboardPage,
        currentFilter: String,
        currentRisingOnly: Bool,
        previousReveal: Reveal?
    ) -> Plan? {
        _ = currentRisingOnly
        guard page == .memory else { return nil }
        guard let accepted = ProcessSelection.acceptedPid(pid, in: rows) else { return nil }
        guard rows.first(where: { $0.pid == accepted })?.name == name else { return nil }

        let nameFilter: NameFilterWrite
        if currentFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nameFilter = .keep
        } else if currentFilter == name {
            nameFilter = .keep
        } else {
            nameFilter = .replace(name)
        }

        return Plan(
            nameFilter: nameFilter,
            risingOnly: false,
            acceptedPid: accepted,
            reveal: Reveal(
                pid: accepted,
                generation: (previousReveal?.generation ?? 0) &+ 1
            )
        )
    }
}
