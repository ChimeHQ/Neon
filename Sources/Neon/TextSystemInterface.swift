import Foundation

import RangeState

public protocol TextSystemInterface {
    associatedtype Content: VersionedContent

    @MainActor
    func applyStyles(for application: TokenApplication)

    @MainActor
    var visibleSet: IndexSet { get }

    @MainActor
    var content: Content { get }
}

/// A function that translates a semantic `Token` into styling attributes.
public typealias TokenAttributeProvider = (Token) -> [NSAttributedString.Key: Any]

