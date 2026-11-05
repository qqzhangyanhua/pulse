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
    static let destructive = Color(red: 0.93, green: 0.47, blue: 0.44)
    static let hairline = Color.white.opacity(0.08)
}

enum ByteFormat {
    static func memory(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 字节" }
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return grouped(gib, maxDecimals: 2) + " GB"
        }
        let mib = Double(bytes) / 1_048_576
        if mib >= 1 {
            return grouped(mib, maxDecimals: 1) + " MB"
        }
        let kib = Double(bytes) / 1_024
        if kib >= 1 {
            return grouped(kib, maxDecimals: 0) + " KB"
        }
        return "\(bytes) 字节"
    }

    static func gibWhole(_ bytes: UInt64) -> String {
        let gib = (Double(bytes) / 1_073_741_824).rounded()
        return String(format: "%.0f GB", gib)
    }

    static func cpu(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    static func wholePercent(value: Double) -> String {
        String(format: "%.0f%%", (value * 100).rounded())
    }

    static func wholePercent(part: UInt64, total: UInt64) -> String {
        guard total > 0 else { return "0%" }
        return wholePercent(value: Double(part) / Double(total))
    }

    static func share(part: UInt64, total: UInt64) -> String {
        guard total > 0 else { return "0%" }
        let percent = (Double(part) / Double(total)) * 100
        if part > 0, percent < 0.1 { return "<0.1%" }
        if percent < 10 { return String(format: "%.1f%%", percent) }
        return String(format: "%.0f%%", percent)
    }

    static func coreLoad(cpuPercent: Double?, processorCount: Int) -> String {
        let total = max(processorCount, 1)
        guard let cpuPercent else { return "— (共 \(total) 个)" }
        let cores = cpuPercent / 100 * Double(total)
        return String(format: "%.1f 个内核 (共 %d 个)", cores, total)
    }

    static func clock(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func grouped(_ value: Double, maxDecimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxDecimals
        formatter.usesGroupingSeparator = abs(value) >= 1000
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxDecimals)f", value)
    }
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
    case gpu = "GPU"

    var id: String { rawValue }
    var isEnabled: Bool { self == .memory }

    var symbol: String {
        switch self {
        case .memory: return "memorychip"
        case .cpu: return "cpu"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .gpu: return "display"
        }
    }
}

struct ResourceTabs: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ResourceTab.allCases) { tab in
                if tab.isEnabled {
                    memoryPill
                } else {
                    disabledTab(tab)
                }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.05), in: Capsule())
        .allowsHitTesting(false)
    }

    private var memoryPill: some View {
        HStack(spacing: 5) {
            Image(systemName: ResourceTab.memory.symbol)
            Text(ResourceTab.memory.rawValue)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PulsePalette.accent, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isSelected)
    }

    private func disabledTab(_ tab: ResourceTab) -> some View {
        Image(systemName: tab.symbol)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.32))
            .frame(width: 30, height: 24)
            .accessibilityLabel("\(tab.rawValue)，不可用")
    }
}

struct AppFilterField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("过滤 App", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空过滤")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 210)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PulsePalette.hairline, lineWidth: 1)
        }
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
            if let retryTitle, let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.bordered)
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
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(ByteFormat.clock(date))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                    .foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatY(number))
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                }
            }
        }
    }
}
