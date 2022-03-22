[![License][license badge]][license]

# Neon
A system for working with language syntax.

Neon aims to provide facilities for highlighting, indenting, and querying the structure of language text in a performant way. It based on [tree-sitter](https://tree-sitter.github.io/tree-sitter/), via [SwiftTreeSitter](https://github.com/ChimeHQ/SwiftTreeSitter).

The library is being extracted from the [Chime](https://www.chimehq.com) editor. It's a pretty complex system, and pulling it out is something we intend to do over time.

## TreeSitterClient

This class is an asynchronous interface to tree-sitter. It provides an UTF16 code-point (NSString-compatible) API for edits, invalidations, and queries. It can process edits of String objects, or raw bytes for even greater flexibility and performance. Invalidations are translated to the current content state, even if a queue of edits are still being processed.

TreeSitterClient requires a function that can translate UTF16 code points (ie `NSRange`.location) to a tree-sitter `Point` (line + offset).

### Suggestions or Feedback

We'd love to hear from you! Get in touch via [twitter](https://twitter.com/chimehq), an issue, or a pull request.

Please note that this project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md). By participating in this project you agree to abide by its terms.

[license]: https://opensource.org/licenses/BSD-3-Clause
[license badge]: https://img.shields.io/github/license/ChimeHQ/Neon
