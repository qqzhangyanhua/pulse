import Foundation

extension MemoryDashboardVM {
    /// Read on entry, then every 30 seconds while the energy page stays selected.
    func syncSleepAssertionWatch() {
        guard selectedPage == .energy else {
            sleepAssertionRefreshTask?.cancel()
            sleepAssertionRefreshTask = nil
            return
        }
        guard sleepAssertionRefreshTask == nil else { return }
        refreshSleepAssertions()
        sleepAssertionRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
                guard let self else { return }
                self.refreshSleepAssertions()
            }
        }
    }

    func refreshSleepAssertions() {
        guard let assertions = SleepAssertionReader.read() else { return }
        guard assertions != sleepAssertions else { return }
        mutateCore { $0.apply(sleepAssertions: assertions) }
    }
}
