import SwiftUI

struct MemoryDashboardView: View {
    @EnvironmentObject private var vm: MemoryDashboardVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshotRefusal: String?

    var body: some View {
        Group {
            switch vm.selectedPage {
            case .machine:
                machinePage.transition(.opacity)
            case .gpu:
                gpuPage.transition(.opacity)
            default:
                resourcePage.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : PulseMotion.page, value: fullPageIdentity)
        .background(PulsePalette.windowBackground)
        .navigationTitle("Pulse")
        .navigationSubtitle(vm.machineLabel ?? "机型读取中")
        .toolbar {
            ToolbarItem(placement: .principal) {
                ResourceTabs()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let savedAt = Date()
                    if let message = vm.requestSaveCurrentSnapshot(savedAt: savedAt, calendar: .current, timeZone: .current) {
                        snapshotRefusal = message
                    }
                } label: {
                    Text("保存当前快照")
                }
                .accessibilityLabel("保存当前快照")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if !vm.selectedPage.isFullPage {
                    HStack(spacing: 8) {
                        if WindowedAppChrome.showsToggle(page: vm.selectedPage) {
                            MemoryToolbarSwitch(
                                title: WindowedAppChrome.toggleTitle,
                                systemImage: "macwindow",
                                isOn: $vm.windowedOnlyFilter
                            )
                            .help(WindowedAppChrome.help)
                        }
                        if AppGroupChrome.showsToggle(page: vm.selectedPage) {
                            MemoryToolbarSwitch(
                                title: AppGroupChrome.toggleTitle,
                                systemImage: "square.stack.3d.up",
                                isOn: $vm.groupedByApp
                            )
                            .help(AppGroupChrome.help(on: vm.selectedPage))
                        }
                        if MemoryRisingOnlyChrome.showsToggle(page: vm.selectedPage) {
                            MemoryToolbarSwitch(
                                title: MemoryRisingOnlyChrome.toggleTitle,
                                systemImage: "chart.line.uptrend.xyaxis",
                                isOn: $vm.risingOnlyFilter
                            )
                            .help(MemoryGrowthListCopy.help)
                        }
                        AppFilterField(text: $vm.filter)
                    }
                    .animation(reduceMotion ? nil : PulseMotion.page, value: vm.selectedPage)
                }
            }
        }
        .toolbarBackground(PulsePalette.windowBackground, for: .windowToolbar)
        .alert(
            snapshotRefusal ?? "",
            isPresented: Binding(
                get: { snapshotRefusal != nil },
                set: { if !$0 { snapshotRefusal = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        }
        .background {
            SnapshotExportSheetPresenter(store: vm.snapshotExportStore, vm: vm)
        }
        .onAppear {
            vm.start()
        }
    }

    /// Machine and GPU are full pages. Other resource switches stay inside `resourcePage`.
    private var fullPageIdentity: DashboardPage? {
        switch vm.selectedPage {
        case .machine, .gpu:
            return vm.selectedPage
        default:
            return nil
        }
    }

    private var machinePage: some View {
        fullPage(MachineOverviewSection())
    }

    private var gpuPage: some View {
        fullPage(GPUOverviewSection())
    }

    private func fullPage<Content: View>(_ content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PulsePalette.windowBackground)
    }

    @ViewBuilder
    private var resourcePage: some View {
        if vm.selectedPage == .energy {
            energyResourceColumn
        } else {
            HSplitView {
                resourceColumn
                ProcessDetailSidebar()
                    .frame(minWidth: 300, idealWidth: 332, maxWidth: 400)
            }
        }
    }

    private var energyResourceColumn: some View {
        HSplitView {
            VStack(spacing: 12) {
                if vm.energyBatteryCard != nil {
                    EnergyBatteryCardView()
                }
                EnergyHistoryChart()
                    .frame(height: 150)
                ProcessTablePane()
            }
            .padding(12)
            .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PulsePalette.windowBackground)
            ProcessDetailSidebar()
                .frame(minWidth: 300, idealWidth: 332, maxWidth: 400)
        }
    }

    private var resourceColumn: some View {
        VStack(spacing: 12) {
            resourceOverview
            ProcessTablePane()
        }
        .padding(12)
        .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PulsePalette.windowBackground)
    }

    /// Crossfade in a clipped slot. Memory is 148 + 12 + 104.
    /// Network is the 112-pt connection card, a 12-pt gap, and the 150-pt rate row.
    /// CPU and disk stay 150. The table is a sibling, so it only follows this height.
    private var resourceOverview: some View {
        let page = vm.selectedPage
        return ZStack(alignment: .topLeading) {
            switch page {
            case .energy:
                Color.clear
            case .gpu, .machine:
                Color.clear
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: overviewHeight(page), alignment: .top)
        .clipped()
        .animation(reduceMotion ? nil : PulseMotion.page, value: page)
    }

    private func overviewHeight(_ page: DashboardPage) -> CGFloat {
        switch page {
        case .cpu, .disk:
            150
        case .network:
            274
        case .energy:
            0
        case .gpu:
            0
        case .memory, .machine:
            264
        }
    }
}

/// macOS hides a `Toggle` title inside the unified toolbar, so the symbol and
/// the short label are drawn here. On fills the chip; off stays a hairline outline.
private struct MemoryToolbarSwitch: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isOn ? Color.white : Color.white.opacity(0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isOn ? PulsePalette.accent : Color.white.opacity(0.06))
            }
            .overlay {
                Capsule()
                    .strokeBorder(isOn ? Color.clear : PulsePalette.hairline, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "开" : "关")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
