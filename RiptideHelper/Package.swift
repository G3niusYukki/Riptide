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
    dependencies: [
        .package(path: "../")
    ],
    targets: [
        .executableTarget(
            name: "RiptideHelper",
            dependencies: [
                .product(name: "Riptide", package: "Riptide")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
