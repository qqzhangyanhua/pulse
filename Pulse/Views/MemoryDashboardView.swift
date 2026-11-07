import SwiftUI

struct MemoryDashboardView: View {
    @EnvironmentObject private var vm: MemoryDashboardVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var overviewPage: DashboardPage = .memory
    @State private var showingMachine = false

    var body: some View {
        Group {
            if showingMachine {
                machinePage.transition(.opacity)
            } else {
                resourcePage.transition(.opacity)
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
        .onAppear {
            vm.start()
            applyPageMotion(vm.selectedPage, animated: false)
        }
        .onChange(of: vm.selectedPage) { _, newPage in
            applyPageMotion(newPage, animated: !reduceMotion)
        }
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
                resourceOverview
                ProcessTablePane()
            }
            .padding(12)
            .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PulsePalette.windowBackground)

            ProcessDetailSidebar()
                .frame(minWidth: 300, idealWidth: 332, maxWidth: 400)
        }
    }

    /// Overview only. The process table follows the page immediately and does not fade.
    private var resourceOverview: some View {
        Group {
            switch overviewPage {
            case .cpu:
                CPUOverviewSection().transition(.opacity)
            case .network:
                NetworkOverviewSection().transition(.opacity)
            case .disk:
                DiskOverviewSection().transition(.opacity)
            default:
                OverviewSection().transition(.opacity)
            }
        }
    }

    private func applyPageMotion(_ page: DashboardPage, animated: Bool) {
        let update = {
            self.showingMachine = page == .machine
            self.overviewPage = page
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.2), update)
        } else {
            update()
        }
    }
}
