import AppKit
import SwiftUI

struct EnergyProcessTable: View {
    @EnvironmentObject private var vm: MemoryDashboardVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var energyDisplay: EnergyPageDisplay {
        EnergyPage.display(
            rows: vm.visibleRows,
            windowRates: vm.activeEnergyRates,
            grouped: vm.groupedByApp
        )
    }

    private var phase: EnergyPagePhase {
        EnergyPage.phase(
            loadState: vm.loadState,
            processCount: vm.rows.count,
            visibleCount: vm.visibleRows.count,
            hasActiveNameFilter: vm.hasActiveFilter,
            processListFailed: vm.processListFailed
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
                if !vm.rows.isEmpty {
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
        Picker("排行", selection: $vm.energyRankingSpan) {
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
                    vm.filter = ""
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        case .ready:
            List(vm.sortedRows, selection: $vm.selectedPid) { row in
                EnergyProcessLine(
                    row: row,
                    rates: energyDisplay.readings[row.pid]?.rates,
                    selected: vm.selectedPid == row.pid
                )
                .contextMenu {
                    Button("复制") {
                        let line = ProcessRowCopy.line(
                            page: .energy,
                            row: row,
                            energyWindow: energyDisplay.readings[row.pid]?.rates
                        )
                        let board = NSPasteboard.general
                        board.clearContents()
                        board.setString(line, forType: .string)
                    }
                }
                .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                .listRowSeparator(.hidden)
                .listRowBackground(rowBackground(vm.selectedPid == row.pid))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tint(PulsePalette.selection)
        }
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
    let row: ProcessRow
    let rates: ProcessEnergyRates?
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ProcessIconView(pid: row.pid, bundleIdentifier: row.bundleIdentifier, size: 16)
                Text(row.name)
                    .lineLimit(1)
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
    }

    private var accessibilityLabel: String {
        [
            row.name,
            "\(ProcessEnergyText.impactTitle) \(ProcessEnergyText.watts(rates?.watts))",
            "\(ProcessEnergyText.wakeTitle) \(ProcessEnergyText.wakeups(rates?.wakeupsPerSecond))",
        ].joined(separator: "，")
    }
}
