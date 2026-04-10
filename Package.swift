// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrizzyClawMac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "GrizzyClaw", targets: ["GrizzyClaw"]),
        .library(name: "GrizzyClawCore", targets: ["GrizzyClawCore"]),
    ],
    targets: [
        .target(
            name: "GrizzyClawCore",
            path: "Sources/GrizzyClawCore"
        ),
        .executableTarget(
            name: "GrizzyClaw",
            dependencies: ["GrizzyClawCore"],
            path: "Sources/GrizzyClaw"
        ),
    ]
)
