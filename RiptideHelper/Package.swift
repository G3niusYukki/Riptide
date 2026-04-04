// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RiptideHelper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "RiptideHelper",
            targets: ["RiptideHelper"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RiptideHelper",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
