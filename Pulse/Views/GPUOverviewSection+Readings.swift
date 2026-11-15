import SwiftUI

extension GPUOverviewSection {
    var specLabels: some View {
        HStack(spacing: 6) {
            specPill(symbol: "cpu.fill", text: MachinePageCopy.chipValue(vm.machineFacts?.chipName))
            if let cores = vm.gpuPage.coreCountText {
                specPill(symbol: "square.grid.3x3.fill", text: cores)
            }
            Spacer(minLength: 0)
        }
    }

    var readingCards: some View {
        HStack(spacing: 12) {
            readingCard(title: GPUPageCopy.utilization, value: vm.gpuPage.utilizationText, symbol: "display")
            readingCard(title: GPUPageCopy.memory, value: vm.gpuPage.memoryText, symbol: "memorychip")
            readingCard(
                title: GPUPageCopy.power,
                value: EnergyModelCopy.gpuPowerReading(vm.cpuEnergy?.gpuWatts),
                symbol: "bolt.fill"
            )
            readingCard(
                title: GPUPageCopy.frequency,
                value: EnergyModelCopy.gpuFrequencyReading(vm.cpuEnergy?.gpuFrequency ?? .missing),
                symbol: "speedometer"
            )
        }
        .frame(height: 142)
    }

    private func readingCard(title: String, value: String, symbol: String) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                metricLabel(title, symbol: symbol)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 25, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    func metricLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PulsePalette.accent.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.accent)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }

    private func specPill(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(PulsePalette.hairline, lineWidth: 1)
        }
    }
}
