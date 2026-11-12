import Foundation

enum EnergyPagePhase: Equatable, Sendable {
    case sampling
    case processListFailed
    case sampleFailed
    case empty
    case filteredEmpty
    case ready
}

enum EnergyPageCopy {
    static let headline = ""
    static let explanation = ""
    static let samplingTitle = ""
    static let processListFailedTitle = ""
    static let processListFailedMessage = ""
    static let sampleFailedTitle = ""
    static let sampleFailedMessage = ""
    static let emptyTitle = ""
    static let emptyMessage = ""
    static let filteredEmptyTitle = ""
    static let filteredEmptyMessage = ""
    static let filteredEmptyButton = ""
    static let retry = ""
    static let impactTitle = ""
    static let wakeTitle = ""
    static let columns: [String] = []
}

enum EnergyPage {
    static func filtered(_ rows: [ProcessRow], query: String) -> [ProcessRow] {
        _ = query
        return rows
    }

    static func ordered(
        _ rows: [ProcessRow],
        rates: [Int32: ProcessEnergyRates],
        sort: ProcessTableSort
    ) -> [ProcessRow] {
        _ = (rates, sort)
        return rows
    }

    static func phase(
        loadState: LoadState,
        processCount: Int,
        visibleCount: Int,
        hasActiveNameFilter: Bool,
        processListFailed: Bool
    ) -> EnergyPagePhase {
        _ = (loadState, processCount, visibleCount, hasActiveNameFilter, processListFailed)
        return .ready
    }
}
