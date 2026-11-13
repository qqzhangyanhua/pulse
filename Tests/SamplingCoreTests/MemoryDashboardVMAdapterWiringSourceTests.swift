import XCTest
@testable import SamplingCore

/// Source guard for the dashboard adapter. Does not instantiate `MemoryDashboardVM`.
final class MemoryDashboardVMAdapterWiringSourceTests: XCTestCase {
    func testAdapterPublishesOnlyCoreAndDoesNotAssignMovedState() throws {
        let source = try WiringSourceText.text(for: "MemoryDashboardVM")
        XCTAssertEqual(occurrenceCount(of: "@Published", in: source), 1)
        XCTAssertTrue(source.contains("@Published private(set) var core"))

        for field in movedStateFields {
            XCTAssertFalse(
                assigns(field, in: source),
                "adapter must not assign \(field)"
            )
        }
    }

    /// Stores that moved onto `DashboardCore`. Assigning `core` is the adapter path.
    private let movedStateFields = [
        "loadState",
        "snapshot",
        "systemCpuPercent",
        "busiestCorePercent",
        "cpuEnergy",
        "historyDraft",
        "pendingHistoryEvents",
        "lastHistoryPressure",
        "lastHistoryThermalName",
        "hostNetworkRates",
        "hostWiFi",
        "hostConnection",
        "ssidPermission",
        "publicIPRequest",
        "hostDiskRates",
        "rows",
        "energyWindowRates",
        "energyHourRates",
        "exitedEnergyProcesses",
        "energyLiveGenerations",
        "processListFailed",
        "processPermissionFootnote",
        "detail",
        "topMemorySeries",
        "quitOutcome",
        "sidebarSubjectPid",
        "samplingFailed",
        "usageHistory",
        "cpuHistory",
        "networkHistory",
        "diskHistory",
        "gpuPage",
        "chipTemperature",
        "machineFacts",
        "energyBatteryCard",
        "energyBatteryReading",
        "launchItems",
        "sleepAssertionsKnown",
        "symptomPanelOpen",
        "thermalNotice",
        "thermalAdvice",
        "thermalAdviceLastUpdate",
        "energyMachineHistory",
        "selectedPid",
        "navigation",
        "publication",
        "filter",
        "risingOnlyFilter",
        "windowedOnlyFilter",
        "groupedByApp",
        "topAppLocateReveal",
        "windowedPids",
        "selectedEnergyGeneration",
        "energyRankingSpan",
        "machineLabel",
        "isRetrying",
    ]

    private func assigns(_ field: String, in source: String) -> Bool {
        var search = source.startIndex
        while let range = source.range(of: field, range: search..<source.endIndex) {
            let boundary = range.lowerBound == source.startIndex
                || !isIdentifier(source[source.index(before: range.lowerBound)])
            if boundary, isAssignment(after: range.upperBound, in: source) {
                return true
            }
            search = range.upperBound
        }
        return false
    }

    private func isAssignment(after index: String.Index, in source: String) -> Bool {
        var cursor = index
        while cursor < source.endIndex, source[cursor] == " " || source[cursor] == "\t" {
            cursor = source.index(after: cursor)
        }
        guard cursor < source.endIndex, source[cursor] == "=" else { return false }
        let next = source.index(after: cursor)
        return next == source.endIndex || source[next] != "="
    }

    private func isIdentifier(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
