// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "GrizzyClawMac",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "GrizzyClaw", targets: ["RunGrizzy"]),
        .executable(name: "GrizzyClawCLI", targets: ["GrizzyClawCLI"]),
        .library(name: "GrizzyClawCore", targets: ["GrizzyClawCore"]),
        .library(name: "GrizzyClawAgent", targets: ["GrizzyClawAgent"]),
        .library(name: "GrizzyClawMLX", targets: ["GrizzyClawMLX"]),
        .library(name: "GrizzyClawWorkspaceUI", targets: ["GrizzyClawWorkspaceUI"]),
        .library(name: "GrizzyClawUI", targets: ["GrizzyClawUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/MihaelIsaev/SwifCron.git", from: "2.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.10.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: Version(2, 31, 3)),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "GrizzyClawCore",
            dependencies: [
                .product(name: "Yams", package: "yams"),
                .product(name: "SwifCron", package: "swifcron"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/GrizzyClawCore",
            // Explicit copies so Xcode embeds Osaurus plugin manifests (`.copy("Resources")` alone can omit new subfolders).
            resources: [
                .copy("Resources/OsaurusPlugins"),
                .copy("Resources/BundledSkills"),
                .copy("Resources/builtin_mcp_marketplace.json"),
                .copy("Resources/swarm_workspace_templates.json"),
                .copy("Resources/mcp_discover.py"),
                .copy("Resources/mcp_call_tool.py"),
            ],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "GrizzyClawAgent",
            dependencies: ["GrizzyClawCore"],
            path: "Sources/GrizzyClawAgent",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ],
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("Contacts"),
                .linkedFramework("Vision"),
            ]
        ),
        .target(
            name: "GrizzyClawMLX",
            dependencies: [
                "GrizzyClawCore",
                "GrizzyClawAgent",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            path: "Sources/GrizzyClawMLX",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ]
        ),
        .target(
            name: "GrizzyClawWorkspaceUI",
            dependencies: ["GrizzyClawCore"],
            path: "Sources/GrizzyClawWorkspaceUI",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ]
        ),
        .target(
            name: "GrizzyClawUI",
            dependencies: ["GrizzyClawCore", "GrizzyClawAgent", "GrizzyClawMLX", "GrizzyClawWorkspaceUI"],
            path: "Sources/GrizzyClawUI",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ]
        ),
        .executableTarget(
            name: "RunGrizzy",
            dependencies: ["GrizzyClawCore", "GrizzyClawUI"],
            path: "Sources/RunGrizzy",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ]
        ),
        .executableTarget(
            name: "GrizzyClawCLI",
            dependencies: ["GrizzyClawCore"],
            path: "Sources/GrizzyClawCLI",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ]
        ),
        .testTarget(
            name: "GrizzyClawCoreTests",
            dependencies: ["GrizzyClawCore"],
            path: "Tests/GrizzyClawCoreTests"
        ),
        .testTarget(
            name: "GrizzyClawAgentTests",
            dependencies: ["GrizzyClawAgent"],
            path: "Tests/GrizzyClawAgentTests"
        ),
    ]
)
