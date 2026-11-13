import SwiftUI

extension MachineOverviewSection {
    var chipTemperatureCard: some View {
        PulseCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    iconLabel(ChipTemperatureCopy.title, symbol: "thermometer.medium", tint: PulsePalette.accent)
                    Spacer(minLength: 0)
                    Text(vm.chipTemperature.text)
                        .font(.system(size: 25, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .frame(width: 146, alignment: .leading)
                chipTemperatureChart
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148, alignment: .topLeading)
    }

    @ViewBuilder
    private var chipTemperatureChart: some View {
        if vm.chipTemperature.showsCurve {
            HistoryAnnotatedChart(
                annotation: HistoryCurvePresentation.annotation(
                    current: vm.chipTemperature.celsius,
                    sampleCount: vm.chipTemperature.history.samples.count
                )
            ) {
                SparklineChart(
                    samples: vm.chipTemperature.history.samples,
                    tint: PulsePalette.accent,
                    domain: vm.chipTemperature.curveDomain,
                    formatY: { ChipTemperatureCopy.degrees($0) }
                )
            }
        } else {
            ChartPlaceholder(text: ChipTemperatureCopy.chartCollecting)
        }
    }
}
