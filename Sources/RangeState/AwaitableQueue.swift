struct AwaitableQueue<Element> {
	private typealias Continuation = CheckedContinuation<Void, Never>

	private enum Event {
		case element(Element)
		case waiter(Continuation)
	}

	private var pendingEvents = [Event]()

	init() {

	}

	public var hasPendingEvents: Bool {
		pendingEvents.contains { event in
			switch event {
			case .element:
				true
			case .waiter:
				false
			}
		}
	}

	public mutating func processingCompleted(isolation: isolated any Actor) async {
		if hasPendingEvents == false {
			return
		}

		await withCheckedContinuation { continuation in
			self.pendingEvents.append(.waiter(continuation))
		}
	}

	public mutating func enqueue(_ element: Element) {
		self.pendingEvents.append(.element(element))
	}

	public var pendingElements: [Element] {
		pendingEvents.compactMap {
			switch $0 {
			case let .element(value):
				value
			case .waiter:
				nil
			}
		}
	}

	public mutating func handlePendingWaiters() {
		while let event = pendingEvents.first {
			guard case let .waiter(continuation) = event else { break }

			continuation.resume()
			pendingEvents.removeFirst()
		}
	}

	mutating func next() -> Element? {
		handlePendingWaiters()

		guard case let .element(first) = pendingEvents.first else {
			return nil
		}

		self.pendingEvents.removeFirst()

		return first
	}
}
