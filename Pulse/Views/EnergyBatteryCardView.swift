import SwiftUI

/// Battery card above the energy-page table. Absent when the Mac has no internal battery.
struct EnergyBatteryCardView: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        if let card = vm.energyBatteryCard {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PulsePalette.pressureElevated)
                reading("电量", card.percent)
                reading("电源", card.power)
                if let lowPowerMode = card.lowPowerMode {
                    Text(lowPowerMode)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PulsePalette.pressureElevated)
                }
                Spacer(minLength: 12)
                Text(card.time)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PulsePalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(PulsePalette.hairline, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func reading(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }
}
