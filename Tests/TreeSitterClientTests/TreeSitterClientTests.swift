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

@available(macOS 10.15, iOS 13.0, watchOS 6.0.0, tvOS 13.0.0, *)
extension TreeSitterClientTests {
	private func makeSwiftClient() throws -> TreeSitterClient {
		let language = Language(language: tree_sitter_swift())

		return try TreeSitterClient(language: language)
	}

	func testBasicParse() async throws {
		let language = Language(language: tree_sitter_swift())

		let client = try TreeSitterClient(language: language)

let content = """
func main() { print("hello" }
"""
		await MainActor.run {
			client.didChangeContent(to: content, in: .zero, delta: content.utf16.count, limit: content.utf16.count)
		}

		let tree = try await client.currentTree()
		let root = try XCTUnwrap(tree.rootNode)

		XCTAssertEqual(root.childCount, 1)
	}

	func testRegularQuery() async throws {
		let language = Language(language: tree_sitter_swift())

		let client = try TreeSitterClient(language: language)

let content = """
func main() { print("hello" }
"""

		await MainActor.run {
			client.didChangeContent(to: content, in: .zero, delta: content.utf16.count, limit: content.utf16.count)
		}

		let queryText = """
("func" @keyword.function)
"""
		let queryData = try XCTUnwrap(queryText.data(using: .utf8))
		let query = try Query(language: language, data: queryData)

		let highlights = try await client.highlights(with: query, in: NSRange(0..<4))

		let range = NamedRange(nameComponents: ["keyword", "function"],
							   tsRange: TSRange(points: Point(row: 0, column: 0)..<Point(row: 0, column: 8),
												bytes: 0..<8))
		XCTAssertEqual(highlights, [range])
	}

	func testStaleQuery() throws {
		let language = Language(language: tree_sitter_swift())

		let client = try TreeSitterClient(language: language, synchronousLengthThreshold: 1)

let content = """
func main() { print("hello" }
"""
		
		let queryText = """
("func" @keyword.function)
"""
		let queryData = try XCTUnwrap(queryText.data(using: .utf8))
		let query = try Query(language: language, data: queryData)

		var result: Result<[NamedRange], TreeSitterClientError> = .failure(.stateInvalid)

		let queryExpectation = expectation(description: "query")

		// the goal here is to begin the query, and then submit a change so
		// the query runs on stale content. It's slightly hard to control all of the execution
		// here, but I'm fairly sure this will work without races.
		client.executeHighlightsQuery(query, in: NSRange(0..<4)) { queryResult in
			result = queryResult
			queryExpectation.fulfill()
		}

		client.didChangeContent(to: content, in: .zero, delta: content.utf16.count, limit: content.utf16.count)

		wait(for: [queryExpectation], timeout: 2.0)
		
		switch result {
		case .failure(.staleContent):
			break
		default:
			XCTFail("Should have failed: \(result)")
		}
	}
}
