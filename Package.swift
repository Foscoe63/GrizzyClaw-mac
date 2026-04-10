// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrizzyClawMac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "GrizzyClaw", targets: ["RunGrizzy"]),
        .library(name: "GrizzyClawCore", targets: ["GrizzyClawCore"]),
        .library(name: "GrizzyClawUI", targets: ["GrizzyClawUI"]),
    ],
    targets: [
        .target(
            name: "GrizzyClawCore",
            path: "Sources/GrizzyClawCore"
        ),
        .target(
            name: "GrizzyClawUI",
            dependencies: ["GrizzyClawCore"],
            path: "Sources/GrizzyClawUI"
        ),
        .executableTarget(
            name: "RunGrizzy",
            dependencies: ["GrizzyClawUI"],
            path: "Sources/RunGrizzy"
        ),
    ]
)
