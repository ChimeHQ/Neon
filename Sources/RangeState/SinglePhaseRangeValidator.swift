import Foundation

import Rearrange

public final class SinglePhaseRangeValidator<Content: VersionedContent> {
	public typealias ContentRange = RangeValidator<Content>.ContentRange
	public typealias Provider = HybridSyncAsyncValueProvider<ContentRange, Validation, Never>
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

    public init(configuration: Configuration, isolation: isolated (any Actor) = MainActor.shared) {
		self.configuration = configuration
		self.primaryValidator = RangeValidator<Content>(content: configuration.versionedContent)

		let (stream, continuation) = Sequence.makeStream()

		self.continuation = continuation

		Task { [weak self] in
            _ = isolation
            
			for await versionedRange in stream {
                await self?.validateRangeAsync(versionedRange, isolation: isolation)
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
    public func validate(
        _ target: RangeTarget,
        prioritizing set: IndexSet? = nil,
        isolation: isolated (any Actor) = MainActor.shared
    ) -> RangeValidator<Content>.Action {
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

            completePrimaryValidation(of: contentRange, with: validation, isolation: isolation)

			return .none
		}
	}

	private func completePrimaryValidation(of contentRange: ContentRange, with validation: Validation, isolation: isolated (any Actor)) {
		primaryValidator.completeValidation(of: contentRange, with: validation)

		switch validation {
		case .stale:
            Task {
                _ = isolation
                
                if contentRange.version == self.version {
                    print("version unchanged after stale results, stopping validation")
                    return
                }
                
                let prioritySet = self.configuration.prioritySetProvider?() ?? IndexSet(contentRange.value)

                self.validate(.set(prioritySet), isolation: isolation)

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

	private func validateRangeAsync(_ contentRange: ContentRange, isolation: isolated (any Actor)) async {
		let validation = await self.configuration.provider.async(contentRange)

        completePrimaryValidation(of: contentRange, with: validation, isolation: isolation)
	}
}
