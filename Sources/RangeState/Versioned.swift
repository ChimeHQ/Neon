import Foundation

/// Represents a value with changes that can be tracked over time.
public struct Versioned<Version, Value> {
	public var value: Value
	public var version: Version

	public init(_ value: Value, version: Version) {
		self.value = value
		self.version = version
	}
}

extension Versioned: Equatable where Version : Equatable, Value : Equatable {}
extension Versioned: Sendable where Version : Sendable, Value : Sendable {}
extension Versioned: Hashable where Version : Hashable, Value : Hashable {}

public typealias VersionedRange<Version> = Versioned<Version, NSRange>

/// Describes a linear span of content that can be changed over time.
///
/// This can be used to model text storage. If your backing store supports versioning, this can be used to improve efficiency.
public protocol VersionedContent<Version> {
	associatedtype Version: Equatable & Sendable

	var currentVersion: Version { get }
	func length(for version: Version) -> Int?
}

extension VersionedContent {
	public var currentVersionedLength: Versioned<Version, Int> {
		let vers = currentVersion

		guard let value = length(for: vers) else {
			preconditionFailure("length of current version must always be available")
		}

		return .init(value, version: vers)
	}

	public var currentLength: Int {
		currentVersionedLength.value
	}
}

/// Content where only the current version is valid.
public final class UnversionableContent: VersionedContent {
	private let lengthProvider: () -> Int
	public private(set) var currentVersion: Int = 0

	public init(lengthProvider: @escaping () -> Int) {
		self.lengthProvider = lengthProvider
	}

	public func length(for version: Int) -> Int? {
		guard version == currentVersion else { return nil }

		return lengthProvider()
	}

	public func contentChanged() {
		self.currentVersion += 1
	}
}
