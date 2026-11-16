import Foundation

extension DashboardCore {
    /// Leave and enter apply here, before the next sample. Same-page calls do not write.
    mutating func publishGPUPageTransition(from previous: DashboardPage, to page: DashboardPage) {
        gpu.transition(from: previous, to: page, samplingFailed: samplingFailed)
    }

    /// The GPU slice of one accepted frame. Not a second read.
    static func gpuFrameInput(_ frame: SampledFrame) -> GPUFrameInput {
        GPUFrameInput(
            nodes: frame.gpuNodes,
            recommendedMaxWorkingSetBytes: frame.gpuRecommendedMaxWorkingSetBytes,
            energy: frame.cpuEnergy,
            shareClients: frame.gpuShareClients,
            rows: frame.rows,
            processListFailed: frame.processListFailed,
            sampledAt: frame.snapshot.capturedAt
        )
    }

    /// Replaces the display card. Nil or empty is 「—」 for the whole card.
    /// Not called from the sampling frame, and not written into history.
    mutating func apply(gpuDisplays readings: [GPUDisplayReading]?) -> [DashboardEffect] {
        gpu.apply(displays: readings)
        return []
    }

    /// Display list only. Utilization sampling stays on every page.
    func gpuDisplayWatchEffect(on page: DashboardPage) -> DashboardEffect {
        page == .gpu ? .startGPUDisplayWatch : .stopGPUDisplayWatch
    }

    /// GPU-share name. Only a pid still in the live process rows can open the memory page.
    func gpuShareNameOpensMemoryPage(_ pid: Int32) -> Bool {
        ProcessSelection.acceptedPid(pid, in: rows) != nil
    }

    /// Name tap. Present pid: `focusMemoryPage`, then select-if-present. Filters stay.
    /// A missing pid changes nothing.
    mutating func openGPUShareProcess(_ pid: Int32) -> [DashboardEffect] {
        guard let accepted = ProcessSelection.acceptedPid(pid, in: rows) else { return [] }
        var effects = focusMemoryPage()
        effects += select(pid: accepted)
        return effects
    }
}
