import Dispatch

fileprivate struct UnsafeContainer<T>: @unchecked Sendable {
	let value: T
}

final class BackgroundProcessor<Value> {
	private let valueContainer: UnsafeContainer<Value>
	private let queue = DispatchQueue(label: "com.chimehq.Neon.BackgroundProcessor")
	private var pendingCount = 0

	public init(value: Value) {
		self.valueContainer = UnsafeContainer(value: value)
	}

	public var hasPendingWork: Bool {
		pendingCount > 0
	}

	private func beginBackgroundWork() {
		precondition(pendingCount >= 0)
		pendingCount += 1
	}

	private func endBackgroundWork() {
		pendingCount -= 1
		precondition(pendingCount >= 0)
	}

	public func accessValueSynchronously() -> Value? {
		if hasPendingWork == false {
			return valueContainer.value
		}

		return nil
	}

	// I would like to downgrade T: Sendable to sending but that seems to not work
	public func accessValue<T: Sendable>(
		isolation: isolated (any Actor),
		preferSynchronous: Bool,
		operation: @escaping @Sendable (Value) throws -> sending T,
		completion: @escaping (Result<T, Error>) -> Void
	) {
		if preferSynchronous, let v = accessValueSynchronously() {
			precondition(hasPendingWork == false)

			let result = Result { try operation(v) }
			completion(result)

			precondition(hasPendingWork == false)

			return
		}


		self.beginBackgroundWork()

		Task {
			_ = isolation

			let result = await runOperation(operation: operation)

			self.endBackgroundWork()

			completion(result)
		}
	}

	private nonisolated func runOperation<T: Sendable>(operation: @escaping @Sendable (Value) throws -> sending T) async -> sending Result<T, Error> {
		Result { try operation(valueContainer.value) }
	}

	public func accessValue<T: Sendable>(
		isolation: isolated (any Actor),
		operation: @escaping @Sendable (Value) throws -> sending T
	) async throws -> T {
		try await withCheckedThrowingContinuation(isolation: isolation) { continuation in
			accessValue(isolation: isolation, preferSynchronous: false, operation: operation, completion: { result in
				continuation.resume(with: result)
			})
		}
	}
}
