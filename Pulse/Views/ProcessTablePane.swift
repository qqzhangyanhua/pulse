import SwiftUI

private enum ProcessColumn {
    static let cpu: CGFloat = 96
    static let memory: CGFloat = 124
    static let network: CGFloat = 80
    static let threads: CGFloat = 64
}

struct ProcessTablePane: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsColumnHeader {
                columnHeader
            }
            tableBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var showsColumnHeader: Bool {
        !vm.rows.isEmpty
    }

    private var sortedRows: [ProcessRow] {
        vm.tableSort.ordered(vm.visibleRows)
    }

    private var cpuPhase: CPUPagePhase {
        CPUPagePhaseResolver.resolve(
            loadState: vm.loadState,
            processCount: vm.rows.count,
            visibleCount: vm.visibleRows.count,
            hasActiveFilter: vm.hasActiveFilter,
            processListFailed: vm.processListFailed
        )
    }

    private var showsNetworkColumn: Bool {
        vm.selectedPage == .network
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sortHeader(ProcessColumnTitle.name, column: .name, trailing: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortHeader(ProcessColumnTitle.cpu, column: .cpu, trailing: true)
                .frame(width: ProcessColumn.cpu, alignment: .trailing)
            sortHeader(ProcessColumnTitle.memory, column: .memory, trailing: true)
                .frame(width: ProcessColumn.memory, alignment: .trailing)
            if showsNetworkColumn {
                staticHeader(ProcessColumnTitle.network)
                    .frame(width: ProcessColumn.network, alignment: .trailing)
            }
            sortHeader(ProcessColumnTitle.threads, column: .threads, trailing: true)
                .frame(width: ProcessColumn.threads, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }

    private var tableBody: some View {
        Group {
            switch vm.selectedPage {
            case .cpu:
                resourceTableBody(
                    sampling: CPUPageCopy.sampling,
                    failureTitle: CPUPageCopy.failureTitle,
                    failureMessage: CPUPageCopy.failureMessage,
                    retryTitle: CPUPageCopy.retry,
                    emptyTitle: CPUPageCopy.emptyTitle,
                    emptyMessage: CPUPageCopy.emptyMessage,
                    systemImage: "cpu"
                )
            case .network:
                resourceTableBody(
                    sampling: NetworkPageCopy.sampling,
                    failureTitle: NetworkPageCopy.failureTitle,
                    failureMessage: NetworkPageCopy.failureMessage,
                    retryTitle: NetworkPageCopy.retry,
                    emptyTitle: NetworkPageCopy.emptyTitle,
                    emptyMessage: NetworkPageCopy.emptyMessage,
                    systemImage: "network"
                )
            default:
                memoryTableBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var memoryTableBody: some View {
        Group {
            if vm.loadState == .sampling, vm.rows.isEmpty {
                samplingPlaceholder(status: "采样中…")
            } else if vm.processListFailed, vm.rows.isEmpty {
                AppEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "暂时无法列出进程",
                    message: "这轮没读到进程列表，点重新采样再试。",
                    retryTitle: "重新采样",
                    onRetry: vm.retrySampling
                )
            } else if vm.loadState == .failed, vm.rows.isEmpty {
                AppEmptyState(
                    systemImage: "waveform.path.ecg",
                    title: "进程列表还没有数据",
                    message: "总览还没回来，列表先空着。",
                    retryTitle: "重新采样",
                    onRetry: vm.retrySampling
                )
            } else if sortedRows.isEmpty, vm.hasActiveFilter {
                filterEmpty
            } else if sortedRows.isEmpty {
                AppEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "没有可显示的进程",
                    message: "这一帧没有进程可显示。"
                )
            } else {
                processList
            }
        }
    }

    @ViewBuilder
    private func resourceTableBody(
        sampling: String,
        failureTitle: String,
        failureMessage: String,
        retryTitle: String,
        emptyTitle: String,
        emptyMessage: String,
        systemImage: String
    ) -> some View {
        switch cpuPhase {
        case .sampling:
            samplingPlaceholder(status: sampling)
        case .failed:
            AppEmptyState(
                systemImage: systemImage,
                title: failureTitle,
                message: failureMessage,
                retryTitle: retryTitle,
                onRetry: vm.retrySampling
            )
        case .empty:
            AppEmptyState(
                systemImage: "list.bullet.rectangle",
                title: emptyTitle,
                message: emptyMessage
            )
        case .filteredEmpty:
            filterEmpty
        case .ready:
            processList
        }
    }

    private func samplingPlaceholder(status: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonBlock(height: 12)
                        .frame(maxWidth: .infinity)
                }
            }
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
            if vm.hasActiveFilter {
                Text("没有匹配的 App")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var filterEmpty: some View {
        VStack(spacing: 8) {
            Text("没有匹配的 App")
                .font(.headline)
            Text("换个名称试试，或清空过滤。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("清空过滤") {
                vm.filter = ""
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var processList: some View {
        List(sortedRows, selection: $vm.selectedPid) { row in
            ProcessLine(
                row: row,
                selected: vm.selectedPid == row.pid,
                showsNetwork: showsNetworkColumn
            )
                .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                .listRowSeparator(.hidden)
                .listRowBackground(rowBackground(vm.selectedPid == row.pid))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .tint(PulsePalette.selection)
    }

    private func rowBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? PulsePalette.selection : Color.clear)
    }

    private func staticHeader(_ title: String) -> some View {
        HStack(spacing: 3) {
            Spacer(minLength: 0)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(Color.secondary)
    }

    private func sortHeader(
        _ title: String,
        column: ProcessSortColumn,
        trailing: Bool
    ) -> some View {
        let active = vm.tableSort.column == column
        return Button {
            vm.setTableSort(vm.tableSort.selecting(column))
        } label: {
            HStack(spacing: 3) {
                if trailing {
                    Spacer(minLength: 0)
                }
                Text(title)
                if active {
                    Image(systemName: vm.tableSort.descending ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                }
                if !trailing {
                    Spacer(minLength: 0)
                }
            }
            .font(.caption)
            .foregroundStyle(active ? Color.white.opacity(0.88) : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct ProcessLine: View {
    let row: ProcessRow
    var selected: Bool
    var showsNetwork: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ProcessIconView(pid: row.pid, bundleIdentifier: row.bundleIdentifier, size: 16)
                Text(row.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            metric(ByteFormat.cpu(row.cpuPercent), dot: PulsePalette.chartCPU)
                .frame(width: ProcessColumn.cpu, alignment: .trailing)
            metric(ByteFormat.memory(row.memoryBytes), dot: PulsePalette.accent)
                .frame(width: ProcessColumn.memory, alignment: .trailing)
            if showsNetwork {
                Text(row.networkAvailability.label)
                    .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.secondary)
                    .frame(width: ProcessColumn.network, alignment: .trailing)
            }
            Text("\(row.threadCount)")
                .monospacedDigit()
                .frame(width: ProcessColumn.threads, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [
            row.name,
            "CPU \(ByteFormat.cpu(row.cpuPercent))",
            "内存 \(ByteFormat.memory(row.memoryBytes))",
        ]
        if showsNetwork {
            parts.append("网络 \(row.networkAvailability.label)")
        }
        parts.append("\(row.threadCount) 线程")
        return parts.joined(separator: "，")
    }

    private func metric(_ text: String, dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(text)
                .monospacedDigit()
        }
    }
}
