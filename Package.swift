// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "Neon",
    products: [
        .library(name: "Neon", targets: ["Neon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.6.1"),
        .package(url: "https://github.com/ChimeHQ/Rearrange", from: "1.5.3"),
    ],
    targets: [
        .target(name: "Neon", dependencies: ["SwiftTreeSitter", "Rearrange", "TreeSitterClient"]),
        .target(name: "TreeSitterClient", dependencies: ["Rearrange", "SwiftTreeSitter"]),
        .testTarget(name: "NeonTests", dependencies: ["Neon"]),
        .testTarget(name: "TreeSitterClientTests", dependencies: ["TreeSitterClient"])
    ]
)
