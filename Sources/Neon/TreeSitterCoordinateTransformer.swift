import Foundation
import Rearrange
import SwiftTreeSitter

public struct TreeSitterCoordinateTransformer {
    public var locationToPoint: (Int) -> Point?
    public var locationToByteOffset: (Int) -> UInt32?
    public var byteOffsetToLocation: (UInt32) -> Int?

    public init(locationToPoint: @escaping (Int) -> Point?) {
        self.locationToPoint = locationToPoint
        self.locationToByteOffset = { UInt32($0 * 2) }
        self.byteOffsetToLocation = { Int($0 / 2) }
    }
}

public extension TreeSitterCoordinateTransformer {
    func computeRange(from byteRange: Range<UInt32>) -> NSRange? {
        guard
            let start = byteOffsetToLocation(byteRange.lowerBound),
            let end = byteOffsetToLocation(byteRange.upperBound)
        else {
            return nil
        }

        return NSRange(start..<end)
    }

    func computeByteRange(from range: NSRange) -> Range<UInt32>? {
        guard
            let start = locationToByteOffset(range.lowerBound),
            let end = locationToByteOffset(range.upperBound)
        else {
            return nil
        }

        return start..<end
    }
}

extension TreeSitterCoordinateTransformer {
    func inputEdit(for range: NSRange, delta: Int, oldEndPoint: Point) -> InputEdit? {
        let startLocation = range.location
        let newEndLocation = range.max + delta

        if newEndLocation < 0 {
            assertionFailure("invalid range/delta")
            return nil
        }

        guard
            let startByte = locationToByteOffset(range.location),
            let oldEndByte = locationToByteOffset(range.max),
            let newEndByte = locationToByteOffset(newEndLocation),
            let startPoint = locationToPoint(startLocation),
            let newEndPoint = locationToPoint(newEndLocation)
        else {
            return nil
        }

        return InputEdit(startByte: startByte,
                         oldEndByte: oldEndByte,
                         newEndByte: newEndByte,
                         startPoint: startPoint,
                         oldEndPoint: oldEndPoint,
                         newEndPoint: newEndPoint)
    }
}
