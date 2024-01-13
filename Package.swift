// swift-tools-version: 5.8

import PackageDescription

let package = Package(
	name: "Neon",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
	products: [
		.library(name: "Neon", targets: ["Neon"]),
	],
	dependencies: [
		.package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", revision: "87ed52a71d4ad6b5e6a11185b42f6f74eb5b47da"),
		.package(url: "https://github.com/ChimeHQ/Rearrange", from: "1.6.0"),
	],
	targets: [
        .target(name: "ConcurrencyCompatibility"),
		.target(name: "RangeState", dependencies: ["ConcurrencyCompatibility", "Rearrange"]),
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
