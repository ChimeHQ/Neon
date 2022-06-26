import Foundation
import SwiftTreeSitter

extension Point {
    public typealias LocationTransformer = (Int) -> Point?
}

extension InputEdit {
    init?(range: NSRange, delta: Int, oldEndPoint: Point, transformer: Point.LocationTransformer) {
        let startLocation = range.location
        let newEndLocation = range.max + delta

        if newEndLocation < 0 {
            assertionFailure("invalid range/delta")
            return nil
        }

        guard
            let startPoint = transformer(startLocation),
            let newEndPoint = transformer(newEndLocation)
        else {
            return nil
        }

        self.init(startByte: UInt32(range.location * 2),
                  oldEndByte: UInt32(range.max * 2),
                  newEndByte: UInt32(newEndLocation * 2),
                  startPoint: startPoint,
                  oldEndPoint: oldEndPoint,
                  newEndPoint: newEndPoint)
    }
}
