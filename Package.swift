// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RSSRadar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "RSSRadar",
            targets: ["RSSRadarApp"]
        ),
        .library(
            name: "RSSRadarCore",
            targets: ["RSSRadarCore"]
        ),
        .library(
            name: "RSSRadarPersistence",
            targets: ["RSSRadarPersistence"]
        ),
        .library(
            name: "RSSRadarFeeds",
            targets: ["RSSRadarFeeds"]
        ),
        .library(
            name: "RSSRadarAI",
            targets: ["RSSRadarAI"]
        ),
        .library(
            name: "RSSRadarProcessing",
            targets: ["RSSRadarProcessing"]
        ),
        .library(
            name: "RSSRadarExport",
            targets: ["RSSRadarExport"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "9.1.2"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.8.8")
    ],
    targets: [
        .executableTarget(
            name: "RSSRadarApp",
            dependencies: [
                "RSSRadarCore",
                "RSSRadarPersistence",
                "RSSRadarFeeds",
                "RSSRadarAI",
                "RSSRadarProcessing"
            ],
            path: "RSSRadarApp",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "RSSRadarCore",
            path: "Packages/RSSRadarCore/Sources/RSSRadarCore"
        ),
        .target(
            name: "RSSRadarPersistence",
            dependencies: [
                "RSSRadarCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Packages/RSSRadarPersistence/Sources/RSSRadarPersistence",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "RSSRadarFeeds",
            dependencies: [
                "RSSRadarCore",
                .product(name: "FeedKit", package: "FeedKit"),
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            path: "Packages/RSSRadarFeeds/Sources/RSSRadarFeeds"
        ),
        .target(
            name: "RSSRadarAI",
            dependencies: ["RSSRadarCore"],
            path: "Packages/RSSRadarAI/Sources/RSSRadarAI",
            resources: [
                .process("Prompts")
            ]
        ),
        .target(
            name: "RSSRadarProcessing",
            dependencies: [
                "RSSRadarCore",
                "RSSRadarPersistence",
                "RSSRadarFeeds",
                "RSSRadarAI"
            ],
            path: "Packages/RSSRadarProcessing/Sources/RSSRadarProcessing"
        ),
        .target(
            name: "RSSRadarExport",
            dependencies: [
                "RSSRadarCore",
                "RSSRadarProcessing"
            ],
            path: "Packages/RSSRadarExport/Sources/RSSRadarExport"
        ),
        .testTarget(
            name: "RSSRadarCoreTests",
            dependencies: ["RSSRadarCore"],
            path: "Tests/RSSRadarCoreTests"
        ),
        .testTarget(
            name: "RSSRadarPersistenceTests",
            dependencies: [
                "RSSRadarPersistence",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/RSSRadarPersistenceTests"
        ),
        .testTarget(
            name: "RSSRadarFeedsTests",
            dependencies: ["RSSRadarFeeds"],
            path: "Tests/RSSRadarFeedsTests",
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "RSSRadarAITests",
            dependencies: ["RSSRadarAI"],
            path: "Tests/RSSRadarAITests",
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "RSSRadarProcessingTests",
            dependencies: [
                "RSSRadarProcessing",
                "RSSRadarPersistence",
                "RSSRadarAI"
            ],
            path: "Tests/RSSRadarProcessingTests",
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "RSSRadarExportTests",
            dependencies: [
                "RSSRadarExport",
                "RSSRadarProcessing"
            ],
            path: "Tests/RSSRadarExportTests"
        )
    ]
)
