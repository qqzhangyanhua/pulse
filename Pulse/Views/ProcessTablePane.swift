import SwiftUI

struct ProcessTablePane: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("筛选进程名称", text: $vm.filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                if vm.hasActiveFilter {
                    Text("\(vm.visibleRows.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            tableBody
        }
    }

    @ViewBuilder
    private var tableBody: some View {
        if vm.loadState == .sampling && vm.rows.isEmpty {
            AppEmptyState(
                systemImage: "hourglass",
                title: "正在采集进程列表",
                message: "第一帧快照尚未返回，列表保持空态。"
            )
        } else if vm.processListFailed && vm.rows.isEmpty {
            AppEmptyState(
                systemImage: "list.bullet.rectangle",
                title: "暂时无法列出进程",
                message: "进程枚举失败，不会用空占用数字填充表格。",
                retryTitle: "重新采样",
                onRetry: vm.retrySampling
            )
        } else if vm.visibleRows.isEmpty {
            AppEmptyState(
                systemImage: "magnifyingglass",
                title: "没有匹配的进程",
                message: "换个名称试试，或清空筛选。"
            )
        } else {
            Table(vm.visibleRows, selection: $vm.selectedPid, sortOrder: $vm.sortOrder) {
                TableColumn("名称", value: \.name) { row in
                    HStack(spacing: 8) {
                        ProcessIconView(pid: row.pid, bundleIdentifier: row.bundleIdentifier)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name)
                                .lineLimit(1)
                            Text("PID \(row.pid)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .width(min: 180, ideal: 260)

                TableColumn("CPU", value: \.cpuSortKey) { row in
                    Text(ByteFormat.cpu(row.cpuPercent))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 64, ideal: 76)

                TableColumn("内存", value: \.memoryBytes) { row in
                    Text(ByteFormat.memory(row.memoryBytes))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 92)

                TableColumn("线程", value: \.threadCount) { row in
                    Text("\(row.threadCount)")
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 52, ideal: 64)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}
