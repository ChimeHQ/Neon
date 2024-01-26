import Foundation

extension HybridValueProvider {
	/// Construct a `HybridValueProvider` that will first attempt to process a location using a `RangeProcessor`.
	@MainActor
	public init(
		rangeProcessor: RangeProcessor,
		inputTransformer: @escaping (Input) -> (Int, RangeFillMode),
		syncValue: @escaping SyncValueProvider,
		asyncValue: @escaping @MainActor (Input) async -> Output
	) {
		self.init(
			syncValue: { input in
				let (location, fill) = inputTransformer(input)

				if rangeProcessor.processLocation(location, mode: fill) {
					return syncValue(input)
				}

				return nil
			},
			asyncValue: { input, actor in
				let (location, fill) = inputTransformer(input)

				await rangeProcessor.processLocation(location, mode: fill)
				await rangeProcessor.processingCompleted()

				return await asyncValue(input)
			}
		)
	}
}

extension HybridThrowingValueProvider {
	/// Construct a `HybridThrowingValueProvider` that will first attempt to process a location using a `RangeProcessor`.
	@MainActor
	public init(
		rangeProcessor: RangeProcessor,
		inputTransformer: @escaping (Input) -> (Int, RangeFillMode),
		syncValue: @escaping SyncValueProvider,
		asyncValue: @escaping @MainActor (Input) async throws -> Output
	) {
		self.init(
			syncValue: { input in
				let (location, fill) = inputTransformer(input)

				if rangeProcessor.processLocation(location, mode: fill) {
					return try syncValue(input)
				}

				return nil
			},
			asyncValue: { input, actor in
				let (location, fill) = inputTransformer(input)

				await rangeProcessor.processLocation(location, mode: fill)
				await rangeProcessor.processingCompleted()

				return try await asyncValue(input)
			}
		)
	}
}
