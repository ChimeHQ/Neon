import Foundation

import RangeState

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit

public typealias TextStorageEditActions = NSTextStorageEditActions
public typealias TextView = NSTextView
#elseif os(iOS) || os(iOS) || os(tvOS) || os(visionOS)
import UIKit

public typealias TextStorageEditActions = NSTextStorage.EditActions
public typealias TextView = UITextView
#endif

#if os(macOS) || os(iOS) || os(iOS) || os(tvOS) || os(visionOS)
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
