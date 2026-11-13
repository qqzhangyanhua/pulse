import Foundation

extension MemoryDashboardVM {
    /// Read on entry, then every 30 seconds while the machine page stays selected.
    func syncLaunchItemWatch() {
        guard selectedPage == .machine else {
            launchItemRefreshTask?.cancel()
            launchItemRefreshTask = nil
            return
        }
        guard launchItemRefreshTask == nil else { return }
        refreshLaunchItems()
        launchItemRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    break
                }
                guard let self else { return }
                self.refreshLaunchItems()
            }
        }
    }

    func refreshLaunchItems() {
        let next = LaunchItemReader.read()
        guard next != launchItems else { return }
        mutateCore { $0.apply(launchItems: next) }
    }
}
