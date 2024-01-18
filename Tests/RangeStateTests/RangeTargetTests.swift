import XCTest

import RangeState

final class RangeTargetTests: XCTestCase {
	func testUnion() {
		let range = RangeTarget(NSRange(0..<10))
		let set = RangeTarget(IndexSet(integersIn: 10..<20))

		XCTAssertEqual(RangeTarget.all.union(.all), .all)
		XCTAssertEqual(RangeTarget.all.union(range), .all)
		XCTAssertEqual(RangeTarget.all.union(set), .all)
		XCTAssertEqual(range.union(.all), .all)
		XCTAssertEqual(set.union(.all), .all)

		XCTAssertEqual(range.union(set), .set(IndexSet(integersIn: 0..<20)))
		XCTAssertEqual(set.union(range), .set(IndexSet(integersIn: 0..<20)))
	}
}
