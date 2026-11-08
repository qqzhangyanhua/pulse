// swift-tools-version: 5.9
import PackageDescription

// Darwin-free slice of the sampling model so `swift test` can run off macOS.
// The app itself still builds from Pulse.xcodeproj.
let package = Package(
    name: "SamplingCore",
    products: [
        .library(name: "SamplingCore", targets: ["SamplingCore"]),
    ],
    targets: [
        .target(
            name: "SamplingCore",
            path: "Pulse",
            exclude: [
                "Actions",
                "Assets.xcassets",
                "Info.plist",
                "Pulse.entitlements",
                "PulseApp.swift",
                "ViewModels",
                "Views",
                "Sampling/HostCPUReader.swift",
                "Sampling/HostMemoryReader.swift",
                "Sampling/HostNetworkReader.swift",
                "Sampling/HostDiskReader.swift",
                "Sampling/MachineInfo.swift",
                "Sampling/HostMachineReader.swift",
                "Sampling/MemorySampler.swift",
                "Sampling/ProcessEnumerator.swift",
                "MenuBar/MenuBarController.swift",
                "MenuBar/MenuBarPopoverView.swift",
                "MenuBar/MainWindowAnchor.swift",
                "MenuBar/PulseAppDelegate.swift",
            ],
            sources: [
                "Models/MemoryModels.swift",
                "Models/ProcessMemoryChoice.swift",
                "Models/ByteFormat.swift",
                "Models/MemoryGrowthSignal.swift",
                "Models/MemoryDetailPresentation.swift",
                "Models/ResourceDetailPageProjection.swift",
                "Models/LastLiveTotalReducer.swift",
                "Models/MemoryGrowthTopSeries.swift",
                "Models/MemoryGrowthRisingFilter.swift",
                "Models/MemoryTablePhase.swift",
                "Models/ProcessSelection.swift",
                "Models/TopAppLocation.swift",
                "Models/HistoryCurvePresentation.swift",
                "Models/ThermalNotice.swift",
                "Models/ProcessQuitOutcome.swift",
                "Models/ProcessQuitSession.swift",
                "Models/CPUPage.swift",
                "Models/MemoryPageSortPublication.swift",
                "Models/NetworkPage.swift",
                "Models/DiskPage.swift",
                "Models/MachinePage.swift",
                "Models/BatteryMath.swift",
                "Models/MachineOverview.swift",
                "Models/SwapUsage.swift",
                "Models/KernelPressure.swift",
                "Models/WindowedAppFilter.swift",
                "Models/AppGroupProjection.swift",
                "Models/ProcessGlossary.swift",
                "Models/MenuBarReading.swift",
                "Sampling/CPULoad.swift",
                "Sampling/HostNetwork.swift",
                "Sampling/HostDisk.swift",
                "Sampling/SamplingPace.swift",
                "Sampling/SamplingRequestGate.swift",
                "Sampling/SamplingRetryChrome.swift",
                "MenuBar/MenuBarStatus.swift",
            ]
        ),
        .testTarget(
            name: "SamplingCoreTests",
            dependencies: ["SamplingCore"],
            path: "Tests/SamplingCoreTests"
        ),
    ]
)
