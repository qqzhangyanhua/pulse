import SwiftUI

extension MachineOverviewSection {
    /// Published GPU utilization and in-use memory. Missing stays 「—」. A tap opens the GPU page.
    var gpuCard: some View {
        Button {
            vm.selectPage(.gpu)
        } label: {
            PulseCard {
                HStack(alignment: .center, spacing: 16) {
                    gpuReading(GPUPageCopy.utilization, value: vm.gpuPage.utilizationText, symbol: "display", tint: PulsePalette.chartCPU)
                    gpuReading(GPUPageCopy.memory, value: vm.gpuPage.memoryText, symbol: "memorychip", tint: PulsePalette.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gpuAccessibility)
        .accessibilityAddTraits(.isButton)
        .frame(maxWidth: .infinity)
        .frame(height: 92)
    }

    private func gpuReading(_ title: String, value: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            iconLabel(title, symbol: symbol, tint: tint)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gpuAccessibility: String {
        "\(GPUPageCopy.utilization) \(vm.gpuPage.utilizationText)，\(GPUPageCopy.memory) \(vm.gpuPage.memoryText)，打开 GPU 页"
    }
}
