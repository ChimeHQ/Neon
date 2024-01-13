import Foundation

import RangeState

/// Manages style state for a `TextSystemInterface`.
///
/// This is the main component that coordinates the styling and invalidation of text. It interfaces with the text system via `TextSystemInterface`. Actual token information is provided from a `TokenProvider`.
///
/// The `TextSystemInterface` is what to update, but it is up to you to tell it when that updating is needed. This is done via the `invalidate(_:)` call, as well as `visibleContentDidChange`. It will be also be done automatically when the content changes.
///
/// > Note: A `Styler` must be informed of all text content changes made using `didChangeContent(in:, delta:)` and changes to the content visibility with `contentVisibleRectChanged(_:_`.
@MainActor
public final class TextSystemStyler<Interface: TextSystemInterface> {
	typealias Validator = RangeValidator<Interface.Content>

	public struct Configuration {
		public let tokenProvider: TokenProvider

		public init(tokenProvider: TokenProvider) {
			self.tokenProvider = tokenProvider
		}
	}

	private let configuration: Configuration
	private let textSystem: Interface
	private lazy var validator = Validator(
		configuration: .init(
			versionedContent: textSystem.content,
			validationProvider: validationProvider,
			workingRangeProvider: { [textSystem] in textSystem.visibleRange }
		)
	)

	public init(textSystem: Interface, configuration: Configuration) {
		self.textSystem = textSystem
		self.configuration = configuration
	}

	public init(textSystem: Interface, tokenProvider: TokenProvider) {
		self.textSystem = textSystem
		self.configuration = .init(tokenProvider: tokenProvider)
	}

	private var validationProvider: Validator.ValidationProvider {
		.init(
			syncValue: { [weak self] in self?.validate($0) },
			asyncValue: { [weak self] in await self?.validate($0) ?? .stale }
		)
	}

	private var currentVersion: Interface.Content.Version {
		textSystem.content.currentVersion
	}

	private func validate(_ range: Validator.ContentRange) -> Validator.Validation? {
		guard range.version == currentVersion else { return .stale }

		guard let application = configuration.tokenProvider.sync(range.value) else {
			return nil
		}

		applyStyles(for: application)

		return .success(range.value)
	}

	private func validate(_ range: Validator.ContentRange) async -> Validator.Validation {
		guard range.version == currentVersion else { return .stale }

		let application = await configuration.tokenProvider.async(range.value)

		applyStyles(for: application)

		return .success(range.value)
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

	/// Calculates any newly-visible text that is invalid
	///
	/// You should invoke this method when the visible text in your system changes.
	public func visibleContentDidChange() {
		validator.workingRangeChanged()
	}

	public func invalidate(_ target: RangeTarget) {
		validator.invalidate(target)
	}

	private func applyStyles(for application: TokenApplication) {
		textSystem.applyStyles(for: application)
	}
}
