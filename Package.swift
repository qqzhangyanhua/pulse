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
                "Sampling/MachineInfo.swift",
                "Sampling/MemorySampler.swift",
                "Sampling/ProcessEnumerator.swift",
                "MenuBar/MenuBarController.swift",
                "MenuBar/MainWindowAnchor.swift",
                "MenuBar/PulseAppDelegate.swift",
            ],
            sources: [
                "Models/MemoryModels.swift",
                "Sampling/CPULoad.swift",
                "Sampling/SamplingPace.swift",
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
