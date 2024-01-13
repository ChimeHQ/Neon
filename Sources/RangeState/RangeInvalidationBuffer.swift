import Foundation

public final class RangeInvalidationBuffer {
	public typealias Handler = (RangeTarget) -> Void

	private enum State: Hashable {
		case idle
		case buffering(RangeTarget, Int)
	}

	private var state = State.idle
	public var invalidationHandler: Handler = { _ in }

	public init() {
	}
}

extension RangeInvalidationBuffer {
	public func beginBuffering() {
		switch state {
		case .idle:
			self.state = .buffering(.set(IndexSet()), 1)
		case let .buffering(set, count):
			self.state = .buffering(set, count + 1)
		}
	}

	public func endBuffering() {
		switch state {
		case .idle:
			preconditionFailure()
		case let .buffering(set, 1):
			invalidationHandler(set)
			self.state = .idle
		case let .buffering(set, count):
			precondition(count > 1)
			self.state = .buffering(set, count - 1)
		}
	}

	public func invalidate(_ target: RangeTarget) {
		switch state {
		case .idle:
			invalidationHandler(target)
		case let .buffering(existing, count):
			precondition(count > 0)

			self.state = .buffering(existing.union(target), count)
		}
	}
}
