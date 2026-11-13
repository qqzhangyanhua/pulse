import Foundation

extension DashboardCore {
    mutating func setSymptomPanelOpen(_ open: Bool) -> [DashboardEffect] {
        symptomPanelOpen = open
        return []
    }
}
