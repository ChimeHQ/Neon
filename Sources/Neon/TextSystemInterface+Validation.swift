import Foundation

import RangeState

extension TextSystemInterface {
	typealias Provider = ThreePhaseRangeValidator<Content>.Provider
	typealias ContentRange = ThreePhaseRangeValidator<Content>.ContentRange

	@MainActor
	func validation(for application: TokenApplication, in contentRange: ContentRange) -> Validation {
		let effectiveRange = application.range ?? contentRange.value

		applyStyles(for: application)

		return .success(effectiveRange)
	}

	@MainActor
	func asyncValidate(
		_ contentRange: ContentRange,
		provider: @MainActor (NSRange) async -> TokenApplication
	) async -> Validation {
		guard contentRange.version == content.currentVersion else { return .stale }

		// https://github.com/apple/swift/pull/71143
		let application = await provider(contentRange.value)

		// second check after the awit
		guard contentRange.version == content.currentVersion else { return .stale }

		return validation(for: application, in: contentRange)
	}

	@MainActor
	func validationProvider(with provider: TokenProvider) -> Provider {
		.init(
			syncValue: { contentRange in
				guard contentRange.version == self.content.currentVersion else { return .stale }

				guard let application = provider.sync(contentRange.value) else {
					return nil
				}

				return validation(for: application, in: contentRange)
			},
			mainActorAsyncValue: { contentRange in
				await asyncValidate(
					contentRange,
					provider: { await provider.async(isolation: MainActor.shared, $0) }
				)
			}
		)
	}
}
extension TextSystemInterface {
	typealias Styler = ThreePhaseTextSystemStyler<Self>
	typealias FallbackHandler = ThreePhaseRangeValidator<Self.Content>.FallbackHandler
	typealias SecondaryValidationProvider = ThreePhaseRangeValidator<Self.Content>.SecondaryValidationProvider

	@MainActor
	func validatorFallbackHandler(
		with provider: @escaping Styler.FallbackTokenProvider
	) -> FallbackHandler {
		{ range in
			let application = provider(range)

			applyStyles(for: application)
		}
	}

	@MainActor
	func validatorSecondaryHandler(
		with provider: @escaping Styler.SecondaryValidationProvider
	) -> SecondaryValidationProvider {
		{ await asyncValidate($0, provider: provider) }
	}
}
