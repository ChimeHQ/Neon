import Foundation

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

public struct VersionedContent<Version> {
	public let version: () -> Version
	public let length: (Version) -> Int?

	public init(
		version: @escaping () -> Version,
		length: @escaping (Version) -> Int?
	) {
		self.version = version
		self.length = length
	}

	public var currentVersionedLength: Versioned<Version, Int> {
		let vers = version()

		guard let value = length(vers) else {
			preconditionFailure("length of current version must always be available")
		}

		return .init(value, version: vers)
	}

	public var currentLength: Int {
		currentVersionedLength.value
	}
}
