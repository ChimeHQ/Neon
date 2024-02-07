import Foundation

import RangeState

@MainActor
public final class ThreePhaseTextSystemStyler<Interface: TextSystemInterface> {
	public typealias FallbackTokenProvider = (NSRange) -> TokenApplication
	public typealias SecondaryValidationProvider = (NSRange) async -> TokenApplication

	private let textSystem: Interface
	private let validator: ThreePhaseRangeValidator<Interface.Content>

	public init(
		textSystem: Interface,
		tokenProvider: TokenProvider,
		fallbackHandler: @escaping FallbackTokenProvider,
		secondaryValidationProvider: @escaping SecondaryValidationProvider
	) {
		self.textSystem = textSystem

		let tokenValidator = TokenSystemValidator(
			textSystem: textSystem,
			tokenProvider: tokenProvider
		)

		self.validator = ThreePhaseRangeValidator(
			configuration: .init(
				versionedContent: textSystem.content,
				provider: tokenValidator.validationProvider,
				fallbackHandler: textSystem.validatorFallbackHandler(with: fallbackHandler),
				secondaryProvider: textSystem.validatorSecondaryHandler(with: secondaryValidationProvider),
				secondaryValidationDelay: 3.0,
				priorityRangeProvider: { textSystem.visibleRange }
			)
		)
	}

	public func didChangeContent(in range: NSRange, delta: Int) {
		validator.contentChanged(in: range, delta: delta)
	}

	public func invalidate(_ target: RangeTarget) {
		validator.invalidate(target)
	}

	public func validate(_ target: RangeTarget) {
		let priorityRange = textSystem.visibleRange

		validator.validate(target, prioritizing: priorityRange)
	}

	public func validate() {
		let priorityRange = textSystem.visibleRange

		validator.validate(.range(priorityRange), prioritizing: priorityRange)
	}
}
