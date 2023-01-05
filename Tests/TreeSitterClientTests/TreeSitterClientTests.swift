import XCTest
import Rearrange
import SwiftTreeSitter
@testable import TreeSitterClient

final class NeonTests: XCTestCase {
    func testInsertAffectedRange() {
        let mutation = RangeMutation(range: .zero, delta: 10, limit: 10)
        let inputEdit = InputEdit(startByte: 0,
                                  oldEndByte: 0,
                                  newEndByte: 20,
                                  startPoint: Point(row: 0, column: 0),
                                  oldEndPoint: Point(row: 0, column: 0),
                                  newEndPoint: Point(row: 0, column: 10))
        let edit = TreeSitterClient.ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: 10)

        XCTAssertEqual(edit.affectedRange, NSRange(0..<10))
    }

    func testInsertClampedAffectedRange() {
        let mutation = RangeMutation(range: .zero, delta: 10, limit: 10)
        let inputEdit = InputEdit(startByte: 0,
                                  oldEndByte: 0,
                                  newEndByte: 20,
                                  startPoint: Point(row: 0, column: 0),
                                  oldEndPoint: Point(row: 0, column: 0),
                                  newEndPoint: Point(row: 0, column: 10))
        let edit = TreeSitterClient.ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: 5)

        XCTAssertEqual(edit.affectedRange, NSRange(0..<5))
    }

    func testDeleteAffectedRange() {
        let mutation = RangeMutation(range: NSRange(0..<10), delta: -10)
        let inputEdit = InputEdit(startByte: 0,
                                  oldEndByte: 20,
                                  newEndByte: 0,
                                  startPoint: Point(row: 0, column: 0),
                                  oldEndPoint: Point(row: 0, column: 10),
                                  newEndPoint: Point(row: 0, column: 0))
        let edit = TreeSitterClient.ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: 0)

        XCTAssertEqual(edit.affectedRange, NSRange(0..<0))
    }

	func testAffectedRangeWithInsertAtEnd() {
		let mutation = RangeMutation(range: NSRange(0..<10), delta: -10)
		let inputEdit = InputEdit(startByte: 0,
								  oldEndByte: 20,
								  newEndByte: 0,
								  startPoint: Point(row: 0, column: 0),
								  oldEndPoint: Point(row: 0, column: 10),
								  newEndPoint: Point(row: 0, column: 0))
		let edit = TreeSitterClient.ContentEdit(rangeMutation: mutation, inputEdit: inputEdit, limit: 0)

		XCTAssertEqual(edit.affectedRange, NSRange(0..<0))
	}
}
