import Foundation

import Rearrange

public enum Validation: Sendable, Hashable {
	case stale
	case success(NSRange)
}

/// A type that manages the validation of range-based content.
public final class RangeValidator<Content: VersionedContent> {
	public typealias ContentRange = VersionedRange<Content.Version>
	public typealias ValidationProvider = HybridSyncAsyncValueProvider<ContentRange, Validation, Never>

	public enum Action: Sendable, Equatable {
		case none
		case needed(ContentRange)
	}

	private var validSet = IndexSet()
	// TODO: this has to be transitioned to an array with a computed set to better prevent overlapping work
	private var pendingSet = IndexSet()
	private var pendingRequests = 0

	public let content: Content

	public init(content: Content) {
		self.content = content
	}

	public var hasOutstandingValidations: Bool {
		pendingRequests > 0
	}

	private var version: Content.Version {
		content.currentVersion
	}

	/// Manually mark a region as invalid.
	public func invalidate(_ target: RangeTarget) {
		let invalidated = target.indexSet(with: length)

		if invalidated.isEmpty {
			return
		}

		validSet.subtract(invalidated)
		pendingSet.subtract(invalidated)
	}

	/// Begin a validation pass.
	///
	/// This must ultimately be paired with a matching call to `completeValidation(of:with:)`.
	public func beginValidation(of target: RangeTarget) -> Action {
		let set = target.indexSet(with: length)

		guard let neededRange = nextNeededRange(in: set) else { return .none }

		self.pendingSet.insert(range: neededRange)
		self.pendingRequests += 1

		let contentRange = ContentRange(neededRange, version: version)

		return .needed(contentRange)
	}

	/// Complete a validation pass.
	///
	/// This should only be used to end a matching call to `beginValidation(of:prioritizing:)`.
	public func completeValidation(of contentRange: ContentRange, with validation: Validation) {
		self.pendingRequests -= 1
		precondition(pendingRequests >= 0)

		guard contentRange.version == version else {
			pendingSet.removeAll()
			return
		}

		switch validation {
		case .stale:
			pendingSet.remove(integersIn: contentRange.value)
		case let .success(range):
			pendingSet.remove(integersIn: range)
			validSet.insert(range: range)
		}
	}

	public func isValid(_ target: RangeTarget) -> Bool {
		switch target {
		case .all:
			fullSet == validSet
		case let .range(range):
			validSet.contains(integersIn: range)
		case let .set(set):
			validSet.intersection(set) == set
		}
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
		let mutation = RangeMutation(range: range, delta: delta)

		self.validSet = mutation.transform(set: validSet)

		if pendingSet.isEmpty {
			return
		}

		// if we have pending requests, we have to start over
		self.pendingSet.removeAll()
	}
}

extension RangeValidator {
	private var length: Int {
		content.currentLength
	}

	private var fullSet: IndexSet {
		IndexSet(integersIn: 0..<length)
	}

	private var invalidSet: IndexSet {
		fullSet.subtracting(validSet)
	}
}

extension RangeValidator {
	/// Computes the next contiguous invalid range
	private func nextNeededRange(in set: IndexSet) -> NSRange? {
		// the candidate set is:
		// - invalid
		// - not already pending
		return invalidSet
			.intersection(set)
			.subtracting(pendingSet)
			.nsRangeView
			.first
	}
}

extension RangeValidator.Action: Hashable where Content.Version: Hashable {}
