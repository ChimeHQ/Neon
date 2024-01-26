import Foundation

/// A type that can perform work both synchronously and asynchronously.
public struct HybridValueProvider<Input: Sendable, Output: Sendable> {
	public typealias SyncValueProvider = (Input) -> Output?
	public typealias AsyncValueProvider = (Input, isolated any Actor) async -> Output

	public let syncValueProvider: SyncValueProvider
	public let asyncValueProvider: AsyncValueProvider

	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		asyncValue: @escaping AsyncValueProvider
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = asyncValue
	}

	public func async(_ input: Input, isolatedTo actor: any Actor) async -> Output {
		await asyncValueProvider(input, actor)
	}


	public func sync(_ input: Input) -> Output? {
		syncValueProvider(input)
	}
}

extension HybridValueProvider {
	/// Create an instance that can statically prove to the compiler that asyncValueProvider is isolated to the MainActor.
	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		mainActorAsyncValue: @escaping @MainActor (Input) async -> Output
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = { input, _ in
			return await mainActorAsyncValue(input)
		}
	}

	/// Hopefully temporary until https://github.com/apple/swift/pull/71143 is available.
	@MainActor
	public func mainActorAsync(_ input: Input) async -> Output {
		await asyncValueProvider(input, MainActor.shared)
	}
}

/// A type that can perform failable work both synchronously and asynchronously.
public struct HybridThrowingValueProvider<Input: Sendable, Output: Sendable> {
	public typealias SyncValueProvider = (Input) throws -> Output?
	public typealias AsyncValueProvider = (Input, isolated any Actor) async throws -> Output

	public let syncValueProvider: SyncValueProvider
	public let asyncValueProvider: AsyncValueProvider

	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		asyncValue: @escaping AsyncValueProvider
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = asyncValue
	}

	public func async(_ input: Input, isolatedTo actor: any Actor) async throws -> Output {
		try await asyncValueProvider(input, actor)
	}

	public func sync(_ input: Input) throws -> Output? {
		try syncValueProvider(input)
	}
}

extension HybridThrowingValueProvider {
	/// Create an instance that can statically prove to the compiler that asyncValueProvider is isolated to the MainActor.
	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		mainActorAsyncValue: @escaping @MainActor (Input) async -> Output
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = { input, _ in
			return await mainActorAsyncValue(input)
		}
	}

	/// Hopefully temporary until https://github.com/apple/swift/pull/71143 is available.
	@MainActor
	public func mainActorAsync(_ input: Input) async throws -> Output {
		try await asyncValueProvider(input, MainActor.shared)
	}
}

// I believe these may still be implementable when https://github.com/apple/swift/pull/71143 is available.
//extension HybridValueProvider {
//	/// Returns a new `HybridValueProvider` with a new output type.
//	public func map<T>(_ transform: @escaping (Output) -> T) -> HybridValueProvider<Input, T> where T: Sendable {
//		.init(
//			syncValue: { self.sync($0).map(transform) },
//			asyncValue: { transform(await self.async($0, isolatedTo: $1)) }
//		)
//	}
//
//	/// Convert to a `HybridThrowingValueProvider`.
//	public var throwing: HybridThrowingValueProvider<Input, Output> {
//		.init(
//			syncValue: self.syncValueProvider,
//			asyncValue: self.asyncValueProvider
//		)
//	}
//}

//extension HybridThrowingValueProvider {
	/// Returns a new `HybridThrowingValueProvider` with a new output type.
//	public func map<T>(_ transform: @escaping (Output, isolated (any Actor)?) throws -> T) -> HybridThrowingValueProvider<Input, T> where T: Sendable {
//		.init(
//			syncValue: { input in try self.sync($0).map({ transform($0, nil) }) },
//			asyncValue: { try transform(try await self.async($0, isolatedTo: $1), $1) }
//		)
//	}

//	/// Transforms a `HybridThrowingValueProvider` into a `HybridValueProvider`.
//	public func catching(_ block: @escaping (Input, Error) -> Output) -> HybridValueProvider<Input, Output> {
//		.init(
//			syncValue: {
//				do {
//					return try self.sync($0)
//				} catch {
//					return block($0, error)
//				}
//			},
//			asyncValue: {
//				do {
//					return try await self.async($0, isolatedTo: $1)
//				} catch {
//					return block($0, error)
//				}
//			}
//		)
//	}
//}
