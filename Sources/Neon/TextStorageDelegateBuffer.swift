import Foundation

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit

typealias TextStorageEditActions = NSTextStorageEditActions
#elseif os(iOS) || os(visionOS)
import UIKit

typealias TextStorageEditActions = NSTextStorage.EditActions
#endif

import RangeState

#if os(macOS) || os(iOS) || os(visionOS)
final class TextStorageDelegate: NSObject {
	typealias ChangeHandler = (NSRange, Int) -> Void

	public var storage: NSTextStorage? {
		didSet {
			oldValue?.delegate = nil
			storage?.delegate = self
		}
	}
	public var willChangeContent: ChangeHandler = { _, _ in }
	public var didChangeContent: ChangeHandler = { _, _ in }
}

extension TextStorageDelegate: NSTextStorageDelegate {
	public func textStorage(
		_ textStorage: NSTextStorage,
		willProcessEditing editedMask: TextStorageEditActions,
		range editedRange: NSRange,
		changeInLength delta: Int
	) {
		guard editedMask.contains(.editedCharacters) else { return }

		willChangeContent(editedRange, delta)
	}

	public func textStorage(
		_ textStorage: NSTextStorage,
		didProcessEditing editedMask: TextStorageEditActions,
		range editedRange: NSRange,
		changeInLength delta: Int
	) {
		// it's important to filter these, as attribute changes can be caused by styling. This will result in an infinite loop.
		guard editedMask.contains(.editedCharacters) else { return }

		didChangeContent(editedRange, delta)
	}
}
#endif
