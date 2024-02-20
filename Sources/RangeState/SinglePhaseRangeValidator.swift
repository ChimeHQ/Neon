import Foundation

import ConcurrencyCompatibility
import Rearrange

@MainActor
public final class SinglePhaseRangeValidator<Content: VersionedContent> {

	public typealias ContentRange = RangeValidator<Content>.ContentRange
	public typealias Provider = HybridValueProvider<ContentRange, Validation>
	public typealias PrioritySetProvider = () -> IndexSet

	private typealias Sequence = AsyncStream<ContentRange>

	public struct Configuration {
		public let versionedContent: Content
		public let provider: Provider
		public let prioritySetProvider: PrioritySetProvider?

		public init(
			versionedContent: Content,
			provider: Provider,
			prioritySetProvider: PrioritySetProvider? = nil
		) {
			self.versionedContent = versionedContent
			self.provider = provider
			self.prioritySetProvider = prioritySetProvider
		}
	}

	private let continuation: Sequence.Continuation
	private let primaryValidator: RangeValidator<Content>

	public let configuration: Configuration
	public var validationHandler: (NSRange) -> Void = { _ in }

	public init(configuration: Configuration) {
		self.configuration = configuration
		self.primaryValidator = RangeValidator<Content>(content: configuration.versionedContent)

		let (stream, continuation) = Sequence.makeStream()

		self.continuation = continuation

		Task { [weak self] in
			for await versionedRange in stream {
				await self?.validateRangeAsync(versionedRange)
			}
		}
	}

	deinit {
		continuation.finish()
	}

	private var version: Content.Version {
		configuration.versionedContent.currentVersion
	}

	/// Manually mark a region as invalid.
	public func invalidate(_ target: RangeTarget) {
		primaryValidator.invalidate(target)
	}

	@discardableResult
	public func validate(_ target: RangeTarget, prioritizing set: IndexSet? = nil) -> RangeValidator<Content>.Action {
		// capture this first, because we're about to start one
		let outstanding = primaryValidator.hasOutstandingValidations

		let action = primaryValidator.beginValidation(of: target, prioritizing: set)

		switch action {
		case .none:
			return .none
		case let .needed(contentRange):
			// if we have an outstanding async operation going, force this to be async too
			if outstanding {
				enqueueValidation(for: contentRange)
				return action
			}

			guard let validation = configuration.provider.sync(contentRange) else {
				enqueueValidation(for: contentRange)

				return action
			}

			completePrimaryValidation(of: contentRange, with: validation)

			return .none
		}
	}

	private func completePrimaryValidation(of contentRange: ContentRange, with validation: Validation) {
		primaryValidator.completeValidation(of: contentRange, with: validation)

		switch validation {
		case .stale:
			DispatchQueue.main.backport.asyncUnsafe {
				let prioritySet = self.configuration.prioritySetProvider?() ?? IndexSet(contentRange.value)

				self.validate(.set(prioritySet))
			}
		case let .success(range):
			validationHandler(range)
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
		primaryValidator.contentChanged(in: range, delta: delta)
	}

	private func enqueueValidation(for contentRange: ContentRange) {
		continuation.yield(contentRange)
	}

	private func validateRangeAsync(_ contentRange: ContentRange) async {
		let validation = await self.configuration.provider.mainActorAsync(contentRange)

		completePrimaryValidation(of: contentRange, with: validation)
	}
}
