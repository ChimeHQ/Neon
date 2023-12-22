import Foundation

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
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

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public struct HybridThrowingValueProvider<Input: Sendable, Output: Sendable> {
	public typealias SyncValueProvider = (Input) throws -> Output?
	public typealias AsyncValueProvider = (Input) async throws -> Output

	public let syncValueProvider: SyncValueProvider
	public let asyncValueProvider: AsyncValueProvider

	public init(Input : Sendable,
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

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension HybridValueProvider {
	@MainActor
	public init(
		processor: Output,
		lazyProcessor: RangeProcessor,
		inputTransformer: @escaping (Input) -> (Int, RangeFillMode)
	) {
		self.init(
			syncValue: { input in
				let (location, fill) = inputTransformer(input)

				if lazyProcessor.processLocation(location, mode: fill) {
					return processor
				}

				return nil
			},
			asyncValue: { input in
				let (location, fill) = inputTransformer(input)

				lazyProcessor.processLocation(location, mode: fill)

				await lazyProcessor.processingCompleted()

				return processor
			}
		)
	}
}
