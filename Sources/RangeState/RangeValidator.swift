import Foundation

import ConcurrencyCompatibility
import Rearrange

/// A type that manages the validation of range-based content.
///
/// > Note: If a `WorkingRangeProvider` is not provided, the validator will **only** perform validation manually via the `validate(_:)` method.
@MainActor
public final class RangeValidator<Content: VersionedContent> {
	public typealias Version = Content.Version
	public typealias ValidationHandler = (NSRange) -> Void

	public enum Validation: Sendable {
		case stale
		case success(NSRange)
	}

	public typealias ContentRange = VersionedRange<Version>
	public typealias ValidationProvider = HybridValueProvider<ContentRange, Validation>

	public typealias WorkingRangeProvider = () -> NSRange
	private typealias Sequence = AsyncStream<ContentRange>

	public struct Configuration {
		public let versionedContent: Content
		public let validationProvider: ValidationProvider
		public let workingRangeProvider: WorkingRangeProvider?

		public init(
			versionedContent: Content,
			validationProvider: ValidationProvider,
			workingRangeProvider: WorkingRangeProvider? = nil
		) {
			self.versionedContent = versionedContent
			self.validationProvider = validationProvider
			self.workingRangeProvider = workingRangeProvider
		}
	}

	private var validSet = IndexSet()
	private var pendingSet = IndexSet()
	private var pendingRequests = 0
	private var version: Content.Version
	private let continuation: Sequence.Continuation

	public let configuration: Configuration
	public var validationHandler: ValidationHandler = { _ in }

	public init(configuration: Configuration) {
		self.configuration = configuration
		self.version = configuration.versionedContent.currentVersion

		let (stream, continuation) = Sequence.makeStream()

		self.continuation = continuation

		Task {
			await self.beginMonitoring(stream)
		}
	}

	deinit {
		continuation.finish()
	}

	private nonisolated func beginMonitoring(_ stream: Sequence) async {
		for await versionedRange in stream {
			await self.validateRangeAsync(versionedRange)
		}
	}

	/// Manually mark a region as invalid.
	public func invalidate(_ target: RangeTarget) {
		let invalidated = target.indexSet(with: length)

		if invalidated.isEmpty {
			return
		}

		validSet.subtract(invalidated)
		pendingSet.subtract(invalidated)

		self.version = configuration.versionedContent.currentVersion

		makeNextWorkingSetRequest()
	}

	/// Compute the sections of the new working range that need validation.
	public func workingRangeChanged() {
		guard let workingSet else { return }

		let set = invalidSet.intersection(workingSet)

		invalidate(.set(set))
	}

	public func validate(_ target: RangeTarget) {
		let set = target.indexSet(with: length)

		makeNextRequest(in: set)
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

		self.version = configuration.versionedContent.currentVersion

		if pendingSet.isEmpty {
			return
		}

		// if we have pending requests, we have to start over
		self.pendingSet.removeAll()

		makeNextWorkingSetRequest()
	}
}

extension RangeValidator {
	private var length: Int {
		configuration.versionedContent.currentLength
	}

	private var fullSet: IndexSet {
		IndexSet(integersIn: 0..<length)
	}

	private var workingRange: NSRange? {
		configuration.workingRangeProvider?()
	}

	private var workingSet: IndexSet? {
		workingRange.map { IndexSet(integersIn: $0) }
	}

	private var invalidSet: IndexSet {
		fullSet.subtracting(validSet)
	}
}

extension RangeValidator {
	/// Computes the next contiguous invalid range
	private func nextNeededRange(in set: IndexSet) -> NSRange? {
		// determine what parts of the target set are actually invalid
		let workingInvalidSet = invalidSet.intersection(set)

		// here's a trick. Create a set with a single range, and then remove
		// any pending ranges from it. The result can be used to determine the longest
		// ranges that do not overlap pending.
		let spanSet = workingInvalidSet
			.limitSpanningRange
			.map({ IndexSet(integersIn: $0) }) ?? IndexSet()

		let candidateSet = spanSet.subtracting(pendingSet)

		// We want to prioritize the invalid ranges that are actually in the target set
		let hasInvalidRanges = set.intersection(invalidSet).isEmpty == false
		let limit = workingRange?.location ?? 0

		// now get back the first range which is the longest continuous
		// range that includes invalid regions
		let range = candidateSet.nsRangeView.first { range in
			guard hasInvalidRanges else { return true }

			return range.max > limit
		}

		return range
	}

	private func makeNextWorkingSetRequest() {
		guard let workingSet else { return }

		makeNextRequest(in: workingSet)
	}

	private func makeNextRequest(in set: IndexSet) {
		guard let range = nextNeededRange(in: set) else { return }

		self.pendingSet.insert(range: range)

		let versionedRange = ContentRange(range, version: version)

		// if we have an outstanding async operation going, force this to be async too
		if pendingRequests > 0 {
			enqueueValidation(for: versionedRange)
			return
		}

		switch configuration.validationProvider.sync(versionedRange) {
		case let .success(validatedRange):
			handleValidatedRange(validatedRange)
		case .stale:
			handleStaleResults()
		case nil:
			enqueueValidation(for: versionedRange)
		}
	}

	private func enqueueValidation(for contentRange: ContentRange) {
		self.pendingRequests += 1
		continuation.yield(contentRange)
	}

	private func validateRangeAsync(_ contentRange: ContentRange) async {
		self.pendingRequests -= 1
		precondition(pendingRequests >= 0)

		let result = await self.configuration.validationProvider.mainActorAsync(contentRange)

		switch result {
		case .stale:
			handleStaleResults()
		case let .success(range):
			// here we must re-validate that the version has remained stable after the await
			guard contentRange.version == version else {
				handleStaleResults()
				break
			}

			handleValidatedRange(range)
		}
	}

	private func handleStaleResults() {
		print("RangeStateValidation provider returned stale results")

		pendingSet.removeAll()

		DispatchQueue.main.backport.asyncUnsafe {
			self.makeNextWorkingSetRequest()
		}
	}

	private func handleValidatedRange(_ range: NSRange) {
		pendingSet.remove(integersIn: range)
		validSet.insert(range: range)

		validationHandler(range)
	}
}
