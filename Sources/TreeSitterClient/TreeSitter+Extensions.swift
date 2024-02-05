import Foundation

import SwiftTreeSitter
import SwiftTreeSitterLayer

extension InputEdit {
	init(range: NSRange, delta: Int, oldEndPoint: Point, transformer: Point.LocationTransformer) {
		let startLocation = range.location
		let newEndLocation = range.upperBound + delta

		assert(startLocation >= 0)
		assert(newEndLocation >= 0)

		let startPoint = transformer(startLocation) ?? .zero
		let newEndPoint = transformer(newEndLocation) ?? .zero

		self.init(
			startByte: UInt32(range.location * 2),
			oldEndByte: UInt32(range.upperBound * 2),
			newEndByte: UInt32(newEndLocation * 2),
			startPoint: startPoint,
			oldEndPoint: oldEndPoint,
			newEndPoint: newEndPoint
		)
	}
}
