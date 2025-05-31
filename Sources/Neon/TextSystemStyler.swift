import Foundation

import RangeState

/// Manages style state for a `TextSystemInterface`.
///
/// This is the main component that coordinates the styling and invalidation of text. It interfaces with the text system via `TextSystemInterface`. Actual token information is provided from a `TokenProvider`.
///
/// The `TextSystemInterface` is what to update, but it is up to you to tell it when that updating is needed. This is done via the `invalidate(_:)` call, as well as `validate(_:)`. It will be also be done automatically when the content changes.
///
/// > Note: A `TextSystemStyler` must be informed of all text content changes made using `didChangeContent(in:, delta:)`.
@MainActor
@preconcurrency
public final class TextSystemStyler<Interface: TextSystemInterface> {
	private let textSystem: Interface
	private let tokenProvider: TokenProvider
	private let validator: SinglePhaseRangeValidator<Interface.Content>

	public init(textSystem: Interface, tokenProvider: TokenProvider) {
		self.textSystem = textSystem
		self.tokenProvider = tokenProvider

		let tokenValidator = TokenSystemValidator(
			textSystem: textSystem,
			tokenProvider: tokenProvider
		)

		self.validator = SinglePhaseRangeValidator(
			configuration: .init(
				versionedContent: textSystem.content,
				provider: tokenValidator.validationProvider
			)
		)
	}

	/// Update internal state in response to an edit.
	///
	/// This method must be invoked on every text change. The `range` parameter must refer to the range of text that **was** changed.
	/// Consider the example text `"abc"`.
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
	public func didChangeContent(in range: NSRange, delta: Int) {
		validator.contentChanged(in: range, delta: delta)
	}

	public func invalidate(_ target: RangeTarget) {
		validator.invalidate(target)
	}

	public func validate(_ target: RangeTarget = .all) {
		validator.validate(target)
	}
}
