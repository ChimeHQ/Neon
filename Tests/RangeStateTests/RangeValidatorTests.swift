import XCTest

import RangeState

final class RangeValidatorTests: XCTestCase {
	typealias StringValidator = RangeValidator<StringContent>

	struct StringContent: VersionedContent {
		private var version: Int = 0
		var string: String {
			didSet { version += 1 }
		}

		init(string: String) {
			self.string = string
		}

		var currentVersion: Int { version }

		func length(for version: Version) -> Int? {
			guard version == currentVersion else { return nil }
				
			return string.utf16.count
		}
	}

	@MainActor
	func testContentChange() {
		var content = StringContent(string: "abc")
		let provider = StringValidator.ValidationProvider(
			syncValue: {
				return .success($0.value)
			},
			asyncValue: { contentRange, _ in
				return .success(contentRange.value)
			})

		let validator = StringValidator(
			configuration: .init(
				versionedContent: content,
				validationProvider: provider
			)
		)

		content.string = "abcd"

		validator.contentChanged(in: NSRange(3..<3), delta: 1)
	}
}
