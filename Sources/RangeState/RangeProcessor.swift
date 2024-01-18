import Foundation

import ConcurrencyCompatibility
import Rearrange

public enum RangeFillMode: Sendable, Hashable {
	/// No processing will be performed to satisfy the request.
	case none

	/// Any needed processing may happen in the future.
	///
	/// Both minimum and maximum delta ranges will be applied.
	case optional

	/// Any needed processing will be performed synchronously.
	///
	/// Maximum deltas will be ignored for the processing.
	case required
}

/// A type that can perform on-demand processing of range-based data.
@MainActor
public final class RangeProcessor {
	private typealias Continuation = CheckedContinuation<(), Never>
	private typealias VersionedMutation = Versioned<Int, RangeMutation>

	private enum Event {
		case change(VersionedMutation)
		case waiter(Continuation)
	}

	/// Function to apply changes.
	///
	/// These mutations can come from the content being modified or from operations that require lazy processing. The parameter's postApplyLimit property defines the maximum read location and needs to be respected to preserve the lazy access semantics.
	public typealias ChangeHandler = (RangeMutation, @MainActor @escaping () -> Void) -> Void
	public typealias LengthProvider = () -> Int

	public struct Configuration {
		public let lengthProvider: LengthProvider
		public let changeHandler: ChangeHandler
		/// The minimum and maximum deltas that are used for changes.
		///
		/// While the minimum always applies, the maximum will only be used for optional filling.
		public let deltaRange: Range<Int>

		public init(
			deltaRange: Range<Int> = 1..<Int.max,
			lengthProvider: @escaping LengthProvider,
			changeHandler: @escaping ChangeHandler
		) {
			self.deltaRange = deltaRange
			self.lengthProvider = lengthProvider
			self.changeHandler = changeHandler
		}
	}

	private var pendingEvents = [Event]()

    public let configuration: Configuration

	// when starting, we have not even processed zero yet
	public private(set) var maximumProcessedLocation: Int?
	private var targetProcessingLocation: Int = -1
	private var pendingProcessedLocation: Int = -1
	private var version = 0
	private var processedVersion = -1

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

	private var contentLength: Int {
		configuration.lengthProvider()
	}
}

extension RangeProcessor {
	private func deltaRange(for mode: RangeFillMode) -> Range<Int> {
		switch mode {
		case .none, .optional:
			configuration.deltaRange
		case .required:
			configuration.deltaRange.lowerBound..<Int.max
		}
	}

	private func fillMutationNeeded(for location: Int, mode: RangeFillMode) -> RangeMutation? {
		let length = contentLength

		precondition(location <= length)

		let start = max(maximumProcessedLocation ?? 0, 0)
		let realDelta = location - start

		if realDelta <= 0 {
			return nil
		}

		let maxDelta = length - start
		let deltaRange = deltaRange(for: mode)
		let adjustedDelta = min(max(realDelta, deltaRange.lowerBound), deltaRange.upperBound)
		let delta = min(adjustedDelta, maxDelta)

		let range = NSRange(start..<start)

		return RangeMutation(range: range, delta: delta)
	}

	@discardableResult
	public func processLocation(_ location: Int, mode: RangeFillMode = .required) -> Bool {
		guard let mutation = fillMutationNeeded(for: location, mode: mode) else {
			return true
		}

		switch mode {
		case .none:
			return false
		case .optional:
			// update our target
			self.targetProcessingLocation = max(location, targetProcessingLocation)
			
			scheduleFilling()
		case .required:
			processMutation(mutation)
		}

		// could have been done synchronously, so check here for convenience
		return processed(location)
	}

    public func processed(_ location: Int) -> Bool {
		precondition(location >= 0)

		guard let maximumProcessedLocation else { return false }

		return maximumProcessedLocation >= location
    }

	public func processed(_ range: NSRange) -> Bool {
		processed(range.location)
	}

	public var hasPendingChanges: Bool {
		pendingEvents.contains { event in
			switch event {
			case .change:
				true
			case .waiter:
				false
			}
		}
	}

    public func processingCompleted() async {
		if hasPendingChanges == false {
			return
		}

        await withCheckedContinuation { continuation in
			self.pendingEvents.append(.waiter(continuation))
        }
    }

	/// Array of any mutations that are scheduled to be applied.
	///
	/// You can use this property to transform Range, IndexSet, and RangeTarget values to match the current content.
	public var pendingMutations: [RangeMutation] {
		pendingEvents.compactMap {
			switch $0 {
			case let .change(mutation):
				mutation.value
			case .waiter:
				nil
			}
		}
	}

	public func didChangeContent(_ mutation: RangeMutation) {
		guard processed(mutation.range) else { return }

		processMutation(mutation)
	}

	public func didChangeContent(in range: NSRange, delta: Int) {
		let mutation = RangeMutation(range: range, delta: delta)

        didChangeContent(mutation)
	}

	private func processMutation(_ mutation: RangeMutation) {
		self.pendingEvents.append(.change(VersionedMutation(mutation, version: version)))
		self.version += 1

		self.pendingProcessedLocation += mutation.delta
		precondition(pendingProcessedLocation >= 0)

		// at this point, it is possible that the target location is no longer meaningful. But that's ok, because it will be clamped and possibly overwritten anyways

		configuration.changeHandler(mutation, {
			self.completeContentChanged(mutation)
		})
	}

	private func completeContentChanged(_ mutation: RangeMutation) {
		self.processedVersion += 1

		resumeLeadingContinuations()

		guard case let .change(first) = pendingEvents.first else {
			preconditionFailure()
		}

		precondition(first.version == processedVersion, "changes must always be completed in order")
		precondition(first.value == mutation, "completed mutation does not match the expected value")

		self.pendingEvents.removeFirst()

		// do this again, just in case there are any
		resumeLeadingContinuations()

		updateProcessedLocation(by: mutation.delta)

		scheduleFilling()
	}

	public func continueFillingIfNeeded() {
		if hasPendingChanges {
			return
		}

		self.targetProcessingLocation = min(targetProcessingLocation, contentLength)
		let mutation = fillMutationNeeded(for: targetProcessingLocation, mode: .optional)

		guard let mutation else { return }

		processMutation(mutation)
	}

	private func scheduleFilling() {
		DispatchQueue.main.async {
			self.continueFillingIfNeeded()
		}
	}
}

extension RangeProcessor {
	private func updateProcessedLocation(by delta: Int) {
		var newMax = maximumProcessedLocation ?? 0

		newMax += delta

		precondition(newMax >= 0)

		self.maximumProcessedLocation = newMax
	}

	private func resumeLeadingContinuations() {
		while let event = pendingEvents.first {
			guard case let .waiter(continuation) = event else { break }

			continuation.resume()
			pendingEvents.removeFirst()
		}
	}
}
