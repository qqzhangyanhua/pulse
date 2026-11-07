import SwiftUI

struct MemoryDashboardView: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        Group {
            if vm.selectedPage == .machine {
                machinePage
            } else {
                resourcePage
            }
        }
        .background(PulsePalette.windowBackground)
        .navigationTitle("Pulse")
        .navigationSubtitle(vm.machineLabel ?? "机型读取中")
        .toolbar {
            ToolbarItem(placement: .principal) {
                ResourceTabs()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if vm.selectedPage != .machine {
                    if WindowedAppChrome.showsToggle(page: vm.selectedPage) {
                        Toggle(WindowedAppChrome.toggleTitle, isOn: $vm.windowedOnlyFilter)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help(WindowedAppChrome.help)
                    }
                    if AppGroupChrome.showsToggle(page: vm.selectedPage) {
                        Toggle(AppGroupChrome.toggleTitle, isOn: $vm.groupedByApp)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help(AppGroupChrome.help)
                    }
                    if MemoryRisingOnlyChrome.showsToggle(page: vm.selectedPage) {
                        Toggle(MemoryRisingOnlyChrome.toggleTitle, isOn: $vm.risingOnlyFilter)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help(MemoryGrowthListCopy.help)
                    }
                    AppFilterField(text: $vm.filter)
                }
            }
        }
        .toolbarBackground(PulsePalette.windowBackground, for: .windowToolbar)
        .onAppear { vm.start() }
    }

    private var machinePage: some View {
        MachineOverviewSection()
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PulsePalette.windowBackground)
    }

    private var resourcePage: some View {
        HSplitView {
            VStack(spacing: 12) {
                switch vm.selectedPage {
                case .cpu:
                    CPUOverviewSection()
                case .network:
                    NetworkOverviewSection()
                case .disk:
                    DiskOverviewSection()
                default:
                    OverviewSection()
                }
                ProcessTablePane()
            }
            .padding(12)
            .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PulsePalette.windowBackground)

            ProcessDetailSidebar()
                .frame(minWidth: 300, idealWidth: 332, maxWidth: 400)
        }
    }
}
