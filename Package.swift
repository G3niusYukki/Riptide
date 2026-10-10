// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Riptide",
    defaultLocalization: "en",
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
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .target(
            name: "Riptide",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
                .product(name: "X509", package: "swift-certificates"),
                "GoCore",
                "RiptideSecurityShim",
            ]
        ),
        .target(
            name: "RiptideSecurityShim"
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
                .product(name: "Yams", package: "Yams"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Assets.xcassets"),
            ],
            swiftSettings: [
                // Xcode `#Preview` macros need the PreviewsMacros compiler
                // plugin, which ships with Xcode but not with plain
                // toolchains / CommandLineTools builds. CLI builds define
                // this to skip preview bodies; remove it to restore previews
                // under Xcode.
                .define("RIPTIDE_NO_PREVIEWS"),
            ]
        ),
        .executableTarget(
            name: "RiptideMihomoService",
            dependencies: [
                "Riptide",
            ],
            path: "Sources/RiptideMihomoService"
        ),
        .testTarget(
            name: "RiptideAppUITests",
            dependencies: [
                "Riptide",
                "RiptideApp"
            ],
            path: "Tests/RiptideAppUITests",
            exclude: ["Fixtures"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .target(
            name: "RiptideTunnel",
            dependencies: [
                "Riptide",
            ],
            path: "Sources/RiptideTunnel"
        ),
        .target(
            name: "RiptideWidget",
            dependencies: [
                "Riptide",
            ],
            path: "Sources/RiptideWidget",
            exclude: ["INSTALLATION.md"]
        ),
        .target(
            name: "RiptideQuickLook",
            dependencies: [
                "Riptide",
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/RiptideQuickLook",
            exclude: ["INSTALLATION.md"]
        ),
        .testTarget(
            name: "RiptideTests",
            dependencies: [
                "Riptide",
                "RiptideCLI",
                "RiptideApp",
                "RiptideWidget",
                "RiptideQuickLook",
            ]
        ),
        .binaryTarget(
            name: "GoCore",
            path: "Frameworks/GoCore.xcframework"
        ),
    ],
    // All targets build in the Swift 5 language mode. Declared once at the
    // package level (the per-target `swiftLanguageMode` API is unavailable
    // in some CLT SwiftPM builds).
    swiftLanguageVersions: [.v5],
)
