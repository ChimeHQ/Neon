import Foundation

import RangeState

public protocol TextSystemInterface {
    associatedtype Content: VersionedContent

    @MainActor
    func applyStyles(for application: TokenApplication)

    @MainActor
    var visibleRange: NSRange { get }

    @MainActor
    var content: Content { get }
}

public typealias TokenAttributeProvider = (Token) -> [NSAttributedString.Key: Any]

