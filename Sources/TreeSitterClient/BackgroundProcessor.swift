import Dispatch

final class BackgroundProcessor<Value> {
	enum AccessMode {
		case synchronous
		case synchronousPreferred
		case asynchronous
	}
	
	private let value: Value
	private let queue = DispatchQueue(label: "com.chimehq.Neon.BackgroundProcessor")
	private var pendingCount = 0
	private var pendingTask: Task<Void, Never>?

	public init(value: Value) {
		self.value = value
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
		
		let opResult = try queue.sync {
			try operation(value)
		}
		
		precondition(hasPendingWork == false)
		
		return opResult
	}
		
	public func accessValue<T>(
		isolation: isolated (any Actor),
		preferSynchronous: Bool,
		operation: @escaping @Sendable (Value) throws -> sending T,
		completion: @escaping (sending Result<T, Error>) -> Void
	) {
		if preferSynchronous && hasPendingWork == false {
			// this is necessary because queue.sync does not return a sending value. However, because operation's return is sending, this must be safe.
			nonisolated(unsafe) let result = Result {
				try queue.sync {
					try operation(value)
				}
			}
			
			completion(result)

			return
		}
		
		beginBackgroundWork()
		
		nonisolated(unsafe) let unsafeValue = value
		
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

	public func accessValue<T>(
		isolation: isolated (any Actor),
		operation: @escaping @Sendable (Value) throws -> sending T
	) async throws -> T {
		// older compilers believe this is unsafe
#if compiler(<6.1)
		nonisolated(unsafe) let localSelf = self
#else
		let localSelf = self
#endif

		return try await withCheckedThrowingContinuation(isolation: isolation) { continuation in
			localSelf.accessValue(isolation: isolation, preferSynchronous: false, operation: operation, completion: { result in
				continuation.resume(with: result)
			})
		}
	}
}
