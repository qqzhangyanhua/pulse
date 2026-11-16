import SwiftUI

extension GPUOverviewSection {
    var recoveryCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                metricLabel(GPUPageCopy.recovery, symbol: "arrow.clockwise")
                Text(vm.gpu.page.recoveryText)
                    .font(.system(size: 25, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(GPUPageCopy.recoveryCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(GPUPageCopy.recovery) \(vm.gpu.page.recoveryText)，\(GPUPageCopy.recoveryCaption)")
    }
}
