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
				secondaryValidationDelay: 3.0
			),
			isolation: MainActor.shared
		)
	}

	public func didChangeContent(in range: NSRange, delta: Int) {
		validator.contentChanged(in: range, delta: delta)
	}

	public func invalidate(_ target: RangeTarget) {
		validator.invalidate(target)
	}

	public func validate(_ target: RangeTarget = .all) {
		validator.validate(target, isolation: MainActor.shared)
	}

	public var name: String? {
		get { validator.name }
		set { validator.name = newValue }
	}
}
