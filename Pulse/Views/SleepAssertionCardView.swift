import SwiftUI

/// Sleep-assertion card above the energy process table. Stays visible when empty.
struct SleepAssertionCardView: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(SleepAssertionCopy.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if vm.sleepAssertions.isEmpty {
                    Text(SleepAssertionCopy.empty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    ForEach(vm.sleepAssertions) { row in
                        assertionRow(row)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func assertionRow(_ row: SleepAssertionRow) -> some View {
        Button {
            vm.selectSleepAssertion(pid: row.pid)
        } label: {
            HStack(spacing: 8) {
                Text(row.name)
                    .font(.callout)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.typeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(row.durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.name)，\(row.typeText)，\(row.durationText)")
    }
}
