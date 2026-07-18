// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CrewPick",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CrewPickCore", targets: ["CrewPickCore"]),
        .executable(name: "CrewPickCoreCheck", targets: ["CrewPickCoreCheck"])
    ],
    targets: [
        .target(name: "CrewPickCore"),
        .executableTarget(name: "CrewPickCoreCheck", dependencies: ["CrewPickCore"], path: "Checks"),
        .testTarget(name: "CrewPickCoreTests", dependencies: ["CrewPickCore"])
    ]
)
