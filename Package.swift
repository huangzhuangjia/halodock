// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaloDock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "HaloDock", targets: ["HaloDock"])
    ],
    targets: [
        .executableTarget(
            name: "HaloDock",
            path: "Sources/HaloDock"
        )
    ]
)
