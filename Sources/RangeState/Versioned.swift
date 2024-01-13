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
public struct UnversionableContent: VersionedContent {
	private let lengthProvider: () -> Int
	public private(set) var currentVersion: Int = 0

	public init(lengthProvider: @escaping () -> Int) {
		self.lengthProvider = lengthProvider
	}

	public func length(for version: Int) -> Int? {
		guard version == currentVersion else { return nil }

		return lengthProvider()
	}

	public mutating func contentChanged() {
		self.currentVersion += 1
	}
}
