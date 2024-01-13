import Foundation

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
	public func map<T>(_ transform: @escaping (Output) -> T) -> HybridValueProvider<Input, T> where T: Sendable {
		.init(
			syncValue: { self.sync($0).map(transform) },
			asyncValue: { transform(await self.async($0)) }
		)
	}
}

extension HybridThrowingValueProvider {
	public func map<T>(_ transform: @escaping (Output) throws -> T) -> HybridThrowingValueProvider<Input, T> where T: Sendable {
		.init(
			syncValue: { try self.sync($0).map(transform) },
			asyncValue: { try transform(try await self.async($0)) }
		)
	}
}
