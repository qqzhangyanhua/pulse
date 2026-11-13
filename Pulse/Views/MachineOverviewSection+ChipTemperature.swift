import SwiftUI

extension MachineOverviewSection {
    var chipTemperatureCard: some View {
        HStack(spacing: 12) {
            PulseCard {
                VStack(alignment: .leading, spacing: 6) {
                    iconLabel(ChipTemperatureCopy.title, symbol: "thermometer.medium", tint: PulsePalette.accent)
                    Spacer(minLength: 0)
                    Text(vm.chipTemperature.text)
                        .font(.system(size: 25, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            }
            .frame(maxWidth: 280)
            Spacer(minLength: 0)
        }
        .frame(height: 92, alignment: .topLeading)
    }
}
