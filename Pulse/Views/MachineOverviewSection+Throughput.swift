import SwiftUI

extension MachineOverviewSection {
    var ioThroughputCard: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 10) {
                iconLabel("实时吞吐", symbol: "arrow.up.arrow.down.circle", tint: PulsePalette.chartNetwork)
                ioDirectionBlock("网络吞吐", down: ("下行", NetworkRateText.string(vm.hostNetworkRates.inboundBytesPerSecond)), up: ("上行", NetworkRateText.string(vm.hostNetworkRates.outboundBytesPerSecond)), samples: vm.networkHistory.inbound.samples, tint: PulsePalette.chartNetwork) { NetworkRateText.string($0) }
                Divider().overlay(PulsePalette.hairline)
                ioDirectionBlock("磁盘读写", down: ("读取", DiskRateText.string(vm.hostDiskRates.readBytesPerSecond)), up: ("写入", DiskRateText.string(vm.hostDiskRates.writeBytesPerSecond)), samples: vm.diskHistory.read.samples, tint: PulsePalette.chartDisk) { DiskRateText.string($0) }
            }
        }
    }

    private func ioDirectionBlock(
        _ title: String, down: (String, String), up: (String, String),
        samples: [ChartSample], tint: Color, formatY: @escaping (Double) -> String
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("↓ \(down.0)").font(.caption2).foregroundStyle(.secondary)
                    Text(down.1).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("↑ \(up.0)").font(.caption2).foregroundStyle(.secondary)
                    Text(up.1).font(.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
            }
            .frame(width: 132, alignment: .leading)
            Group {
                if samples.count >= 2 {
                    SparklineChart(samples: samples, tint: tint, domain: byteDomain(samples), formatY: formatY)
                } else {
                    ChartPlaceholder(text: "曲线采集中")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}
