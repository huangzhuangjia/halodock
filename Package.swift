// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaloDock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HaloDock", targets: ["HaloDock"]),
        .executable(name: "HaloDockUpdater", targets: ["HaloDockUpdater"])
    ],
    targets: [
        .executableTarget(
            name: "HaloDock",
            dependencies: ["UpdateInstallation"],
            path: "Sources/HaloDock"
        ),
        .target(name: "UpdateInstallation"),
        .executableTarget(name: "HaloDockUpdater", dependencies: ["UpdateInstallation"]),
        .testTarget(name: "HaloDockTests", dependencies: ["HaloDock", "UpdateInstallation"])
    ]
)
