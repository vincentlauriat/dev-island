// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DevIsland",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "DevIslandCore",
            targets: ["DevIslandCore"]
        ),
        .executable(
            name: "DevIslandHooks",
            targets: ["DevIslandHooks"]
        ),
        .executable(
            name: "DevIslandSetup",
            targets: ["DevIslandSetup"]
        ),
        .executable(
            name: "DevIslandApp",
            targets: ["DevIslandApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "DevIslandCore"
        ),
        .executableTarget(
            name: "DevIslandHooks",
            dependencies: ["DevIslandCore"]
        ),
        .executableTarget(
            name: "DevIslandSetup",
            dependencies: ["DevIslandCore"]
        ),
        .executableTarget(
            name: "DevIslandApp",
            dependencies: [
                "DevIslandCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "DevIslandCoreTests",
            dependencies: ["DevIslandCore"]
        ),
        .testTarget(
            name: "DevIslandAppTests",
            dependencies: ["DevIslandApp", "DevIslandCore"]
        ),
    ]
)
