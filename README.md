[![Build Status][build status badge]][build status]
[![License][license badge]][license]
[![Platforms][platforms badge]][platforms]
[![Documentation][documentation badge]][documentation]

# Neon
A Swift library for efficient highlighting, indenting, and querying structured syntax.

It features:

- Minimal text invalidation
- Support for multiple token sources
- A hybrid sync/async system for targeting flicker-free styling on keystrokes
- [tree-sitter](https://tree-sitter.github.io/tree-sitter/) integration
- Compatibility with lazy text data reading
- Flexibility when integrating with a larger text system

It does not feature:

- A theme system
- A single View subclass

Neon has a strong focus on efficiency and flexibility. I realize that many people are looking for a drop-in editor View subclass that does it all. This is a lower-level library. You could, however, use Neon to power the portions of this editor.

The library is being extracted from the [Chime](https://www.chimehq.com) editor. It's a big system, and pulling it out is something we intend to do over time.

## Language Support

Neon is built around the idea that there can be multiple sources of information about the semantic meaning of the text, all with varying latencies and quality.

- [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) has [semantic tokens](https://microsoft.github.io/language-server-protocol/specifications/specification-current/#textDocument_semanticTokens), which is high quality, high latency, and typically used in combination with other sources.
- [tree-sitter](https://tree-sitter.github.io/tree-sitter/) is very good quality, and can **potentially** be low-latency
- Regex-based systems can have ok quality and low-latency
- Simpler pattern-matching systems generally have poor quality, but have very low latency

Neon includes built-in support for tree-sitter via [SwiftTreeSitter](https://github.com/ChimeHQ/SwiftTreeSitter). Tree-sitter uses separate compiled parsers for each language. There are a variety of ways to use tree-sitter parsers with SwiftTreeSitter. Check out that project for details.

## Integration

Neon is text-system independent. It makes very few assumptions about how text is stored, displayed, and styled. And, it is built around parts that can be used together to build a full system. But, there are also some helper types for use-cases with simpler needs.

### TextViewSystemInterface

An implementation of the `TextSystemInterface` protocol for `NSTextView`/`UITextView`. This takes care of the interface to the view and `NSLayoutManager`, but defers `Token`-style translation (themes) to an external `AttributeProvider`. This is compatible with both TextKit 1 and 2.

### TextViewHighlighter

A more full-featured system that integrates `NSTextView`/`UITextView` with a `TreeSitterClient`. This is a good way to get going quickly, or just to see how the parts fit together. Also compatible with TextKit 1 and 2.

Will take over as the delegate of the text view's `NSTextStorage`.

There is also an example project that demonstrates how to use `TextViewHighlighter` for macOS and iOS.

## Manual Integration

A minimal integration can be achieved by configuring a `Highlighter` to interface with an `NSTextView`:

```swift
func applicationDidFinishLaunching(_ aNotification: Notification) {
   let textInterface = TextViewSystemInterface(textView: textView, attributeProvider: self.attributeProvider)
   self.highlighter = Highlighter(textInterface: textInterface, tokenProvider: self.tokenProvider)
   textStorage.delegate = self
   self.highlighter.invalidate()
}
```

Attaching the highlighter to a text view interface tells it _what_ to update, but not _when_. You have to notify the highlighter whenever the text view's content changes, and invalidate existing highlighting as needed. Such notifications can be conveyed by making yourself the delegate of your text view's `textStorage`, and implementing this delegate method:

```swift
func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
   // Map NSTextStorageDelegate editedRange to Neon's style of editedRange
   let adjustedRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
   self.highlighter.didChangeContent(in: adjustedRange, delta: delta)

   DispatchQueue.main.async {
      self.highlighter.invalidate()
   }
}
```

Notice that the `invalidate` method is dispatched asynchronously to ensure the styles are not updated until after the underlying text storage is done being edited.

The initial configuration of `highlighter` included references to `self.tokenProvider` and `self.attributeProvider`, which are responsible for providing the logic behind _what_ gets highlighted, and _how_ it should be done. At a minimum, the `TokenProvider` generates and supplies named tokens that correspond to ranges of text:

```swift
let paintItBlackTokenName = "paintItBlack"

func tokenProvider(_ range: NSRange, completionHandler: @escaping (Result<TokenApplication, Error>) -> Void) {
   var tokens: [Token] = []
   guard let searchString = self.textView.textStorage?.string else {
      // Could also complete with .failure(...) here
      completionHandler(.success(TokenApplication(tokens: tokens, action: .replace)))
      return
   }

   if let regex = try? NSRegularExpression(pattern: "[^\\s]+\\s{0,1}") {
      regex.enumerateMatches(in: searchString, range: range) { regexResult, _, _ in
         guard let result = regexResult else { return }
         for rangeIndex in 0..<result.numberOfRanges {
            let tokenRange = result.range(at: rangeIndex)
            tokens.append(Token(name: paintItBlackTokenName, range: tokenRange))
         }
      }
   }

   completionHandler(.success(TokenApplication(tokens: tokens, action: .replace)))
}
```

In this trivial example, the "paint it black" token is unilaterally applied to every non-whitespace range of the text. It demonstrates how you use a token provider to associate named tokens with arbitrary ranges of text. It's important to understand though that supplying the token doesn't change anything about the appearance of the corresponding text. In order to achieve that, you need to implement the _attribute provider_, which effectively translates named tokens in to suitable attributes:

```swift
func attributeProvider(_ token: Token) -> [NSAttributedString.Key: Any]? {
   if token.name == paintItBlackTokenName {
      return [.foregroundColor: NSColor.red, .backgroundColor: NSColor.black]
   }
   return nil
}
```

Now our example achieves its goal of "painting black" any runs of non-whitespace characters, along with single whitespace characters between them:

<img src="PaintItBlack.png?raw=true" width="582" alt="Screenshot of 'Paint it Black' text window showing text with a black background and red text." />

Using this basic structure you can annotate the text with tokens while separately determining the appropriate styling for those tokens.

## Advanced Integration

Achieving better performance and guaranteed flicker-free highlighting is more challenging. Monitoring the visible rect of the text view will improve performance. You need to know when a text change has been processing by enough of the system that styling is possible. This point in the text change lifecycle is not natively supported by `NSTextStorage` or `NSLayoutManager`. It requires an `NSTextStorage` subclass. But, even that isn't quite enough unfortunately, as you still need to precisely control the timing of invalidation and styling. This is where `HighlighterInvalidationBuffer` comes in.

## Relationship to TextStory

[TextStory](https://github.com/ChimeHQ/TextStory) is a library that contains three very useful components when working with Neon.

- `TSYTextStorage` gets you all the text change life cycle hooks without falling into the `NSString`/`String` bridging performance traps
- `TextMutationEventRouter` makes it easier to route events to the components
- `LazyTextStoringMonitor` allows for lazy content reading, which is essential to quickly open large documents

You can definitely use Neon without TextStory. But, I think it may be reasonable to just make Neon depend on TextStory to help simplify usage.

## Components

### Highlighter

This is the main component that coordinates the styling and invalidation of text.

- Connects to a text view via `TextSystemInterface`
- Monitors text changes and view visible state
- Gets token-level information from a `TokenProvider`

Note that Highlighter is built to handle a `TokenProvider` calling its completion block more than one time, potentially replacing or merging with existing styling.

### HighlighterInvalidationBuffer

In a traditional `NSTextStorage`/`NSLayoutManager` system (TextKit 1), it can be challenging to achieve flicker-free on-keypress highlighting. This class offers a mechanism for buffering invalidations, so you can precisely control how and when actual text style updates occur.


### TreeSitterClient

This class is an asynchronous interface to tree-sitter. It provides an UTF-16 code-point (`NSString`-compatible) API for edits, invalidations, and queries. It can process edits of `String` objects, or raw bytes. Invalidations are translated to the current content state, even if a queue of edits are still being processed. It is fully-compatible with reading the document content lazily.

- Monitors text changes
- Can be used to build a `TokenProvider`

`TreeSitterClient` provides APIs that can be both synchronous, asynchronous, or both depending on the state of the system. This kind of interface can be important when optimizing for flicker-free, low-latency highlighting live typing interactions like indenting.

Using it is quite involved - here's a little example:

```swift
import SwiftTreeSitter
import TreeSitterSwift // this parser is available via SPM (see SwiftTreeSitter's README.md)
import Neon

// step 1: setup

// construct the tree-sitter parser for the language you are interested in
let language = Language(language: tree_sitter_swift())

// construct your highlighting query
// remember, this is a one-time cost but can be expensive
let url = Bundle.main
              .resourceURL
              .appendingPathComponent("TreeSitterSwift_TreeSitterSwift.bundle")
              .appendingPathComponent("queries/highlights.scm")
let query = try! language.query(contentsOf: url)

// step 2: configure the client

let client = TreeSitterClient(language: language)

// this function will be called with a minimal set of text ranges
// that have become invalidated due to edits. These ranges
// always correspond to the *current* state of the text content,
// even if TreeSitterClient is currently processing edits in the
// background.
client.invalidationHandler = { indexSet in
    // highlighter.invalidate(.set(indexSet))
}

// step 3: inform it about content changes
// these APIs match up fairly closely with NSTextStorageDelegate,
// and are compatible with lazy evaluation of the text content

// call this *before* the content has been changed
client.willChangeContent(in: range)

// and call this *after*
client.didChangeContent(to: string, in: range, delta: delta, limit: limit)

// step 4: run queries
// you can execute these queries directly in the invalidationHandler, if desired

// Many tree-sitter highlight queries contain predicates. These are both expensive
// and complex to resolve. This is an optional feature - you can just skip it. Doing
// so makes the process both faster and simpler, but could result in lower-quality
// and even incorrect highlighting.

let provider: TreeSitterClient.TextProvider = { (range, _) -> String? in
   return nil
}

let range = NSMakeRange(0, 10) // for example
client.executeHighlightsQuery(query, in: range, textProvider: provider) { result in
   // Token values will tell you the highlights.scm name and range in your text
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
[documentation]: https://swiftpackageindex.com/ChimeHQ/Neon/main/documentation
[documentation badge]: https://img.shields.io/badge/Documentation-DocC-blue
