import Foundation
import SwiftTreeSitter

struct TreeSitterParseState {
    var tree: Tree?

    init(tree: Tree? = nil) {
        self.tree = tree
    }

    func node(in range: Range<UInt32>) -> Node? {
        guard let root = tree?.rootNode else {
            return nil
        }

        return root.descendant(in: range)
    }

    func applyEdit(_ edit: InputEdit) {
        tree?.edit(edit)
    }

    func changedRanges(for otherState: TreeSitterParseState) -> [Range<UInt32>] {
        let otherTree = otherState.tree

        switch (tree, otherTree) {
        case (let t1?, let t2?):
            return t1.changedRanges(from: t2).map({ $0.bytes })
        case (nil, let t2?):
            let range = t2.rootNode?.byteRange

            return range.flatMap({ [$0] }) ?? []
        case (_, nil):
            return []
        }
    }

    func copy() -> TreeSitterParseState {
        return TreeSitterParseState(tree: tree?.copy())
    }
}

extension Parser {
    func parse(state: TreeSitterParseState, string: String, limit: Int? = nil) -> TreeSitterParseState {
        let newTree = parse(tree: state.tree, string: string, limit: limit)

        return TreeSitterParseState(tree: newTree)
    }

    func parse(state: TreeSitterParseState, readHandler: @escaping Parser.ReadBlock) -> TreeSitterParseState {
        let newTree = parse(tree: state.tree, readBlock: readHandler)

        return TreeSitterParseState(tree: newTree)
    }
}
