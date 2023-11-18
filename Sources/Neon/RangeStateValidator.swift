import Foundation
import Rearrange

@available(macOS 10.15, iOS 13.0, *)
public final class RangeStateValidator {
	public enum ValidationResult: Sendable, Hashable {
		case success(NSRange)
		case asyncRequired
	}

	public typealias LengthProvider = () -> Int
	public typealias SyncValidateRange = (NSRange) -> ValidationResult
	public typealias ValidateRange = (NSRange) async -> NSRange

	public struct Configuration {
		public let lengthProvider: LengthProvider
		public let syncValidateRange: SyncValidateRange
		public let validateRange: ValidateRange

		public init(
			lengthProvider: @escaping LengthProvider,
			syncValidateRange: @escaping SyncValidateRange,
			validateRange: @escaping ValidateRange
		) {
			self.lengthProvider = lengthProvider
			self.syncValidateRange = syncValidateRange
			self.validateRange = validateRange
		}
	}

	private var validSet = IndexSet()
	private var pendingSet = IndexSet()
	private var pendingTask: Task<Void, Never>?
	private var pendingCount: Int = 0
	let configuration: Configuration

	/// Maximum amount to expand requests outside of the working range.
	public var prefetchLength: Int = 1024

	/// A single range that makes up the active working area.
	///
	/// Setting this to nil causes the workingRange to be the entire content.
	public var workingRange: NSRange? {
		didSet {
			workingRangeDidChange()
		}
	}

	public init(configuration: Configuration) {
		self.configuration = configuration
	}

	public func invalidate(_ region: Region = .all) {
		let set = region.indexSet(with: fullSet)

		if set.isEmpty {
			return
		}

		validSet.subtract(set)
		pendingSet.subtract(set)

		makeNextRequest()
	}

	/// Update internal state in response to a mutation.
	///
	/// This method must be invoked on every content change. The `range` parameter must refer to the range that **was** changed. Consider the example text `"abc"`.
	///
	/// Inserting a "d" at the end:
	///
	///     range = NSRange(3..<3)
	///     delta = 1
	///
	/// Deleting the middle "b":
	///
	///     range = NSRange(1..<2)
	///     delta = -1
	public func contentChanged(in range: NSRange, delta: Int) {
		let limit = length - delta

		let mutation = RangeMutation(range: range, delta: delta, limit: limit)

		self.validSet = mutation.transform(set: validSet)

		if pendingSet.isEmpty {
			return
		}

		// if we have pending requests, we have to start over
		self.pendingSet.removeAll()

		makeNextRequest()
	}
}

@available(macOS 10.15, iOS 13.0, *)
extension RangeStateValidator {
	private var length: Int {
		configuration.lengthProvider()
	}

	private var fullSet: IndexSet {
		IndexSet(integersIn: 0..<length)
	}

	private var invalidSet: IndexSet {
		fullSet.subtracting(validSet)
	}

	private var effectiveWorkingRange: NSRange {
		workingRange ?? NSRange(0..<length)
	}

	private var workingSet: IndexSet {
		IndexSet(integersIn: effectiveWorkingRange)
	}

	private func workingRangeDidChange() {
		let set = invalidSet.intersection(workingSet)

		invalidate(.set(set))
	}
}

@available(macOS 10.15, iOS 13.0, *)
extension RangeStateValidator {
	/// Computes the next contiguous invalid range
	private func nextNeededRange() -> NSRange? {
		let workingRange = effectiveWorkingRange

		let lookBehindLength = prefetchLength
		let lookAheadLength = prefetchLength

		// expand the working range by the maximum possible request length
		let expandedStart = max(workingRange.location - lookBehindLength, 0)
		let expandedEnd = min(workingRange.max + lookAheadLength, length)

		let expandedSet = IndexSet(integersIn: NSRange(expandedStart..<expandedEnd))

		// determine what parts of that set are actually invalid
		let expandedInvalidSet = invalidSet.intersection(expandedSet)

		// here's a trick. Create a set with a single range, and then remove
		// any pending ranges from it. The result can be used to determine the longest
		// ranges that do not overlap pending.
		let spanSet = expandedInvalidSet
			.limitSpanningRange
			.map({ IndexSet(integersIn: $0) }) ?? IndexSet()

		let candidateSet = spanSet.subtracting(pendingSet)

		// We want to prioritize the invalid ranges that are actually visible
		let hasWorkingInvalidRanges = workingSet.intersection(invalidSet).isEmpty == false

		// now get back the first range, which is the longest continuous
		// range that includes invalid regions
		let range = candidateSet.nsRangeView.first { range in
			guard hasWorkingInvalidRanges else { return true }

			return range.max > workingRange.location
		}

		return range
	}

	private func makeNextRequest() {
		guard let range = nextNeededRange() else { return }

		self.pendingSet.insert(range: range)

		// if we have an outstanding async operation going, force this to be async too
		if pendingTask != nil {
			validateRangeAsync(range)
			return
		}

		switch configuration.syncValidateRange(range) {
		case let .success(validatedRange):
			handleValidatedRange(validatedRange)
		case .asyncRequired:
			validateRangeAsync(range)
		}
	}

	private func validateRangeAsync(_ range: NSRange) {
		pendingCount += 1

		let currentTask = pendingTask
		let currentCount = pendingCount

		self.pendingTask = Task { [weak self] in
			guard let self = self else { return }

			await currentTask?.value

			let validatedRange = await self.configuration.validateRange(range)

			self.handleValidatedRange(validatedRange)

			// if another task has not yet been scheduled, we can safely clear any pending task
			if currentCount == self.pendingCount {
				self.pendingTask = nil
			}
		}
	}

	private func handleValidatedRange(_ range: NSRange) {
		pendingSet.remove(integersIn: range)
		validSet.insert(range: range)
	}
}
