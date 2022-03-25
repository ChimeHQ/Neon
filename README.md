[![Build Status][build status badge]][build status]
[![License][license badge]][license]
[![Platforms][platforms badge]][platforms]

# Neon
A system for working with language syntax.

Neon aims to provide facilities for highlighting, indenting, and querying the structure of language text in a performant way. It is based on [tree-sitter](https://tree-sitter.github.io/tree-sitter/), via [SwiftTreeSitter](https://github.com/ChimeHQ/SwiftTreeSitter).

The library is being extracted from the [Chime](https://www.chimehq.com) editor. It's a pretty complex system, and pulling it out is something we intend to do over time.

## Language Parsers

Tree-sitter uses seperate compiled parsers for each language. Thanks to [tree-sitter-xcframework](https://github.com/krzyzanowskim/tree-sitter-xcframework), you can get access to pre-built binaries for the runtime and **some** parsers. It also includes query definitions for those languages. This system is compatible with parsers that aren't bundled, but it's a lot more work to use them.

## Why is this so complicated?

Working with small, static, and syntactically correct documents is one thing. Achieving both high performance and high quality behavior for an editor is totally different. Work needs to be done on every keystroke, and minimizing that work requires an enormous amount of infrastructure and careful design. Before starting, it's worth seriously evaluating your performance and quality needs. You may be able to get away with a much simpler system. A lot of this boils down to size of the document. Remember: most files are small, and small files can make even the most naive implementation feel acceptable.

Some things to consider:

- Latency to open a file
- Latency to visible elements highlight
- Latency to end-of-document highlight
- Latency on keystroke
- Precise invalidation on keystrokes
- Precise invalidation on inter-file changes
- Highlight quality in the face of invalid syntax
- Ability to apply progressively higher-quality highlighting

## TreeSitterClient

This class is an asynchronous interface to tree-sitter. It provides an UTF16 code-point (NSString-compatible) API for edits, invalidations, and queries. It can process edits of String objects, or raw bytes for even greater flexibility and performance. Invalidations are translated to the current content state, even if a queue of edits are still being processed.

TreeSitterClient requires a function that can translate UTF16 code points (ie `NSRange`.location) to a tree-sitter `Point` (line + offset).

```swift
import SwiftTreeSitter
import tree_sitter_language_resources
import Neon

// step 1: setup

// construct the tree-sitter grammar for the language you are interested
// in working with manually
let unbundledLanguage = Language(language: my_tree_sitter_grammar())

// .. or grab one from tree-sitter-xcframework
let swift = LanguageResource.swift
let language = Language(language: swift.parser)

// construct your highlighting query
// this is a one-time cost, but can be expensive
let url = swift.highlightQueryURL!
let query = try! language.query(contentsOf: url)

// step 2: configure the client

// produce a function that can map UTF16 code points to Point (Line, Offset) structs
let locationToPoint = { Int -> Point? in ... }

let client = TreeSitterClient(language: language, locationToPoint: locationToPoint)

// this function will be called with a minimal set of text ranges
// that have become invalidated due to edits. These ranges
// always correspond to the *current* state of the text content,
// even if TreeSitterClient is currently processing edits in the
// background.
client.invalidationHandler = { set in ... }

// step 3: inform it about content changes
// these APIs match up fairly closely with NSTextStorageDelegate,
// and are compatible with lazy evaluation of the text content

// call this *before* the content has been changed
client.willChangeContent(in: range)

// and call this *after*
client.didChangeContent(to: string, in: range, delta: delta, limit: limit)

// step 4: run queries
// you can execute these queries in the invalidationHandler

// produce a function that can read your text content
let provider = { contentRange -> Result<String, Error> in ... }

client.executeHighlightQuery(query, in: range, contentProvider: provider) { result in
    // TreeSitterClient.HighlightMatch objects will tell you about the
    // highlights.scm name and range in your text
}
```

### Suggestions or Feedback

We'd love to hear from you! Get in touch via [twitter](https://twitter.com/chimehq), an issue, or a pull request.

Please note that this project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project you agree to abide by its terms.

[build status]: https://github.com/ChimeHQ/Neon/actions
[build status badge]: https://github.com/ChimeHQ/Neon/workflows/CI/badge.svg
[license]: https://opensource.org/licenses/BSD-3-Clause
[license badge]: https://img.shields.io/github/license/ChimeHQ/Neon
[platforms]: https://swiftpackageindex.com/ChimeHQ/Neon
[platforms badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FChimeHQ%2FNeon%2Fbadge%3Ftype%3Dplatforms
