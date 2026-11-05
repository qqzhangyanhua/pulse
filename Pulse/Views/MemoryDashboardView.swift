import AppKit
import SwiftUI

struct MemoryDashboardView: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        VStack(spacing: 0) {
            ResourceTabs()
            Divider()
            OverviewSection()
            Divider()
            HSplitView {
                ProcessTablePane()
                    .frame(minWidth: 420)
                ProcessDetailSidebar()
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text(vm.machineLabel ?? "机型读取中")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { vm.start() }
    }
}
