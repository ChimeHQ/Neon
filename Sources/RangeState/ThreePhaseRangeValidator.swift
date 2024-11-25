import Foundation

import Rearrange

@MainActor
public final class ThreePhaseRangeValidator<Content: VersionedContent> {
	public typealias PrimaryValidator = SinglePhaseRangeValidator<Content>
	private typealias InternalValidator = RangeValidator<Content>

	public typealias ValidationHandler = (NSRange) -> Void

	public typealias ContentRange = RangeValidator<Content>.ContentRange
	public typealias Provider = PrimaryValidator.Provider
	public typealias FallbackHandler = (NSRange) -> Void
	public typealias SecondaryValidationProvider = (ContentRange) async -> Validation

	private typealias Sequence = AsyncStream<ContentRange>

	public struct Configuration {
		public let versionedContent: Content
		public let provider: Provider
		public let fallbackHandler: FallbackHandler?
		public let secondaryProvider: SecondaryValidationProvider?
		public let secondaryValidationDelay: TimeInterval
		public let prioritySetProvider: PrimaryValidator.PrioritySetProvider?

		public init(
			versionedContent: Content,
			provider: Provider,
			fallbackHandler: FallbackHandler? = nil,
			secondaryProvider: SecondaryValidationProvider? = nil,
			secondaryValidationDelay: TimeInterval = 2.0,
			prioritySetProvider: PrimaryValidator.PrioritySetProvider?
		) {
			self.versionedContent = versionedContent
			self.provider = provider
			self.fallbackHandler = fallbackHandler
			self.secondaryProvider = secondaryProvider
			self.secondaryValidationDelay = secondaryValidationDelay
			self.prioritySetProvider = prioritySetProvider
		}
	}

	private let primaryValidator: PrimaryValidator
	private let fallbackValidator: InternalValidator
	private let secondaryValidator: InternalValidator?
	private var task: Task<Void, Error>?

	public let configuration: Configuration

	public init(configuration: Configuration) {
		self.configuration = configuration
		self.primaryValidator = PrimaryValidator(
			configuration: .init(
				versionedContent: configuration.versionedContent,
				provider: configuration.provider,
				prioritySetProvider: configuration.prioritySetProvider
			)
		)

		self.fallbackValidator = InternalValidator(content: configuration.versionedContent)
		self.secondaryValidator = InternalValidator(content: configuration.versionedContent)

		primaryValidator.validationHandler = { [unowned self] in self.handlePrimaryValidation(of: $0) }
	}

	private var version: Content.Version {
		configuration.versionedContent.currentVersion
	}

	/// Manually mark a region as invalid.
	public func invalidate(_ target: RangeTarget) {
		primaryValidator.invalidate(target)
		fallbackValidator.invalidate(target)
		secondaryValidator?.invalidate(target)
	}

	public func validate(_ target: RangeTarget, prioritizing set: IndexSet? = nil) {
		let action = primaryValidator.validate(target, prioritizing: set)

		switch action {
		case .none:
			scheduleSecondaryValidation(of: target, prioritizing: set)
		case let .needed(contentRange):
			fallbackValidate(contentRange.value, prioritizing: set)
		}
	}

	private func fallbackValidate(_ targetRange: NSRange, prioritizing set: IndexSet?) -> Void {
		guard let provider = configuration.fallbackHandler else { return }

		let action = fallbackValidator.beginValidation(of: .range(targetRange), prioritizing: set)

		switch action {
		case .none:
			return
		case let .needed(contentRange):
			provider(contentRange.value)

			fallbackValidator.completeValidation(of: contentRange, with: .success(contentRange.value))
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
		fallbackValidator.contentChanged(in: range, delta: delta)
		secondaryValidator?.contentChanged(in: range, delta: delta)

		task?.cancel()
	}
}

extension ThreePhaseRangeValidator {
	private func handlePrimaryValidation(of range: NSRange) {
		let target = RangeTarget.range(range)
		let prioritySet = configuration.prioritySetProvider?() ?? IndexSet(range)

		fallbackValidator.invalidate(target)
		secondaryValidator?.invalidate(target)

		scheduleSecondaryValidation(of: target, prioritizing: prioritySet)
	}

	private func scheduleSecondaryValidation(of target: RangeTarget, prioritizing set: IndexSet?) {
		if configuration.secondaryProvider == nil || secondaryValidator == nil {
			return
		}

		task?.cancel()

		let requestingVersion = configuration.versionedContent.currentVersion
		let delay = max(UInt64(configuration.secondaryValidationDelay * 1_000_000_000), 0)

		self.task = Task {
			try await Task.sleep(nanoseconds: delay)

			await secondaryValidate(target: target, requestingVersion: requestingVersion, prioritizing: set)
		}
	}

	private func secondaryValidate(target: RangeTarget, requestingVersion: Content.Version, prioritizing set: IndexSet?) async {
		guard
			requestingVersion == self.version,
			let validator = secondaryValidator,
			let provider = configuration.secondaryProvider
		else {
			return
		}

		let action = validator.beginValidation(of: target, prioritizing: set)

		switch action {
		case .none:
			return
		case let .needed(contentRange):
			let validation = await provider(contentRange)

			validator.completeValidation(of: contentRange, with: validation)
		}
	}
}
