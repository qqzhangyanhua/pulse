import Foundation

extension MemoryDashboardVM {
    var symptomPanelOpen: Bool { core.symptomPanelOpen }

    func setSymptomPanelOpen(_ open: Bool) {
        mutateCore { $0.setSymptomPanelOpen(open) }
    }

    func symptomFinding(_ kind: SymptomKind) -> SymptomFinding {
        SymptomDiagnosis.finding(kind, input: symptomInput())
    }

    func openSymptomCause(page: DashboardPage, pid: Int32?) {
        mutateCore { core in
            _ = core.setSymptomPanelOpen(false)
            var effects = core.selectPage(page)
            if let pid {
                effects += core.select(pid: pid)
            }
            return effects
        }
    }

    private func symptomInput() -> SymptomInput {
        let now = Date()
        let history = HistoryStore.shared.samples(
            from: now.addingTimeInterval(-3600),
            to: now
        )
        let facts = core.machineFacts
        let sleep: SymptomSleepFacts
        if !core.sleepAssertionsKnown {
            sleep = .unread
        } else if core.sleepAssertions.isEmpty {
            sleep = .none
        } else {
            sleep = .held(core.sleepAssertions.map {
                SymptomHeldSleep(pid: $0.pid, name: $0.name, typeText: $0.typeText)
            })
        }
        return SymptomInput(
            systemCpuPercent: core.systemCpuPercent,
            processes: core.rows.map {
                SymptomProcess(
                    pid: $0.pid,
                    name: $0.name,
                    cpuPercent: $0.cpuPercent,
                    energyWatts: $0.energyWatts
                )
            },
            memoryPressure: core.snapshot?.pressure,
            thermalName: core.lastHistoryThermalName,
            gpuPercent: core.gpuPage.utilizationPercent,
            dischargeMilliamps: facts?.battery?.milliamps,
            diskFreeBytes: facts?.volume.availableBytes,
            diskTotalBytes: facts?.volume.totalBytes,
            purgeableBytes: nil,
            sleep: sleep,
            recentCPU: history.map(\.cpuPercent)
        )
    }
}
