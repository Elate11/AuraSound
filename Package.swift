// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SoundBarBoost",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "SoundBarBoost",
            targets: ["SoundBarBoost"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SoundBarBoost",
            dependencies: [],
            path: "Sources/SoundBarBoost",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
