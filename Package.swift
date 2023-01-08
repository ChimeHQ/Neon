// swift-tools-version:5.5

import PackageDescription

let package = Package(
	name: "Neon",
	platforms: [.macOS(.v10_13), .iOS(.v11), .tvOS(.v11), .watchOS(.v4)],
	products: [
		.library(name: "Neon", targets: ["Neon"]),
	],
	dependencies: [
		.package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.7.0"),
		.package(url: "https://github.com/ChimeHQ/Rearrange", from: "1.5.3"),
	],
	targets: [
		.target(name: "Neon", dependencies: ["SwiftTreeSitter", "Rearrange", "TreeSitterClient"]),
		.target(name: "TreeSitterClient", dependencies: ["Rearrange", "SwiftTreeSitter"]),
		.target(name: "TestTreeSitterSwift",
				path: "tree-sitter-swift",
				sources: ["src/parser.c", "src/scanner.c"],
				publicHeadersPath: "bindings/swift",
				cSettings: [.headerSearchPath("src")]),
		.testTarget(name: "NeonTests", dependencies: ["Neon"]),
		.testTarget(name: "TreeSitterClientTests", dependencies: ["TreeSitterClient", "TestTreeSitterSwift"])
	]
)
