// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "Neon",
    platforms: [.macOS(.v10_13), .iOS(.v11)],
    products: [
        .library(name: "Neon", targets: ["Neon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.5.0"),
        .package(url: "https://github.com/ChimeHQ/Rearrange", from: "1.5.1"),
    ],
    targets: [
        .target(name: "Neon", dependencies: ["SwiftTreeSitter", "Rearrange"]),
        .testTarget(name: "NeonTests", dependencies: ["Neon"]),
    ]
)
