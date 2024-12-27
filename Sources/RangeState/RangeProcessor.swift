import Foundation

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
public final class RangeProcessor {
	private typealias VersionedMutation = Versioned<Int, RangeMutation>

	/// Function to apply changes.
	///
	/// These mutations can come from the content being modified or from operations that require lazy processing. The parameter's postApplyLimit property defines the maximum read location and needs to be respected to preserve the lazy access semantics.
	public typealias ChangeHandler = (RangeMutation, @escaping () -> Void) -> Void
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

	private var pendingEventQueue = AwaitableQueue<VersionedMutation>()

    public let configuration: Configuration

	// when starting, we have not even processed zero yet
	public private(set) var maximumProcessedLocation: Int?
	private var targetProcessingLocation: Int = -1
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

	/// Ensure that a location has been processed
	///
	/// - Returns: true if the location has been processed

	@discardableResult
	public func processLocation(isolation: isolated (any Actor)? = #isolation, _ location: Int, mode: RangeFillMode = .required) -> Bool {
		switch mode {
		case .none:
			break
		case .optional:
			// update our target
			self.targetProcessingLocation = max(location, targetProcessingLocation)
			
			scheduleFilling(in: isolation)
		case .required:
			if hasPendingChanges {
				break
			}

			if let mutation = fillMutationNeeded(for: location, mode: mode) {
				processMutation(mutation, in: isolation)
			}
		}

		// could have been done synchronously, so check here for convenience
		return processed(location)
	}

	/// Check for the processed state of a location.
	///
	/// This method will not cause any processing to occur.
	public func processed(_ location: Int) -> Bool {
		precondition(location >= 0)

		guard let maximumProcessedLocation else { return false }

		return maximumProcessedLocation >= location
	}

	public func processed(_ range: NSRange) -> Bool {
		processed(range.location)
	}

	public var hasPendingChanges: Bool {
		pendingEventQueue.hasPendingEvents
	}

    public func processingCompleted(isolation: isolated (any Actor)) async {
		await pendingEventQueue.processingCompleted(isolation: isolation)
    }

	/// Array of any mutations that are scheduled to be applied.
	///
	/// You can use this property to transform Range, IndexSet, and RangeTarget values to match the current content.
	public var pendingMutations: [RangeMutation] {
		pendingEventQueue.pendingElements.map { $0.value }
	}

	public func didChangeContent(_ mutation: RangeMutation) {
		didChangeContent(in: mutation.range, delta: mutation.delta)
	}

	public func didChangeContent(isolation: isolated (any Actor)? = #isolation, in range: NSRange, delta: Int) {
		if processed(range.location) == false {
			return
		}

		guard let limit = maximumProcessedLocation else {
			return
		}

		precondition(limit >= 0)

		let visibleRange = range.clamped(to: limit)
		let effectiveLimit = limit
		let clampLength = range.upperBound - visibleRange.upperBound

		precondition(clampLength >= 0)

		// The logic to adjust the delta is pretty tricky.
		let visibleDelta: Int

		if clampLength == 0 {
			visibleDelta = delta
		} else if delta < 0 {
			visibleDelta = max(delta + clampLength, 0)
		} else {
			visibleDelta = 0
		}

		let mutation = RangeMutation(range: visibleRange, delta: visibleDelta, limit: effectiveLimit)

		processMutation(mutation, in: isolation)
	}

	private func processMutation(_ mutation: RangeMutation, in isolation: isolated (any Actor)?) {
		pendingEventQueue.enqueue(VersionedMutation(mutation, version: version))
		self.version += 1

		// this requires a very strange workaround to get the correct isolation inheritance from this changeHandler arrangement. I believe this is a bug.
		// https://github.com/swiftlang/swift/issues/77067
		func _completeContentChanged() {
			self.completeContentChanged(mutation, in: isolation)
		}

		// at this point, it is possible that the target location is no longer meaningful. But that's ok, because it will be clamped and possibly overwritten anyways
		configuration.changeHandler(mutation, _completeContentChanged)
	}

	private func completeContentChanged(_ mutation: RangeMutation, in isolation: isolated (any Actor)?) {
		self.processedVersion += 1

		guard let first = pendingEventQueue.next() else {
			preconditionFailure()
		}

		precondition(first.version == processedVersion, "changes must always be completed in order")
		precondition(first.value == mutation, "completed mutation does not match the expected value")

		updateProcessedLocation(by: mutation.delta)

		scheduleFilling(in: isolation)
	}

	public func continueFillingIfNeeded(isolation: isolated (any Actor)? = #isolation) {
		if hasPendingChanges {
			return
		}

		self.targetProcessingLocation = min(targetProcessingLocation, contentLength)
		let mutation = fillMutationNeeded(for: targetProcessingLocation, mode: .optional)

		guard let mutation else {
			return
		}

		processMutation(mutation, in: isolation)
	}

	private func scheduleFilling(in isolation: isolated (any Actor)?) {
		Task {
			self.continueFillingIfNeeded(isolation: isolation)

			// it is very important to double check here, in case
			// any waiters stuck in and we have no more work to do
			self.pendingEventQueue.handlePendingWaiters()
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
}
