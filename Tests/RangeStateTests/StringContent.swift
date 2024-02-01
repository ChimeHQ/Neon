import Foundation

import RangeState

final class StringContent: VersionedContent {
	private var version: Int = 0
	
	var string: String {
		didSet { version += 1 }
	}

	init(string: String) {
		self.string = string
	}

	var currentVersion: Int { version }

	func length(for version: Int) -> Int? {
		guard version == currentVersion else { return nil }

		return string.utf16.count
	}
}
