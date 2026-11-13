import Foundation

extension MemoryDashboardVM {
    /// Every click terminates this pid, with no confirm dialog. A selected process-page pid finishes that session only when `ordinaryTerminate` issues one.
    func terminateThermalAdvice(pid: Int32) async {
        await runCore { $0.beginThermalTerminate(pid: pid) }
    }
}
