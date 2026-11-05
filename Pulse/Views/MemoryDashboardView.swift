import SwiftUI

struct MemoryDashboardView: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        HSplitView {
            VStack(spacing: 12) {
                OverviewSection()
                ProcessTablePane()
            }
            .padding(12)
            .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PulsePalette.windowBackground)

            ProcessDetailSidebar()
                .frame(minWidth: 300, idealWidth: 332, maxWidth: 400)
        }
        .background(PulsePalette.windowBackground)
        .navigationTitle("Pulse")
        .navigationSubtitle(vm.machineLabel ?? "机型读取中")
        .toolbar {
            ToolbarItem(placement: .principal) {
                ResourceTabs()
            }
            ToolbarItem(placement: .primaryAction) {
                AppFilterField(text: $vm.filter)
            }
        }
        .toolbarBackground(PulsePalette.windowBackground, for: .windowToolbar)
        .onAppear { vm.start() }
    }
}
