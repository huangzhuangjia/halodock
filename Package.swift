// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaloDock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HaloDock", targets: ["HaloDock"]),
        .executable(name: "HaloDockUpdater", targets: ["HaloDockUpdater"]),
        .executable(name: "HaloDockPowerGuard", targets: ["HaloDockPowerGuard"])
    ],
    targets: [
        .executableTarget(
            name: "HaloDock",
            dependencies: ["UpdateInstallation", "ClosedLidSupport"],
            path: "Sources/HaloDock"
        ),
        .target(name: "UpdateInstallation"),
        .target(name: "ClosedLidSupport"),
        .executableTarget(name: "HaloDockPowerGuard", dependencies: ["ClosedLidSupport"]),
        .executableTarget(name: "HaloDockUpdater", dependencies: ["UpdateInstallation"]),
        .testTarget(name: "HaloDockTests", dependencies: ["HaloDock", "UpdateInstallation", "ClosedLidSupport"])
    ]
)
