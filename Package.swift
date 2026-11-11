// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnowDesktop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SnowDesktop", targets: ["SnowDesktop"]),
        .library(name: "SnowCore", targets: ["SnowCore"])
    ],
    targets: [
        .target(name: "SnowCore"),
        .executableTarget(name: "SnowDesktop", dependencies: ["SnowCore"]),
        .testTarget(name: "SnowCoreTests", dependencies: ["SnowCore"])
    ]
)
