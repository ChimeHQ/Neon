import Foundation

import RangeState

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

public typealias TextStorageEditActions = NSTextStorageEditActions
public typealias TextView = NSTextView
#elseif canImport(UIKit)
import UIKit

public typealias TextStorageEditActions = NSTextStorage.EditActions
public typealias TextView = UITextView
#endif

#if canImport(AppKit) || canImport(UIKit)
extension NSTextStorage: VersionedContent {
	public var currentVersion: Int {
		hashValue
	}

	public func length(for version: Int) -> Int? {
		guard version == currentVersion else { return nil }

		return length
	}
}

@available(macOS 12.0, iOS 16.0, tvOS 16.0, *)
extension NSTextContentManager: VersionedContent {
	public var currentVersion: Int {
		hashValue
	}

	public func length(for version: Int) -> Int? {
		guard version == currentVersion else { return nil }

		return NSRange(documentRange, provider: self).length
	}
}
#endif
