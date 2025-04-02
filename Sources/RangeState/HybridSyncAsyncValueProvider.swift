import Foundation

/// A type that can perform work both synchronously and asynchronously.
public struct HybridSyncAsyncValueProvider<Input, Output, Failure: Error> {
	public typealias SyncValueProvider = (Input) throws(Failure) -> Output?
	public typealias AsyncValueProvider = (isolated (any Actor), sending Input) async throws(Failure) -> sending Output

	public let syncValueProvider: SyncValueProvider
	public let asyncValueProvider: AsyncValueProvider

	public init(
		syncValue: @escaping SyncValueProvider = { _ in nil },
		asyncValue: @escaping AsyncValueProvider
	) {
		self.syncValueProvider = syncValue
		self.asyncValueProvider = asyncValue
	}

	public func async(isolation: isolated (any Actor), _ input: sending Input) async throws(Failure) -> sending Output {
		try await asyncValueProvider(isolation, input)
	}

	@MainActor
	@preconcurrency
	public func async(_ input: sending Input) async throws(Failure) -> sending Output {
		try await asyncValueProvider(MainActor.shared, input)
	}

	public func sync(_ input: Input) throws(Failure) -> Output? {
		try syncValueProvider(input)
	}
}

extension HybridSyncAsyncValueProvider {
	/// Create an instance that can statically prove to the compiler that asyncValueProvider is isolated to the MainActor.
	@preconcurrency
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

// I've not yet gotten these working right, but I think there could be something here.
extension HybridSyncAsyncValueProvider {
	// Returns a new `HybridSyncAsyncValueProvider` with a new output type.
//	func map<T>(_ transform: @escaping (isolated (any Actor)?, Output) throws -> T) -> HybridSyncAsyncValueProvider<Input, T, any Error> {
//		.init(
//			syncValue: { input in
//				guard let output = try sync(input) else {
//					return nil
//				}
//
//				return try transform(#isolation, output)
//			},
//			asyncValue: { (isolation, input) in
//				try transform(isolation, try await self.async(isolation: isolation, input))
//			}
//		)
//	}

//	/// Transforms the `Failure` type of `HybridSyncAsyncValueProvider` to `Never`,
//	func catching(_ block: @escaping (Input, Error) -> Output) -> HybridSyncAsyncValueProvider<Input, Output, Never> {
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
//					return try await self.async(isolation: $0, $1)
//				} catch {
//					return block($1, error)
//				}
//			}
//		)
//	}
}
