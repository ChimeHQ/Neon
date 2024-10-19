import Foundation

/// A type that can perform work both synchronously and asynchronously.
public struct HybridSyncAsyncValueProvider<Input, Output, Failure: Error> {
	public typealias SyncValueProvider = (sending Input) throws(Failure) -> sending Output?
	public typealias AsyncValueProvider = (isolated (any Actor)?, sending Input) async throws(Failure) -> sending Output

	public let syncValueProvider: SyncValueProvider
	public let asyncValueProvider: AsyncValueProvider

	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		asyncValue: @escaping AsyncValueProvider
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = asyncValue
	}

	public func async(isolation: isolated (any Actor)? = #isolation, _ input: sending Input) async throws(Failure) -> sending Output {
		try await asyncValueProvider(isolation, input)
	}


	public func sync(_ input: sending Input) throws(Failure) -> sending Output? {
		try syncValueProvider(input)
	}
}

extension HybridSyncAsyncValueProvider {
	/// Create an instance that can statically prove to the compiler that asyncValueProvider is isolated to the MainActor.
	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		mainActorAsyncValue: @escaping @MainActor (Input) async throws(Failure) -> sending Output
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = { _, input async throws(Failure) in
			try await mainActorAsyncValue(input)
		}
	}
}

// I'm not 100% sure these both work yet right yet.
extension HybridSyncAsyncValueProvider {
	// Returns a new `HybridSyncAsyncValueProvider` with a new output type.
	func map<T>(_ transform: @escaping (isolated (any Actor)?, Output) throws -> T) -> HybridSyncAsyncValueProvider<Input, T, any Error> {
		.init(
			syncValue: { input in try self.sync(input).map({ try transform(nil, $0) }) },
			asyncValue: { try transform($0, try await self.async(isolation: $0, $1)) }
		)
	}

	/// Transforms the `Failure` type of `HybridSyncAsyncValueProvider` to `Never`,
	func catching(_ block: @escaping (Input, Error) -> Output) -> HybridSyncAsyncValueProvider<Input, Output, Never> {
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
					return try await self.async(isolation: $0, $1)
				} catch {
					return block($1, error)
				}
			}
		)
	}
}
