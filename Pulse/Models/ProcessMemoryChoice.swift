import Foundation

/// Which process-memory reading a row is showing.
enum ProcessMemorySource: Sendable, Equatable, Hashable {
    case footprint
    case resident
}

/// Footprint when that read succeeded, including a real zero. Resident only when footprint is nil.
struct ProcessMemoryChoice: Equatable, Sendable {
    let bytes: UInt64
    let source: ProcessMemorySource

    static func project(footprint: UInt64?, resident: UInt64) -> ProcessMemoryChoice {
        if let footprint {
            return ProcessMemoryChoice(bytes: footprint, source: .footprint)
        }
        return ProcessMemoryChoice(bytes: resident, source: .resident)
    }
}
