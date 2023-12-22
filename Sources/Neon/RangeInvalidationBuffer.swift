import Foundation

public final class RangeInvalidationBuffer {
	public typealias Handler = (IndexSet) -> Void
	public typealias LengthProvider = () -> Int

	private enum State: Hashable {
		case idle
		case buffering(IndexSet, Int)
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
			self.state = .buffering(IndexSet(), 1)
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

	public func invalidate(_ set: IndexSet) {
		switch state {
		case .idle:
			invalidationHandler(set)
		case let .buffering(existing, count):
			precondition(count > 0)

			self.state = .buffering(existing.union(set), count)
		}
	}

	public func invalidate(_ range: NSRange) {
		invalidate(IndexSet(integersIn: range))
	}
}
