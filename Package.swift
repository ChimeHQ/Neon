// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "Neon",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "Neon", targets: ["Neon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.4.0"),
        .package(url: "https://github.com/ChimeHQ/Rearrange", from: "1.5.1"),
        .package(url: "https://github.com/ChimeHQ/OperationPlus", from: "1.5.4"),
    ],
    targets: [
        .target(name: "Neon", dependencies: ["SwiftTreeSitter", "Rearrange", "OperationPlus"]),
        .testTarget(
            name: "NeonTests",
            dependencies: ["Neon"],
            linkerSettings: [.linkedLibrary("c++")]
        ),
    ]
)
