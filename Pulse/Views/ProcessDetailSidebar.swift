import SwiftUI

struct ProcessDetailSidebar: View {
    /// Internal so `ProcessDetailSidebar+MemoryAttribution` can read the same object.
    @EnvironmentObject var vm: MemoryDashboardVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Sampling-window disclosure. View-local, collapsed. Not stored on the VM.
    @State private var samplingWindowExpanded = false
    @State private var showsProcessTree = false
    @State private var processTreeCenterPid: Int32?
    @State private var expandedProcessTreePids: Set<Int32> = []
    /// Last positive physical total for the sidebar subject, plus the locked freeze.
    @State private var lastLiveTotal = LastLiveTotalState.empty

    var body: some View {
        let sidebar = vm.sidebar
        Group {
            if showsProcessTree, let centerPid = processTreeCenterPid {
                ProcessTreeView(
                    rows: vm.rows,
                    centerPid: centerPid,
                    expandedPids: $expandedProcessTreePids,
                    onBack: { vm.focusProcessFromTree(centerPid); showsProcessTree = false },
                    onSelect: { pid in vm.focusProcessFromTree(pid); showsProcessTree = false }
                )
                .transition(.opacity)
            } else if let detail = sidebar.detail {
                detailBody(detail).transition(.opacity)
            } else if sidebar.showsAbsentRecord {
                absentRecordBody.transition(.opacity)
            } else {
                emptyBody.transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: sidebarMotionID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PulsePalette.sidebar)
        .onAppear(perform: acceptCurrentSidebarLiveTotal)
        .task { acceptCurrentSidebarLiveTotal() }
        .onChange(of: vm.snapshot) { _, _ in
            acceptSnapshotTotal()
        }
        .onChange(of: sidebarSubjectBeat) { previous, current in
            acceptSidebarBeat(previous: previous, current: current)
        }
        .onChange(of: AppGroupChrome.showsProcessTreeButton(groupedByApp: vm.groupedByApp, page: vm.selectedPage)) { _, shows in
            if !shows { showsProcessTree = false }
        }
    }

    private var sidebarSubjectBeat: SidebarSubjectBeat {
        let detail = vm.sidebar.detail
        return SidebarSubjectBeat(
            subjectPid: vm.sidebarSubjectPid,
            showsAbsentRecord: vm.sidebar.showsAbsentRecord,
            sidebarDetailPid: detail?.row.pid,
            sidebarDetailMemoryBytes: detail?.row.memoryBytes,
            hasSidebarDetail: detail != nil,
            liveDetailPid: vm.detail?.row.pid,
            listSelectedPid: vm.selectedPid,
            sidebarSeriesEmpty: detail.map { $0.memorySeries.isEmpty && $0.cpuSeries.isEmpty } ?? false
        )
    }

    private func currentLiveGate() -> SidebarLiveGate {
        SidebarLiveGate(beat: sidebarSubjectBeat, snapshotTotalBytes: vm.snapshot?.totalBytes)
    }

    private func acceptCurrentSidebarLiveTotal() {
        guard let event = LastLiveTotalReducer.eventForCurrentSidebar(currentLiveGate()) else { return }
        reduceLastLive([event])
    }

    private func acceptSnapshotTotal() {
        acceptCurrentSidebarLiveTotal()
    }

    private func acceptSidebarBeat(previous: SidebarSubjectBeat, current: SidebarSubjectBeat) {
        reduceLastLive(
            LastLiveTotalReducer.eventsForSidebar(
                previous: previous,
                current: current,
                snapshotTotalBytes: vm.snapshot?.totalBytes
            )
        )
    }

    private func reduceLastLive(_ events: [LastLiveTotalEvent]) {
        for event in events {
            lastLiveTotal = LastLiveTotalReducer.step(lastLiveTotal, event)
        }
    }

    /// Detail pid, absent record, or empty. Snapshot ticks do not change it.
    private var sidebarMotionID: String {
        if let pid = vm.sidebar.detail?.row.pid { return "d\(pid)" }
        return vm.sidebar.showsAbsentRecord ? "absent" : "empty"
    }

    private var emptyPrompt: String {
        switch vm.selectedPage {
        case .cpu:
            return CPUPageCopy.sidebarEmpty
        case .network:
            return NetworkPageCopy.sidebarEmpty
        case .disk:
            return DiskPageCopy.sidebarEmpty
        default:
            return "选择一个进程查看详情"
        }
    }

    private var emptyBody: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(PulsePalette.accent.opacity(0.12))
                    .frame(width: 88, height: 88)
                    .blur(radius: 18)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PulsePalette.card.opacity(0.8))
                    .frame(width: 58, height: 58)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(PulsePalette.accent.opacity(0.24), lineWidth: 1)
                    }
                    .overlay {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        PulsePalette.accent,
                                        PulsePalette.chartCPU
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .frame(height: 88)
            .accessibilityHidden(true)

            Text(emptyPrompt)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var absentRecordBody: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                closeButton
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            quitControls
        }
    }

    private var closeButton: some View {
        Button {
            vm.dismissSidebar()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭详情")
        .help("关闭详情")
    }

    private func detailBody(_ detail: ProcessDetail) -> some View {
        let projection = displayedProjection(detail)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(detail)
                processInfo(detail)
                switch projection {
                case .memoryExisting:
                    metrics(detail)
                    if let slot = vm.memoryGrowthSlot {
                        memoryTrend(slot, curveRow: detail.row)
                    }
                    if vm.sidebar.showsLiveTrend && vm.selectedPage == .memory {
                        samplingWindowDisclosure
                    }
                    memoryChart(detail)
                        .frame(height: 168)
                    cpuChart(detail)
                        .frame(height: 124)
                case .cpu(let cpu):
                    cpuResourceDetail(detail, cpu: cpu)
                case .network(let network):
                    networkResourceDetail(detail, network: network)
                case .disk(let disk):
                    diskResourceDetail(detail, disk: disk)
                case .energy(let energy):
                    energyResourceDetail(energy)
                case .noResourceUpgrade:
                    noResourceUpgradeDetail(detail)
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            quitControls
        }
    }

    private func displayedProjection(_ detail: ProcessDetail) -> ResourceDetailProjection {
        let shown = ProcessDetail(
            row: displayedMemoryRow(detail.row),
            memorySeries: detail.memorySeries,
            cpuSeries: detail.cpuSeries
        )
        return ResourceDetailPageProjection.project(
            page: vm.selectedPage,
            detail: shown,
            physicalTotalBytes: vm.snapshot?.totalBytes,
            frozen: LastLiveTotalReducer.frozenSemanticsForProjection(
                showsAbsentRecord: vm.sidebar.showsAbsentRecord,
                state: lastLiveTotal,
                detailPid: shown.row.pid,
                detailMemoryBytes: shown.row.memoryBytes
            ),
            energyDisplay: energyDisplayReading(for: shown.row.pid)
        )
    }

    @ViewBuilder
    private func cpuResourceDetail(_ detail: ProcessDetail, cpu: CPUDetailProjection) -> some View {
        cpuMetric(cpuPercent: cpu.cpuPercent)
        HStack(alignment: .top, spacing: 10) {
            SidebarMetric(
                systemImage: "bolt",
                title: ProcessEnergyText.impactTitle,
                tint: PulsePalette.chartCPU,
                value: ProcessEnergyText.watts(cpu.energyWatts),
                caption: ProcessEnergyText.caption(isPartial: cpu.energyReadingIsPartial)
            )
            SidebarMetric(
                systemImage: "moon.zzz",
                title: ProcessEnergyText.wakeTitle,
                tint: PulsePalette.chartCPU,
                value: ProcessEnergyText.wakeups(cpu.wakeupsPerSecond),
                caption: ProcessEnergyText.caption(isPartial: cpu.wakeupReadingIsPartial)
            )
        }
        cpuChart(detail)
            .frame(height: 124)
        memoryMetric(cpu.memory, bytes: cpu.memoryBytes)
        memoryChart(detail)
            .frame(height: 168)
    }

    @ViewBuilder
    private func networkResourceDetail(_ detail: ProcessDetail, network: NetworkDetailProjection) -> some View {
        switch network.notice {
        case .unavailable:
            Text(ResourceDetailPageProjection.processNetworkUnavailable)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help(NetworkPageCopy.processRateHelp)
        }
        HStack(alignment: .top, spacing: 10) {
            cpuMetric(cpuPercent: network.cpuPercent)
            memoryMetric(network.memory, bytes: network.memoryBytes)
        }
        memoryChart(detail)
            .frame(height: 168)
    }

    @ViewBuilder
    private func diskResourceDetail(_ detail: ProcessDetail, disk: DiskDetailProjection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            diskRateMetric(title: DiskPageCopy.readTitle, bytesPerSecond: disk.readBytesPerSecond)
            diskRateMetric(title: DiskPageCopy.writeTitle, bytesPerSecond: disk.writeBytesPerSecond)
        }
        HStack(alignment: .top, spacing: 10) {
            cpuMetric(cpuPercent: disk.cpuPercent)
            memoryMetric(disk.memory, bytes: disk.memoryBytes)
        }
        memoryChart(detail)
            .frame(height: 168)
    }

    @ViewBuilder
    private func noResourceUpgradeDetail(_ detail: ProcessDetail) -> some View {
        metrics(detail)
        memoryChart(detail)
            .frame(height: 168)
    }

    private func cpuMetric(cpuPercent: Double?) -> some View {
        SidebarMetric(
            systemImage: "cpu",
            title: "CPU",
            tint: PulsePalette.chartCPU,
            value: ByteFormat.cpu(cpuPercent),
            caption: ByteFormat.coreLoad(
                cpuPercent: cpuPercent,
                processorCount: MachineInfo.processorCount
            )
        )
    }

    private func memoryMetric(_ memory: MemoryDetailFieldCopy, bytes: UInt64) -> some View {
        SidebarMetric(
            systemImage: "memorychip",
            title: memory.title,
            tint: PulsePalette.accent,
            value: ByteFormat.memory(bytes),
            caption: memory.caption,
            help: memory.help
        )
    }

    private func diskRateMetric(title: String, bytesPerSecond: Double?) -> some View {
        SidebarMetric(
            systemImage: "internaldrive",
            title: title,
            tint: PulsePalette.chartDisk,
            value: DiskRateText.string(bytesPerSecond),
            caption: ""
        )
    }

    private func header(_ detail: ProcessDetail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProcessIconView(
                pid: detail.row.pid,
                bundleIdentifier: detail.row.bundleIdentifier,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.row.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(kindLine(detail.row))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = ProcessGlossary.note(for: detail.row.name) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if AppGroupChrome.showsProcessTreeButton(groupedByApp: vm.groupedByApp, page: vm.selectedPage) {
                ProcessTreeOpenButton(systemName: "arrow.triangle.branch", help: "进程树") {
                    openProcessTree(centeredOn: detail.row.pid)
                }
            }
            closeButton
        }
    }

    private func openProcessTree(centeredOn pid: Int32) {
        processTreeCenterPid = pid
        expandedProcessTreePids = ProcessTree.build(from: vm.rows).initiallyExpanded(centeredOn: pid)
        showsProcessTree = true
    }

    private func kindLine(_ row: ProcessRow) -> String {
        let kind = row.bundleIdentifier == nil ? "进程" : "App"
        return "\(kind) · PID \(row.pid)"
    }

    private func metrics(_ detail: ProcessDetail) -> some View {
        let row = memoryMagnitudeRow(fallback: displayedMemoryRow(detail.row))
        let memory = memoryField(row)
        return HStack(alignment: .top, spacing: 10) {
            SidebarMetric(
                systemImage: "memorychip",
                title: memory.title,
                tint: PulsePalette.accent,
                value: ByteFormat.memory(row.memoryBytes),
                caption: memory.caption,
                help: memory.help,
                attribution: memoryMagnitudeAttribution(
                    displayed: row,
                    curve: detail.row,
                    points: detail.memorySeries.count
                )
            )
            SidebarMetric(
                systemImage: "cpu",
                title: "CPU",
                tint: PulsePalette.chartCPU,
                value: ByteFormat.cpu(detail.row.cpuPercent),
                caption: ByteFormat.coreLoad(
                    cpuPercent: detail.row.cpuPercent,
                    processorCount: MachineInfo.processorCount
                )
            )
        }
    }

    private var samplingWindowDisclosure: some View {
        DisclosureGroup(isExpanded: $samplingWindowExpanded) {
            Text(MemoryDetailSamplingWindow.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text(MemoryDetailSamplingWindow.summary)
                .font(.caption.weight(.semibold))
        }
    }

    /// Grouped memory and CPU pages show the merged row. The curve stays on the selected pid.
    func displayedMemoryRow(_ row: ProcessRow) -> ProcessRow {
        guard vm.groupedByApp, AppGroupChrome.applies(on: vm.selectedPage) else { return row }
        return vm.sortedRows.first { $0.pid == row.pid } ?? row
    }

    func memoryField(_ row: ProcessRow) -> MemoryDetailFieldCopy {
        let frozen = LastLiveTotalReducer.frozenSemanticsForProjection(
            showsAbsentRecord: vm.sidebar.showsAbsentRecord,
            state: lastLiveTotal,
            detailPid: row.pid,
            detailMemoryBytes: row.memoryBytes
        )
        return MemoryDetailPresentation.field(
            page: vm.selectedPage,
            part: row.memoryBytes,
            total: ResourceDetailPageProjection.memoryTotal(
                detailPid: row.pid,
                physicalTotalBytes: vm.snapshot?.totalBytes,
                frozen: frozen
            ),
            source: row.memorySource,
            residentIsPartial: row.residentMemoryIsPartial
        )
    }

    private func cpuChart(_ detail: ProcessDetail) -> some View {
        seriesBlock(
            title: "CPU",
            samples: detail.cpuSeries,
            placeholder: "正在采集 CPU 曲线",
            summary: cpuSummary(detail.cpuSeries),
            tint: PulsePalette.chartCPU,
            domain: percentDomain(detail.cpuSeries),
            formatY: { ByteFormat.cpu($0) }
        )
    }

    private func cpuSummary(_ samples: [ChartSample]) -> String {
        guard let average = samples.seriesAverage, let peak = samples.seriesPeak else { return "" }
        return "平均 \(ByteFormat.cpu(average)) · 峰值 \(ByteFormat.cpu(peak))"
    }

    private func percentDomain(_ samples: [ChartSample]) -> ClosedRange<Double> {
        let peak = samples.map(\.value).max() ?? 0
        return 0...max(peak * 1.2, 5)
    }

    func seriesBlock(
        title: String,
        samples: [ChartSample],
        placeholder: String,
        summary: String,
        tint: Color,
        domain: ClosedRange<Double>,
        formatY: @escaping (Double) -> String,
        summaryScale: CGFloat = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(summaryScale)
            }
            if samples.count < 2 {
                ChartPlaceholder(text: placeholder)
            } else {
                SparklineChart(samples: samples, tint: tint, domain: domain, formatY: formatY)
            }
        }
    }
}
