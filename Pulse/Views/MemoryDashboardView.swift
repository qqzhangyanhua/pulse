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
                        .help(AppGroupChrome.help)
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
