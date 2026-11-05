import AppKit
import SwiftUI

enum PulsePalette {
    static let app = Color(red: 0.22, green: 0.47, blue: 0.96)
    static let wired = Color(red: 0.95, green: 0.62, blue: 0.18)
    static let compressed = Color(red: 0.56, green: 0.38, blue: 0.90)
    static let cached = Color(red: 0.42, green: 0.58, blue: 0.46)
    static let pressureNormal = Color(red: 0.18, green: 0.58, blue: 0.46)
    static let pressureElevated = Color(red: 0.86, green: 0.58, blue: 0.18)
}

enum ByteFormat {
    static func memory(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return String(format: gib >= 10 ? "%.0f GB" : "%.1f GB", gib)
        }
        let mib = Double(bytes) / 1_048_576
        if mib >= 1 {
            return String(format: mib >= 10 ? "%.0f MB" : "%.1f MB", mib)
        }
        let kib = Double(bytes) / 1_024
        return String(format: "%.0f KB", kib)
    }

    static func gibWhole(_ bytes: UInt64) -> String {
        let gib = (Double(bytes) / 1_073_741_824).rounded()
        return String(format: "%.0f GB", gib)
    }

    static func cpu(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
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
}

struct ResourceTabs: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(ResourceTab.allCases) { tab in
                Text(tab.rawValue)
                    .font(.subheadline.weight(tab.isEnabled ? .semibold : .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(tab.isEnabled ? Color.accentColor.opacity(0.16) : Color.clear)
                    .foregroundStyle(tab.isEnabled ? Color.primary : Color.secondary.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ProcessIconView: View {
    let pid: pid_t
    let bundleIdentifier: String?

    var body: some View {
        if let icon = resolvedIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .cornerRadius(4)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
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
            .fill(Color.primary.opacity(0.07))
            .frame(width: width, height: height)
    }
}
