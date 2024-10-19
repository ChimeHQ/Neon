import Foundation

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
