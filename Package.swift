// swift-tools-version: 6.0

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
		.package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", branch: "main"),
		.package(url: "https://github.com/ChimeHQ/Rearrange", from: "2.0.0"),
	],
	targets: [
		.target(name: "RangeState", dependencies: ["Rearrange"]),
		.testTarget(name: "RangeStateTests", dependencies: ["RangeState"]),
		.target(
			name: "Neon",
			dependencies: [
				"RangeState",
				"Rearrange",
				"TreeSitterClient",
				.product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter"),
			]
		),
		.target(
			name: "TreeSitterClient",
			dependencies: [
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
