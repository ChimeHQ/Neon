import Foundation
import SwiftTreeSitter

extension Point {
    public typealias LocationTransformer = (Int) -> Point?
}

extension InputEdit {
    init?(range: NSRange, delta: Int, oldEndPoint: Point, transformer: Point.LocationTransformer? = nil) {
        let startLocation = range.location
        let newEndLocation = range.max + delta

        if newEndLocation < 0 {
            assertionFailure("invalid range/delta")
            return nil
        }

        let startPoint, newEndPoint: Point?
        if let transformer = transformer {
            startPoint = transformer(startLocation)
            newEndPoint = transformer(newEndLocation)
            if startPoint == nil || newEndPoint == nil {
                return nil
            }
        } else {
            startPoint = .zero
            newEndPoint = .zero
        }

        assert(startPoint != nil, "startPoint should not be nil")
        assert(newEndPoint != nil, "newEndPoint should not be nil")
        self.init(startByte: UInt32(range.location * 2),
                  oldEndByte: UInt32(range.max * 2),
                  newEndByte: UInt32(newEndLocation * 2),
                  startPoint: startPoint!,
                  oldEndPoint: oldEndPoint,
                  newEndPoint: newEndPoint!)
    }
}
