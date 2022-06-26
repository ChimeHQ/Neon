// swift-tools-version:5.7

import PackageDescription

let package = Package(
    name: "Neon",
    platforms: [.macOS(.v10_13), .iOS(.v11), .tvOS(.v11), .watchOS(.v4)],
    products: [
        .library(name: "Neon", targets: ["Neon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.6.1"),
        .package(url: "https://github.com/ChimeHQ/Rearrange", from: "1.5.1"),
    ],
    targets: [
        .target(name: "Neon", dependencies: ["SwiftTreeSitter", "Rearrange", "TreeSitterClient"]),
        .target(name: "TreeSitterClient", dependencies: ["Rearrange", "SwiftTreeSitter"]),
        .testTarget(name: "NeonTests", dependencies: ["Neon", "TreeSitterClient"]),
    ]
)
