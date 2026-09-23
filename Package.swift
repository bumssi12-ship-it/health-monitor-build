// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthMonitorCore",
    products: [
        .library(name: "HealthMonitorCore", targets: ["HealthMonitorCore"])
    ],
    targets: [
        .target(
            name: "HealthMonitorCore",
            path: "Shared"
        ),
        .testTarget(
            name: "HealthMonitorCoreTests",
            dependencies: ["HealthMonitorCore"],
            path: "CoreTests"
        )
    ]
)
