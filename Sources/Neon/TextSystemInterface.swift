import Foundation

import RangeState

public protocol TextSystemInterface {
    associatedtype Content: VersionedContent

    @MainActor
    func applyStyles(for application: TokenApplication)

    @MainActor
    var content: Content { get }
}

/// A function that translates a semantic `Token` into styling attributes.
///
/// This is also where theming could be taken into account.
public typealias TokenAttributeProvider = (Token) -> [NSAttributedString.Key: Any]

