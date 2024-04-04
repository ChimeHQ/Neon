// swift-tools-version: 5.8

import PackageDescription

let package = Package(
	name: "Neon",
	platforms: [
		.macOS(.v10_15),
		.iOS(.v13),
		.tvOS(.v13),
		.watchOS(.v6),
		.macCatalyst(.v13)
	],
	products: [
		.library(name: "Neon", targets: ["Neon"]),
	],
	dependencies: [
		.package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", revision: "b01904a3737649c1d8520106bbb285724fe5b0bb"),
		.package(url: "https://github.com/ChimeHQ/Rearrange", from: "1.8.1"),
	],
	targets: [
        .target(name: "ConcurrencyCompatibility"),
		.target(name: "RangeState", dependencies: ["ConcurrencyCompatibility", "Rearrange"]),
		.testTarget(name: "RangeStateTests", dependencies: ["RangeState"]),
		.target(
			name: "Neon",
			dependencies: [
                "ConcurrencyCompatibility",
                "RangeState",
                "Rearrange",
                "TreeSitterClient",
                .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter"),
            ]
		),
		.target(
			name: "TreeSitterClient",
			dependencies: [
                "ConcurrencyCompatibility",
				"RangeState",
				"Rearrange",
				"SwiftTreeSitter",
                .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter"),
			]
		),
		.target(
			name: "NeonTestsTreeSitterSwift",
			path: "tree-sitter-swift",
			sources: ["src/parser.c", "src/scanner.c"],
			publicHeadersPath: "bindings/swift",
			cSettings: [.headerSearchPath("src")]
		),
		.testTarget(name: "NeonTests", dependencies: ["Neon"]),
		.testTarget(name: "TreeSitterClientTests", dependencies: ["TreeSitterClient", "NeonTestsTreeSitterSwift"])
	]
)

let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency")
]

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(contentsOf: swiftSettings)
    target.swiftSettings = settings
}
