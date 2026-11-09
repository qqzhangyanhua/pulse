import AppKit
import SwiftUI

private enum ProcessColumn {
    static let cpu: CGFloat = 96
    static let memory: CGFloat = 124
    static let network: CGFloat = 80
    static let disk: CGFloat = 108
    static let energy: CGFloat = 88
    static let wakeups: CGFloat = 96
    static let threads: CGFloat = 64
}

struct ProcessTablePane: View {
    @EnvironmentObject private var vm: MemoryDashboardVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsColumnHeader {
                columnHeader
                Divider()
                    .overlay(PulsePalette.hairline)
                    .padding(.horizontal, 4)
            }
            tableBody
            ProcessPermissionFootnoteLabel(sentence: vm.processPermissionFootnote, processListFailed: vm.processListFailed, showsProcessTable: showsReadyProcessList)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var showsColumnHeader: Bool {
        !vm.rows.isEmpty
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

    private var showsDiskColumns: Bool {
        vm.selectedPage == .disk
    }

    private var showsEnergyColumns: Bool {
        vm.selectedPage == .cpu
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sortHeader(ProcessColumnTitle.name, column: .name, trailing: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortHeader(ProcessColumnTitle.cpu, column: .cpu, trailing: true)
                .frame(width: ProcessColumn.cpu, alignment: .trailing)
            sortHeader(ProcessColumnTitle.memory, column: .memory, trailing: true)
                .frame(width: ProcessColumn.memory, alignment: .trailing)
            if showsEnergyColumns {
                sortHeader(ProcessColumnTitle.energy, column: .energy, trailing: true)
                    .frame(width: ProcessColumn.energy, alignment: .trailing)
                sortHeader(ProcessColumnTitle.wakeups, column: .wakeups, trailing: true)
                    .frame(width: ProcessColumn.wakeups, alignment: .trailing)
            }
            if showsNetworkColumn {
                staticHeader(ProcessColumnTitle.network)
                    .frame(width: ProcessColumn.network, alignment: .trailing)
            }
            if showsDiskColumns {
                sortHeader(ProcessColumnTitle.diskRead, column: .diskRead, trailing: true)
                    .frame(width: ProcessColumn.disk, alignment: .trailing)
                sortHeader(ProcessColumnTitle.diskWrite, column: .diskWrite, trailing: true)
                    .frame(width: ProcessColumn.disk, alignment: .trailing)
            }
            sortHeader(ProcessColumnTitle.threads, column: .threads, trailing: true)
                .frame(width: ProcessColumn.threads, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }

    private var tableBody: some View {
        Group {
            if showsReadyProcessList {
                processList
            } else {
                switch vm.selectedPage {
                case .cpu:
                    resourceTableBody(
                        sampling: CPUPageCopy.sampling,
                        failureTitle: CPUPageCopy.failureTitle,
                        failureMessage: CPUPageCopy.failureMessage,
                        emptyTitle: CPUPageCopy.emptyTitle,
                        emptyMessage: CPUPageCopy.emptyMessage,
                        systemImage: "cpu"
                    )
                case .network:
                    resourceTableBody(
                        sampling: NetworkPageCopy.sampling,
                        failureTitle: NetworkPageCopy.failureTitle,
                        failureMessage: NetworkPageCopy.failureMessage,
                        emptyTitle: NetworkPageCopy.emptyTitle,
                        emptyMessage: NetworkPageCopy.emptyMessage,
                        systemImage: "network"
                    )
                case .disk:
                    resourceTableBody(
                        sampling: DiskPageCopy.sampling,
                        failureTitle: DiskPageCopy.failureTitle,
                        failureMessage: DiskPageCopy.failureMessage,
                        emptyTitle: DiskPageCopy.emptyTitle,
                        emptyMessage: DiskPageCopy.emptyMessage,
                        systemImage: "internaldrive"
                    )
                default:
                    memoryTableBody
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var showsReadyProcessList: Bool {
        switch vm.selectedPage {
        case .cpu, .network, .disk: cpuPhase == .ready
        default: memoryPhase == .ready
        }
    }

    private var memoryPhase: MemoryTablePhase {
        MemoryTablePhaseResolver.resolve(
            page: vm.selectedPage,
            loadState: vm.loadState,
            processCount: vm.rows.count,
            visibleCount: vm.sortedRows.count,
            hasActiveNameFilter: vm.hasActiveFilter,
            risingOnly: vm.risingOnlyFilter,
            processListFailed: vm.processListFailed,
            windowedOnly: vm.windowedOnlyFilter
        )
    }

    private var memoryTableBody: some View {
        Group {
            switch memoryPhase {
            case .sampling:
                samplingPlaceholder(status: "采样中…")
            case .processListFailed:
                AppEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "暂时无法列出进程",
                    message: SamplingRetryChrome.processListFailedMessage,
                    retrying: vm.isRetrying,
                    onRetry: vm.retrySampling
                )
            case .failed:
                AppEmptyState(
                    systemImage: "waveform.path.ecg",
                    title: "进程列表还没有数据",
                    message: "总览还没回来，列表先空着。",
                    retrying: vm.isRetrying,
                    onRetry: vm.retrySampling
                )
            case .nameFilterEmpty:
                memoryFilterEmpty(phase: .nameFilterEmpty)
            case .risingOnlyEmpty:
                memoryFilterEmpty(phase: .risingOnlyEmpty)
            case .empty:
                AppEmptyState(
                    systemImage: "list.bullet.rectangle",
                    title: "没有可显示的进程",
                    message: "这一帧没有进程可显示。"
                )
            case .ready:
                processList
            }
        }
    }

    @ViewBuilder
    private func memoryFilterEmpty(phase: MemoryTablePhase) -> some View {
        if let lines = MemoryTableEmptyCopy.filterEmptyLines(for: phase) {
            VStack(spacing: 8) {
                Text(lines.title)
                    .font(.headline)
                Text(lines.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(lines.buttonTitle) {
                    vm.clearMemoryPageFilters()
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    @ViewBuilder
    private func resourceTableBody(
        sampling: String,
        failureTitle: String,
        failureMessage: String,
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
                retrying: vm.isRetrying,
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
            Text(CPUPageCopy.filteredEmptyTitle)
                .font(.headline)
            Text(CPUPageCopy.filteredEmptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(CPUPageCopy.filteredEmptyButton) {
                vm.filter = ""
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var processList: some View {
        ScrollViewReader { proxy in
            List(vm.sortedRows, selection: $vm.selectedPid) { row in
                ProcessLine(
                    row: row,
                    selected: vm.selectedPid == row.pid,
                    showsNetwork: showsNetworkColumn,
                    showsDisk: showsDiskColumns,
                    showsEnergy: showsEnergyColumns,
                    growthBadge: vm.memoryGrowthListBadge(for: row.pid)
                )
                    .contextMenu {
                        Button("复制") {
                            let line = ProcessRowCopy.line(page: vm.selectedPage, row: row)
                            let board = NSPasteboard.general
                            board.clearContents()
                            board.setString(line, forType: .string)
                        }
                    }
                    .id(row.pid)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(rowBackground(vm.selectedPid == row.pid))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tint(PulsePalette.selection)
            .onAppear { revealProcessListTarget(proxy) }
            .onChange(of: vm.processListScrollTarget) { _, _ in
                revealProcessListTarget(proxy)
            }
            .onChange(of: vm.topAppLocateReveal) { _, request in
                guard let request else { return }
                revealTopApp(request: request, proxy: proxy)
            }
        }
    }

    /// Step-1 `processListScrollTarget`: reveal the present selected pid, never a vanished one.
    private func revealProcessListTarget(_ proxy: ScrollViewProxy) {
        guard let target = vm.processListScrollTarget else { return }
        DispatchQueue.main.async {
            let move = { proxy.scrollTo(target, anchor: .center) }
            if self.reduceMotion {
                move()
            } else {
                withAnimation(.easeInOut(duration: 0.28), move)
            }
        }
    }

    private func revealTopApp(request: TopAppLocation.Reveal, proxy: ScrollViewProxy) {
        guard vm.sortedRows.contains(where: { $0.pid == request.pid }) else { return }
        DispatchQueue.main.async {
            let move = { proxy.scrollTo(request.pid, anchor: .center) }
            if self.reduceMotion {
                move()
            } else {
                withAnimation(.easeInOut(duration: 0.28), move)
            }
        }
    }

    private func rowBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? PulsePalette.selection : Color.clear)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
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
                        .contentTransition(.symbolEffect(.replace))
                        .transition(.opacity.combined(with: .scale(scale: 0.5)))
                }
                if !trailing {
                    Spacer(minLength: 0)
                }
            }
            .font(.caption)
            .foregroundStyle(active ? Color.white.opacity(0.88) : Color.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: vm.tableSort)
    }
}

private struct ProcessLine: View {
    let row: ProcessRow
    var selected: Bool
    var showsNetwork: Bool
    var showsDisk: Bool
    var showsEnergy: Bool
    /// Phase-6 chip. Per-row Top5 ∩ `.rising`; selection is not a gate. Nil paints nothing.
    var growthBadge: MemoryGrowthListBadge?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ProcessIconView(pid: row.pid, bundleIdentifier: row.bundleIdentifier, size: 16)
                Text(row.name)
                    .lineLimit(1)
                if let growthBadge {
                    MemoryGrowthRisingBadge(badge: growthBadge)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            metric(ByteFormat.cpu(row.cpuPercent), dot: PulsePalette.chartCPU)
                .frame(width: ProcessColumn.cpu, alignment: .trailing)
            metric(ByteFormat.memory(row.memoryBytes), dot: PulsePalette.accent)
                .frame(width: ProcessColumn.memory, alignment: .trailing)
            if showsNetwork {
                Text(row.networkAvailability.label)
                    .help(NetworkPageCopy.processRateHelp)
                    .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.secondary)
                    .frame(width: ProcessColumn.network, alignment: .trailing)
            }
            if showsDisk {
                diskCell(DiskRateText.string(row.diskReadBytesPerSecond))
                    .frame(width: ProcessColumn.disk, alignment: .trailing)
                diskCell(DiskRateText.string(row.diskWriteBytesPerSecond))
                    .frame(width: ProcessColumn.disk, alignment: .trailing)
            }
            if showsEnergy {
                diskCell(ProcessEnergyText.watts(row.energyWatts))
                    .frame(width: ProcessColumn.energy, alignment: .trailing)
                diskCell(ProcessEnergyText.wakeups(row.wakeupsPerSecond))
                    .frame(width: ProcessColumn.wakeups, alignment: .trailing)
            }
            Text("\(row.threadCount)")
                .monospacedDigit()
                .frame(width: ProcessColumn.threads, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
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
        if showsDisk {
            parts.append("\(DiskPageCopy.readTitle) \(DiskRateText.string(row.diskReadBytesPerSecond))")
            parts.append("\(DiskPageCopy.writeTitle) \(DiskRateText.string(row.diskWriteBytesPerSecond))")
        }
        if showsEnergy {
            parts.append("\(ProcessEnergyText.impactTitle) \(ProcessEnergyText.watts(row.energyWatts))")
            parts.append("\(ProcessEnergyText.wakeTitle) \(ProcessEnergyText.wakeups(row.wakeupsPerSecond))")
        }
        if let growthBadge {
            parts.append(growthBadge.help)
        }
        parts.append("\(row.threadCount) 线程")
        return parts.joined(separator: "，")
    }

    private func diskCell(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(selected ? Color.white.opacity(0.88) : Color.primary)
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

/// Calm selected-row chip. Secondary ink only; no red, flash, or click-through.
private struct MemoryGrowthRisingBadge: View {
    let badge: MemoryGrowthListBadge

    var body: some View {
        Text(badge.title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .help(badge.help)
            .accessibilityHidden(true)
            .layoutPriority(1)
    }
}
