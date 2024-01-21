import Foundation

/// A type that can perform work both synchronously and asynchronously.
public struct HybridValueProvider<Input: Sendable, Output: Sendable> {
	public typealias SyncValueProvider = (Input) -> Output?
	public typealias AsyncValueProvider = (Input) async -> Output

	public let syncValueProvider: SyncValueProvider
	public let asyncValueProvider: AsyncValueProvider

	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		asyncValue: @escaping AsyncValueProvider
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = asyncValue
	}

	public func async(_ input: Input) async -> Output {
		await asyncValueProvider(input)
	}

	public func sync(_ input: Input) -> Output? {
		syncValueProvider(input)
	}
}

/// A type that can perform failable work both synchronously and asynchronously.
public struct HybridThrowingValueProvider<Input: Sendable, Output: Sendable> {
	public typealias SyncValueProvider = (Input) throws -> Output?
	public typealias AsyncValueProvider = (Input) async throws -> Output

	public let syncValueProvider: SyncValueProvider
	public let asyncValueProvider: AsyncValueProvider

	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		asyncValue: @escaping AsyncValueProvider
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = asyncValue
	}

	public func async(_ input: Input) async throws -> Output {
		try await asyncValueProvider(input)
	}

	public func sync(_ input: Input) throws -> Output? {
		try syncValueProvider(input)
	}
}

extension HybridValueProvider {
	/// Returns a new `HybridValueProvider` with a new output type.
	public func map<T>(_ transform: @escaping (Output) -> T) -> HybridValueProvider<Input, T> where T: Sendable {
		.init(
			syncValue: { self.sync($0).map(transform) },
			asyncValue: { transform(await self.async($0)) }
		)
	}

	/// Convert to a `HybridThrowingValueProvider`.
	public var throwing: HybridThrowingValueProvider<Input, Output> {
		.init(
			syncValue: self.syncValueProvider,
			asyncValue: self.asyncValueProvider
		)
	}
}

extension HybridThrowingValueProvider {
	/// Returns a new `HybridThrowingValueProvider` with a new output type.
	public func map<T>(_ transform: @escaping (Output) throws -> T) -> HybridThrowingValueProvider<Input, T> where T: Sendable {
		.init(
			syncValue: { try self.sync($0).map(transform) },
			asyncValue: { try transform(try await self.async($0)) }
		)
	}

	/// Transforms a `HybridThrowingValueProvider` into a `HybridValueProvider`.
	public func catching(_ block: @escaping (Input, Error) -> Output) -> HybridValueProvider<Input, Output> {
		.init(
			syncValue: {
				do {
					return try self.sync($0)
				} catch {
					return block($0, error)
				}
			},
			asyncValue: {
				do {
					return try await self.async($0)
				} catch {
					return block($0, error)
				}
			}
		)
	}
}
