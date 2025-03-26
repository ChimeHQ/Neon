import Foundation
import Testing

import RangeState

struct RangeTargetTests {
	@Test func union() {
		let range = RangeTarget(NSRange(0..<10))
		let set = RangeTarget(IndexSet(integersIn: 10..<20))

		#expect(RangeTarget.all.union(.all) == .all)
		#expect(RangeTarget.all.union(range) == .all)
		#expect(RangeTarget.all.union(set) == .all)
		#expect(range.union(.all) == .all)
		#expect(set.union(.all) == .all)

		#expect(range.union(set) == .set(IndexSet(integersIn: 0..<20)))
		#expect(set.union(range) == .set(IndexSet(integersIn: 0..<20)))
	}
	
	@Test func insertingEmptyRange() {
		let target = RangeTarget(NSRange(10..<10))
		
		#expect(target.indexSet(with: 20) == IndexSet())
	}
}
