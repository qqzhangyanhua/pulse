import AppKit
import Charts
import SwiftUI

enum PulsePalette {
    static let windowBackground = Color(red: 0.086, green: 0.086, blue: 0.094)
    static let sidebar = Color(red: 0.067, green: 0.067, blue: 0.074)
    static let card = Color(red: 0.145, green: 0.145, blue: 0.157)
    static let accent = Color(red: 0.47, green: 0.39, blue: 0.98)
    static let action = Color(red: 0.20, green: 0.48, blue: 0.98)
    static let selection = Color(red: 0.16, green: 0.45, blue: 0.96)
    static let app = Color(red: 0.31, green: 0.55, blue: 0.98)
    static let wired = Color(red: 0.98, green: 0.58, blue: 0.22)
    static let compressed = Color(red: 0.30, green: 0.78, blue: 0.45)
    static let cached = Color(red: 0.58, green: 0.59, blue: 0.63)
    static let pressureNormal = Color(red: 0.22, green: 0.80, blue: 0.48)
    static let pressureElevated = Color(red: 0.96, green: 0.62, blue: 0.20)
    static let chartCPU = Color(red: 0.36, green: 0.62, blue: 0.98)
    static let chartNetwork = Color(red: 0.30, green: 0.74, blue: 0.72)
    static let chartDisk = Color(red: 0.78, green: 0.58, blue: 0.36)
    static let destructive = Color(red: 0.93, green: 0.47, blue: 0.44)
    static let hairline = Color.white.opacity(0.08)
}

enum PulseRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

extension Array where Element == ChartSample {
    var seriesAverage: Double? {
        guard !isEmpty else { return nil }
        return reduce(0) { $0 + $1.value } / Double(count)
    }

    var seriesPeak: Double? {
        map(\.value).max()
    }

    var seriesLatest: Double? {
        last?.value
    }
}

enum ResourceTab: String, CaseIterable, Identifiable {
    case memory = "内存"
    case cpu = "CPU"
    case disk = "磁盘"
    case network = "网络"
    case machine = "本机"
    case gpu = "GPU"

    var id: String { rawValue }

    var page: DashboardPage {
        switch self {
        case .memory: return .memory
        case .cpu: return .cpu
        case .disk: return .disk
        case .network: return .network
        case .machine: return .machine
        case .gpu: return .gpu
        }
    }

    var isEnabled: Bool { page.isSelectable }

    var symbol: String {
        switch self {
        case .memory: return "memorychip"
        case .cpu: return "cpu"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .machine: return "desktopcomputer"
        case .gpu: return "display"
        }
    }
}

struct ResourceTabs: View {
    @EnvironmentObject private var vm: MemoryDashboardVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionPill
    @State private var highlighted: DashboardPage?

    private static let selectionAnimation = Animation.smooth(duration: 0.34, extraBounce: 0)

    private var shownPage: DashboardPage { highlighted ?? vm.selectedPage }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ResourceTab.allCases.filter(\.isEnabled)) { tab in
                enabledTab(tab)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.05), in: Capsule())
        .onAppear { if highlighted == nil { highlighted = vm.selectedPage } }
        .onChange(of: vm.selectedPage) { _, newPage in
            guard highlighted != newPage else { return }
            moveHighlight(to: newPage)
        }
    }

    private func enabledTab(_ tab: ResourceTab) -> some View {
        let selected = shownPage == tab.page
        return Button {
            if shownPage != tab.page {
                moveHighlight(to: tab.page)
            }
            vm.selectPage(tab.page)
        } label: {
            HStack(spacing: 0) {
                Image(systemName: tab.symbol)
                Text(tab.rawValue)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 5)
                    .modifier(ResourceTabLabelCollapse(progress: selected ? 1 : 0))
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.78))
            .padding(.horizontal, selected ? 10 : 8)
            .padding(.vertical, 5)
            .frame(minWidth: 30, minHeight: 24)
            .background {
                if selected {
                    Capsule()
                        .fill(PulsePalette.accent)
                        .matchedGeometryEffect(id: "resource-tab-pill", in: selectionPill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.rawValue)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func moveHighlight(to page: DashboardPage) {
        if reduceMotion {
            highlighted = page
        } else {
            withAnimation(Self.selectionAnimation) {
                highlighted = page
            }
        }
    }
}

/// Label stays mounted so the selected capsule can morph width instead of popping.
private struct ResourceTabLabelCollapse: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        ResourceTabLabelWidth(progress: progress) { content }
            .clipped()
            .opacity(min(1, max(0, (progress - 0.72) / 0.28)))
    }
}

private struct ResourceTabLabelWidth: Layout {
    var progress: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let full = child.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height))
        return CGSize(width: full.width * min(1, max(0, progress)), height: full.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let full = child.sizeThatFits(ProposedViewSize(width: nil, height: bounds.height))
        child.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: full.width, height: full.height)
        )
    }
}

private struct FocusNameFilterKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct NameFilterFocusedKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var focusNameFilter: (() -> Void)? {
        get { self[FocusNameFilterKey.self] }
        set { self[FocusNameFilterKey.self] = newValue }
    }

    var nameFilterFocused: Bool? {
        get { self[NameFilterFocusedKey.self] }
        set { self[NameFilterFocusedKey.self] = newValue }
    }
}

struct AppFilterField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("过滤 App", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空过滤")
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: text.isEmpty)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 210)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? PulsePalette.accent.opacity(0.65) : PulsePalette.hairline, lineWidth: 1)
        }
        .focusedSceneValue(\.focusNameFilter) { isFocused = true }
        .focusedSceneValue(\.nameFilterFocused, isFocused)
    }
}

struct ProcessIconView: View {
    let pid: pid_t
    let bundleIdentifier: String?
    var size: CGFloat = 20

    var body: some View {
        if let icon = resolvedIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.62))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    private var resolvedIcon: NSImage? {
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            return icon
        }
        if let bundleIdentifier,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        {
            return app.icon
        }
        return nil
    }
}

struct AppEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var retryTitle: String?
    var onRetry: (() -> Void)?
    var isRetryEnabled: Bool = true
    var pendingMessage: String?

    init(
        systemImage: String,
        title: String,
        message: String,
        retryTitle: String? = nil,
        onRetry: (() -> Void)? = nil,
        isRetryEnabled: Bool = true,
        pendingMessage: String? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
        self.isRetryEnabled = isRetryEnabled
        self.pendingMessage = pendingMessage
    }

    init(
        systemImage: String,
        title: String,
        message: String,
        retrying: Bool,
        onRetry: @escaping () -> Void
    ) {
        let chrome = SamplingRetryEmptyChrome(retrying: retrying)
        self.init(
            systemImage: systemImage,
            title: title,
            message: message,
            retryTitle: chrome.buttonTitle,
            onRetry: onRetry,
            isRetryEnabled: chrome.isButtonEnabled,
            pendingMessage: chrome.pendingMessage
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            if let pendingMessage {
                Text(pendingMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.bordered)
                    .disabled(!isRetryEnabled)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .frame(width: width, height: height)
    }
}

struct SkeletonChart: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: 0, y: height * 0.55))
                path.addCurve(
                    to: CGPoint(x: width, y: height * 0.42),
                    control1: CGPoint(x: width * 0.28, y: height * 0.22),
                    control2: CGPoint(x: width * 0.62, y: height * 0.72)
                )
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.05))
        }
    }
}

struct ChartPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PulseCard<Content: View>: View {
    var padding: CGFloat = 14
    var border: Color = PulsePalette.hairline
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PulsePalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
    }
}

struct SparklineChart: View {
    let samples: [ChartSample]
    var tint: Color
    var domain: ClosedRange<Double>
    var formatY: (Double) -> String
    var showsAxes: Bool = true

    var body: some View {
        Chart(samples) { sample in
            AreaMark(
                x: .value("时间", sample.date),
                y: .value("值", sample.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [tint.opacity(0.42), tint.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("时间", sample.date),
                y: .value("值", sample.value)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .chartLegend(.hidden)
        .chartYScale(domain: domain)
        .chartPlotStyle { plot in
            plot.background(Color.clear)
        }
        .chartXAxis {
            if showsAxes {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(ByteFormat.clock(date))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.42))
                        }
                    }
                }
            }
        }
        .chartYAxis {
            if showsAxes {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(formatY(number))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.42))
                        }
                    }
                }
            }
        }
    }
}

struct ThermalNoticeLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct SidebarMetric: View {
    let systemImage: String
    let title: String
    let tint: Color
    let value: String
    let caption: String
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.caption)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            captionText
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(PulsePalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PulsePalette.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var captionText: some View {
        if !caption.isEmpty {
            let text = Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let help {
                text.help(help)
            } else {
                text
            }
        }
    }
}

struct HistoryAnnotatedChart<Content: View>: View {
    let annotation: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topLeading) {
                if let annotation {
                    Text(annotation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 5)
                        .padding(.leading, 5)
                }
            }
    }
}
