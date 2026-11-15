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
            utilizationCard
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

    private var utilizationCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                metricLabel(GPUPageCopy.utilization, symbol: "display")
                Spacer(minLength: 0)
                Text(vm.gpuPage.utilizationText)
                    .font(.system(size: 25, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                HStack(spacing: 8) {
                    engineTag(GPUPageCopy.renderer, vm.gpuPage.rendererText)
                    engineTag(GPUPageCopy.tiler, vm.gpuPage.tilerText)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func engineTag(_ title: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.primary.opacity(0.85))
        }
        .font(.system(size: 10))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
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
