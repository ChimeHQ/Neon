import Foundation

public struct MainActorBackport {
	/// Execute the given body closure on the main actor without enforcing MainActor isolation.
	///
	/// It will crash if run on any non-main thread.
	@_unavailableFromAsync
	public func assumeIsolated<T>(_ body: @MainActor () throws -> T) rethrows -> T {
#if swift(>=5.9)
		if #available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *) {
			return try MainActor.assumeIsolated(body)
		}
#endif

		dispatchPrecondition(condition: .onQueue(.main))
		return try withoutActuallyEscaping(body) { fn in
			try unsafeBitCast(fn, to: (() throws -> T).self)()
		}
	}
}

extension MainActor {
	public static var backport: MainActorBackport {
		MainActorBackport()
	}
}

public struct DispatchQueueBackport {
	private let queue: DispatchQueue

	init(_ queue: DispatchQueue) {
		self.queue = queue
	}

	public func asyncUnsafe(group: DispatchGroup? = nil, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], execute unsafeWork: @escaping @convention(block) () -> Void) {
		let work = unsafeBitCast(unsafeWork, to: (@Sendable @convention(block) () -> Void).self)

		queue.async(group: group, qos: qos, flags: flags, execute: work)
	}
}

extension DispatchQueue {
	public var backport: DispatchQueueBackport {
		DispatchQueueBackport(self)
	}
}
