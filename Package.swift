// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PitchDetect",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    targets: [
        .target(
            name: "PitchDetectCore",
            path: "PianoReader/DSP",
            exclude: ["PolyphonicDetector.swift", "PolyphonicSmoother.swift"]
        ),
        .executableTarget(
            name: "PitchDetectCLI",
            dependencies: ["PitchDetectCore"],
            path: "Sources/PitchDetectCLI"
        ),
    ]
)
