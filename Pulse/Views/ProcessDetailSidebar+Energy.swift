import SwiftUI

extension ProcessDetailSidebar {
    func energyDisplayReading(for pid: Int32) -> EnergyDisplayReading? {
        EnergyPage.display(
            rows: vm.visibleRows,
            windowRates: vm.activeEnergyRates,
            grouped: vm.groupedByApp && vm.selectedPage == .energy
        ).readings[pid]
    }

    @ViewBuilder
    func energyResourceDetail(_ energy: EnergyDetailProjection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SidebarMetric(
                systemImage: "bolt",
                title: ProcessEnergyText.impactTitle,
                tint: PulsePalette.chartCPU,
                value: ProcessEnergyText.watts(energy.watts),
                caption: ProcessEnergyText.caption(isPartial: energy.energyReadingIsPartial)
            )
            SidebarMetric(
                systemImage: "moon.zzz",
                title: ProcessEnergyText.wakeTitle,
                tint: PulsePalette.chartCPU,
                value: ProcessEnergyText.wakeups(energy.wakeupsPerSecond),
                caption: ProcessEnergyText.caption(isPartial: energy.wakeupReadingIsPartial)
            )
        }
    }

    /// Hidden when the only hour-ranking match for `selectedPid` has already exited.
    @ViewBuilder
    var quitControls: some View {
        if !vm.selectedEnergyExitedOnly {
            ProcessDetailSidebarQuitControls()
        }
    }
}
