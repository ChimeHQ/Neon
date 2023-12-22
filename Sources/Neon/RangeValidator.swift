import Foundation

import Rearrange

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
@MainActor
public final class RangeValidator<Version: Equatable & Sendable> {
    public typealias ContentRange = VersionedRange<Version>
    public typealias ValidatorProvider = HybridValueProvider<ContentRange, NSRange?>
	public typealias WorkingRangeProvider = () -> NSRange
    private typealias Sequence = AsyncStream<ContentRange>

	public struct Configuration {
		public let versionedContent: VersionedContent<Version>
        public let validatorProvider: ValidatorProvider
		public let workingRangeProvider: WorkingRangeProvider?

		public init(
			versionedContent: VersionedContent<Version>,
			validatorProvider: ValidatorProvider,
			workingRangeProvider: WorkingRangeProvider? = nil
		) {
			self.versionedContent = versionedContent
			self.validatorProvider = validatorProvider
			self.workingRangeProvider = workingRangeProvider
		}
	}

	private var validSet = IndexSet()
	private var pendingSet = IndexSet()
    private var version: Version
    private var oldestPendingRequestVersion: Version
    private let continuation: Sequence.Continuation
	
    public let configuration: Configuration

	public init(configuration: Configuration) {
		self.configuration = configuration
		self.version = configuration.versionedContent.version()
        self.oldestPendingRequestVersion = version

        let (stream, continuation) = Sequence.makeStream()

        self.continuation = continuation

        Task {
            for await versionedRange in stream {
                await validateRangeAsync(versionedRange)
            }
        }
	}

    deinit {
        continuation.finish()
    }

	/// Manually mark a region as invalid.
	public func invalidate(_ invalidated: IndexSet) {
		if invalidated.isEmpty {
			return
		}

		validSet.subtract(invalidated)
		pendingSet.subtract(invalidated)

		makeNextRequest()
	}

	public func invalidate(_ range: NSRange) {
		invalidate(IndexSet(integersIn: range))
	}

	public func invalidate() {
		invalidate(fullSet)
	}

	/// Compute the sections of the new working range that need validation.
	public func workingRangeChanged() {
		let workingSet = IndexSet(integersIn: workingRange)
		let set = invalidSet.intersection(workingSet)

		invalidate(set)
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

		self.version = configuration.versionedContent.version()

		if pendingSet.isEmpty {
			return
		}

		// if we have pending requests, we have to start over
		self.pendingSet.removeAll()

		makeNextRequest()
	}
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension RangeValidator {
	private var length: Int {
		configuration.versionedContent.currentLength
	}

	private var fullSet: IndexSet {
		IndexSet(integersIn: 0..<length)
	}

	private var workingRange: NSRange {
		configuration.workingRangeProvider?() ?? NSRange(0..<length)
	}

	private var invalidSet: IndexSet {
		fullSet.subtracting(validSet)
	}
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension RangeValidator {
	/// Computes the next contiguous invalid range
	private func nextNeededRange() -> NSRange? {
		let workingSet = IndexSet(integersIn: workingRange)

		// determine what parts of the working set are actually invalid
		let workingInvalidSet = invalidSet.intersection(workingSet)

		// here's a trick. Create a set with a single range, and then remove
		// any pending ranges from it. The result can be used to determine the longest
		// ranges that do not overlap pending.
		let spanSet = workingInvalidSet
			.limitSpanningRange
			.map({ IndexSet(integersIn: $0) }) ?? IndexSet()

		let candidateSet = spanSet.subtracting(pendingSet)

		// We want to prioritize the invalid ranges that are actually in the working set
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

        let versionedRange = ContentRange(range, version: version)

		// if we have an outstanding async operation going, force this to be async too
        if version != oldestPendingRequestVersion {
            enqueueValidation(for: versionedRange)
			return
		}

		switch configuration.validatorProvider.sync(versionedRange) {
		case let validatedRange??:
            handleValidatedRange(validatedRange)
		case nil?:
			handleStaleResults()
		case nil:
            enqueueValidation(for: versionedRange)
		}
	}

	private func enqueueValidation(for contentRange: ContentRange) {
        continuation.yield(contentRange)
	}

    private func validateRangeAsync(_ contentRange: ContentRange) async {
		let range = await self.configuration.validatorProvider.async(contentRange)

		// here we must re-validate that the version has remained stable after the await
		if let range, contentRange.version == version {
			handleValidatedRange(range)
		} else {
			handleStaleResults()
		}

		self.oldestPendingRequestVersion = contentRange.version
    }

    private func handleStaleResults() {
        print("RangeStateValidation provider returned stale results")

        pendingSet.removeAll()

        makeNextRequest()
    }

	private func handleValidatedRange(_ range: NSRange) {
		pendingSet.remove(integersIn: range)
		validSet.insert(range: range)
	}
}
