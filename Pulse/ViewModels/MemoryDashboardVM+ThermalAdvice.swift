import Foundation

extension MemoryDashboardVM {
    /// Terminates this pid. A paused pid asks to continue first. A selected process-page pid finishes that session only when `ordinaryTerminate` issues one.
    func terminateThermalAdvice(pid: Int32) async {
        await runCore { $0.beginThermalTerminate(pid: pid) }
    }
}
