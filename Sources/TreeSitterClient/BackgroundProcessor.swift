import Dispatch

fileprivate struct UnsafeContainer<T>: @unchecked Sendable {
	let value: T
}

final class BackgroundProcessor<Value> {
	enum AccessMode {
		case synchronous
		case synchronousPreferred
		case asynchronous
	}
	
	private let valueContainer: UnsafeContainer<Value>
	private let queue = DispatchQueue(label: "com.chimehq.Neon.BackgroundProcessor")
	private var pendingCount = 0
	private var pendingTask: Task<Void, Never>?

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
		
		pendingTask = nil
	}

	public func accessValueSynchronously<T>(
		operation: (Value?) throws -> T
	) throws -> T {
		if hasPendingWork {
			return try operation(nil)
		}
		
		let value = try queue.sync {
			try operation(valueContainer.value)
		}
		
		precondition(hasPendingWork == false)
		
		return value
	}
		
	public func accessValue<T: Sendable>(
		isolation: isolated (any Actor),
		preferSynchronous: Bool,
		operation: @escaping @Sendable (Value) throws -> sending T,
		completion: @escaping (Result<T, Error>) -> Void
	) {
		if preferSynchronous && hasPendingWork == false {
			let result = Result {
				try queue.sync {
					try operation(valueContainer.value)
				}
			}
			
			completion(result)

			return
		}
		
		beginBackgroundWork()
		
		nonisolated(unsafe) let unsafeValue = self.valueContainer.value
		
		Task {
			_ = isolation
			
			let result = await withCheckedContinuation { continuation in
				queue.async {
					let result = Result { try operation(unsafeValue) }
					
					continuation.resume(returning: result)
				}
			}
			
			endBackgroundWork()
			
			completion(result)
		}
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
