import XCTest
import Rearrange
import SwiftTreeSitter
@testable import TreeSitterClient
import TestTreeSitterSwift

final class TreeSitterClientTests: XCTestCase {
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

extension TreeSitterClientTests {
	@available(macOS 10.15, iOS 13.0, watchOS 6.0.0, tvOS 13.0.0, *)
	func testBasicParse() async throws {
		let language = Language(language: tree_sitter_swift())

		let client = try TreeSitterClient(language: language)

let content = """
func main() { print("hello" }
"""
		await MainActor.run {
			client.didChangeContent(to: content, in: .zero, delta: content.utf16.count, limit: 0)
		}

		let tree = try await client.currentTree()

		XCTAssertNotNil(tree.rootNode)
	}
}
