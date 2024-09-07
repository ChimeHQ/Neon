# Choosing Components

Neon is built from components that must be assembled together to be useful.

## Overview

Neon has a very strong focus on flexibility. It made up of a collection of components, not all of which you might need. A big part of getting started is understanding how to pick the components that will best work with your system.

There are three important factors in deciding how to integrate Neon into your system:

- the text view you use
- the kind of styling do you need to apply
- how you map text data to style

## Text System

Neon is text system-independent. This means that it does not come with an AppKit/UIKit/SwiftUI view. This view is something you always have to provide yourself. However, Neon does include many pre-built interfaces that work well with existing views.

### Text Interface

Neon's interface with your text view requires two parts. First is the `TextSystemInterface`, which is a protocol that will be used to apply styles. But, you will also need to manually inform Neon's components about changes to the text content and visibility.

``TextViewHighlighter`` can quickly integrate syntax highlighting to a `NS/UITextView`. It take care of almost all these details, but does trade off flexibiltity and some performance.

### Processing Text

Neon needs to know what style applies to what parts of the text. This is often driven by a parser that can assign semantic meaning to ranges. This is done using the ``TokenProvider`` type.

If you are working with source code, you might be able to use tree-sitter to perform the semantic analysis needed. Neon comes with optional tree-sitter integration via the `TreeSitterClient` type. This is integrated into ``TextViewHighlighter``.
