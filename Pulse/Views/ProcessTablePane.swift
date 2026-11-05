import SwiftUI

private enum ProcessColumn {
    static let cpu: CGFloat = 96
    static let memory: CGFloat = 124
    static let threads: CGFloat = 64
}

private enum SortColumn {
    case name
    case cpu
    case memory
    case threads
}

struct ProcessTablePane: View {
    @EnvironmentObject private var vm: MemoryDashboardVM
    @State private var sortColumn: SortColumn = .memory
    @State private var sortDescending = true

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
        vm.visibleRows.sorted(using: vm.sortOrder)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sortHeader("名称", column: .name, defaultDescending: false, trailing: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortHeader("CPU", column: .cpu, defaultDescending: true, trailing: true)
                .frame(width: ProcessColumn.cpu, alignment: .trailing)
            sortHeader("内存", column: .memory, defaultDescending: true, trailing: true)
                .frame(width: ProcessColumn.memory, alignment: .trailing)
            sortHeader("线程", column: .threads, defaultDescending: true, trailing: true)
                .frame(width: ProcessColumn.threads, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }

    private var tableBody: some View {
        Group {
            if vm.loadState == .sampling, vm.rows.isEmpty {
                samplingPlaceholder
            } else if vm.processListFailed, vm.rows.isEmpty {
                AppEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "暂时无法列出进程",
                    message: "进程枚举失败，不会用空占用数字填充表格。",
                    retryTitle: "重新采样",
                    onRetry: vm.retrySampling
                )
            } else if vm.loadState == .failed, vm.rows.isEmpty {
                AppEmptyState(
                    systemImage: "waveform.path.ecg",
                    title: "进程列表还没有数据",
                    message: "总览采样没有返回，列表保持空态。",
                    retryTitle: "重新采样",
                    onRetry: vm.retrySampling
                )
            } else if sortedRows.isEmpty, vm.hasActiveFilter {
                filterEmpty
            } else if sortedRows.isEmpty {
                AppEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "没有可显示的进程",
                    message: "这一帧没有返回进程。"
                )
            } else {
                processList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var samplingPlaceholder: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    SkeletonBlock(height: 12)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("采样中…")
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
            ProcessLine(row: row, selected: vm.selectedPid == row.pid)
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

    private func sortHeader(
        _ title: String,
        column: SortColumn,
        defaultDescending: Bool,
        trailing: Bool
    ) -> some View {
        let active = sortColumn == column
        return Button {
            if active {
                sortDescending.toggle()
            } else {
                sortColumn = column
                sortDescending = defaultDescending
            }
            applySort()
        } label: {
            HStack(spacing: 3) {
                if trailing {
                    Spacer(minLength: 0)
                }
                Text(title)
                if active {
                    Image(systemName: sortDescending ? "chevron.down" : "chevron.up")
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

    private func applySort() {
        let order: SortOrder = sortDescending ? .reverse : .forward
        switch sortColumn {
        case .name:
            vm.sortOrder = [KeyPathComparator(\ProcessRow.name, order: order)]
        case .cpu:
            vm.sortOrder = [KeyPathComparator(\ProcessRow.cpuSortKey, order: order)]
        case .memory:
            vm.sortOrder = [KeyPathComparator(\ProcessRow.memoryBytes, order: order)]
        case .threads:
            vm.sortOrder = [KeyPathComparator(\ProcessRow.threadCount, order: order)]
        }
    }
}

private struct ProcessLine: View {
    let row: ProcessRow
    var selected: Bool

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
            Text("\(row.threadCount)")
                .monospacedDigit()
                .frame(width: ProcessColumn.threads, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(row.name)，CPU \(ByteFormat.cpu(row.cpuPercent))，内存 \(ByteFormat.memory(row.memoryBytes))，\(row.threadCount) 线程"
        )
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
