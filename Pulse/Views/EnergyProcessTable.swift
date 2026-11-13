import AppKit
import SwiftUI

struct EnergyProcessTable: View {
    @EnvironmentObject private var vm: MemoryDashboardVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rankRows: [EnergyRankRow] {
        EnergyPage.ranked(
            span: vm.energyRankingSpan,
            rows: vm.rows,
            rates: vm.activeEnergyRates,
            exited: vm.exitedEnergyProcesses,
            nameQuery: vm.filter,
            grouped: vm.groupedByApp,
            sort: vm.tableSort
        )
    }

    private var phase: EnergyPagePhase {
        let counts = EnergyPage.phaseCounts(
            span: vm.energyRankingSpan,
            liveRowCount: vm.rows.count,
            exitedCount: vm.exitedEnergyProcesses.count,
            rankedCount: rankRows.count
        )
        return EnergyPage.phase(
            loadState: vm.loadState,
            processCount: counts.processCount,
            visibleCount: counts.visibleCount,
            hasActiveNameFilter: vm.hasActiveFilter,
            processListFailed: vm.processListFailed
        )
    }

    /// Exited rows are not tagged with `selectedPid`. A click on one does not select a live reuse.
    private var listSelection: Binding<String?> {
        Binding(
            get: {
                guard let pid = vm.selectedPid else { return nil }
                return rankRows.first { $0.isQuitTarget && $0.pid == pid }?.id
            },
            set: { newValue in
                guard let newValue else {
                    vm.select(pid: nil)
                    return
                }
                guard let entry = rankRows.first(where: { $0.id == newValue }), entry.isQuitTarget else {
                    return
                }
                vm.select(pid: entry.pid)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rankingSpanControl
            VStack(alignment: .leading, spacing: 4) {
                Text(EnergyPageCopy.headline(for: vm.energyRankingSpan))
                    .font(.headline)
                Text(EnergyPageCopy.explanation(for: vm.energyRankingSpan))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if showsColumnHeader {
                    columnHeader
                    Divider()
                        .overlay(PulsePalette.hairline)
                        .padding(.horizontal, 4)
                }
                tableBody
                ProcessPermissionFootnoteLabel(
                    sentence: vm.processPermissionFootnote,
                    processListFailed: vm.processListFailed,
                    showsProcessTable: phase == .ready
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var rankingSpanControl: some View {
        Picker("排行", selection: Binding(get: { vm.energyRankingSpan }, set: { vm.setEnergyRankingSpan($0) })) {
            Text("1 分钟").tag(EnergyRankingSpan.oneMinute)
            Text("1 小时").tag(EnergyRankingSpan.oneHour)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sortHeader(ProcessColumnTitle.name, column: .name, trailing: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortHeader(EnergyPageCopy.impactTitle, column: .energy, trailing: true)
                .frame(width: 96, alignment: .trailing)
            sortHeader(EnergyPageCopy.wakeTitle, column: .wakeups, trailing: true)
                .frame(width: 108, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
    }

    @ViewBuilder
    private var tableBody: some View {
        switch phase {
        case .sampling:
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonBlock(height: 12)
                            .frame(maxWidth: .infinity)
                    }
                }
                Text(EnergyPageCopy.samplingTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        case .processListFailed:
            AppEmptyState(
                systemImage: "list.bullet.rectangle",
                title: EnergyPageCopy.processListFailedTitle,
                message: EnergyPageCopy.processListFailedMessage,
                retrying: vm.isRetrying,
                onRetry: vm.retrySampling
            )
        case .sampleFailed:
            AppEmptyState(
                systemImage: "bolt",
                title: EnergyPageCopy.sampleFailedTitle,
                message: EnergyPageCopy.sampleFailedMessage,
                retrying: vm.isRetrying,
                onRetry: vm.retrySampling
            )
        case .empty:
            AppEmptyState(
                systemImage: "list.bullet.rectangle",
                title: EnergyPageCopy.emptyTitle,
                message: EnergyPageCopy.emptyMessage
            )
        case .filteredEmpty:
            VStack(spacing: 8) {
                Text(EnergyPageCopy.filteredEmptyTitle)
                    .font(.headline)
                Text(EnergyPageCopy.filteredEmptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(EnergyPageCopy.filteredEmptyButton) {
                    vm.setFilter("")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        case .ready:
            List(rankRows, selection: listSelection) { entry in
                EnergyProcessLine(
                    name: entry.name,
                    pid: entry.pid,
                    bundleIdentifier: entry.bundleIdentifier,
                    exited: entry.exited,
                    rates: entry.rates,
                    selected: showsSelection(entry),
                    paused: vm.isPaused(pid: entry.pid),
                    onResume: { Task { await vm.resumePausedProcess(pid: entry.pid) } }
                )
                .contextMenu {
                    Button("复制") {
                        let line = copyLine(for: entry)
                        let board = NSPasteboard.general
                        board.clearContents()
                        board.setString(line, forType: .string)
                    }
                }
                .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                .listRowSeparator(.hidden)
                .listRowBackground(rowBackground(showsSelection(entry)))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tint(PulsePalette.selection)
        }
    }

    private var showsColumnHeader: Bool {
        EnergyPage.phaseCounts(
            span: vm.energyRankingSpan,
            liveRowCount: vm.rows.count,
            exitedCount: vm.exitedEnergyProcesses.count,
            rankedCount: rankRows.count
        ).processCount > 0
    }

    private func showsSelection(_ entry: EnergyRankRow) -> Bool {
        guard vm.selectedPid == entry.pid else { return false }
        if entry.isQuitTarget { return true }
        return !rankRows.contains { $0.isQuitTarget && $0.pid == entry.pid }
    }

    private func copyLine(for entry: EnergyRankRow) -> String {
        ProcessRowCopy.line(
            page: .energy,
            row: ProcessRow(
                pid: entry.pid,
                name: entry.name,
                bundleIdentifier: entry.bundleIdentifier,
                executablePath: nil,
                cpuPercent: nil,
                memoryBytes: 0,
                threadCount: 0,
                groupedMemberCount: entry.groupedMemberCount
            ),
            energyWindow: entry.rates
        )
    }

    private func rowBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? PulsePalette.selection : Color.clear)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
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
                if trailing { Spacer(minLength: 0) }
                Text(title)
                if active {
                    Image(systemName: vm.tableSort.descending ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                }
                if !trailing { Spacer(minLength: 0) }
            }
            .font(.caption)
            .foregroundStyle(active ? Color.white.opacity(0.88) : Color.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct EnergyProcessLine: View {
    let name: String
    let pid: Int32
    let bundleIdentifier: String?
    let exited: Bool
    let rates: ProcessEnergyRates?
    let selected: Bool
    var paused = false
    var onResume: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ProcessIconView(pid: pid, bundleIdentifier: bundleIdentifier, size: 16)
                Text(name)
                    .lineLimit(1)
                if paused {
                    PausedProcessMark { onResume() }
                }
                if exited {
                    Text(EnergyPage.exitedStatus)
                        .font(.caption)
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ProcessEnergyText.watts(rates?.watts))
                .monospacedDigit()
                .frame(width: 96, alignment: .trailing)
            Text(ProcessEnergyText.wakeups(rates?.wakeupsPerSecond))
                .monospacedDigit()
                .frame(width: 108, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .modifier(PauseResumeAction(enabled: paused, resume: onResume))
    }

    private var accessibilityLabel: String {
        var parts = [name]
        if paused {
            parts.append("已暂停")
        }
        if exited {
            parts.append(EnergyPage.exitedStatus)
        }
        parts.append("\(ProcessEnergyText.impactTitle) \(ProcessEnergyText.watts(rates?.watts))")
        parts.append("\(ProcessEnergyText.wakeTitle) \(ProcessEnergyText.wakeups(rates?.wakeupsPerSecond))")
        return parts.joined(separator: "，")
    }
}
