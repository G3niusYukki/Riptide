// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Riptide",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Riptide",
            targets: ["Riptide"]
        ),
        .executable(
            name: "riptide",
            targets: ["RiptideCLI"]
        ),
        .executable(
            name: "RiptideApp",
            targets: ["RiptideApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Riptide",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            exclude: ["Backup"]
        ),
        .executableTarget(
            name: "RiptideCLI",
            dependencies: [
                "Riptide",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
        .executableTarget(
            name: "RiptideApp",
            dependencies: [
                "Riptide",
            ]
        ),
        .testTarget(
            name: "RiptideTests",
            dependencies: [
                "Riptide",
                "RiptideCLI",
            ]
        ),
    ]
)
