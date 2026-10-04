# Book domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [syntax.md](../../platform/syntax/syntax.md)

The Book domain, `ProjecturedBook`, holds structured prose: a book, its chapters, paragraphs of styled text, lists and pictures. It is a domain with no text form: you build a book as Julia values, and ProjecturEd shows it and edits its text. This document says where it differs from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="Book example" src="../../../asset/image/example/book.png">

## How it works

| Type | Fields that matter |
| --- | --- |
| `BookBook` | `title`, `author` (can be `nothing`), `elements` |
| `BookChapter` | `title`, `numbering`, `elements` |
| `BookParagraph` | `content`, a `TextBlock` of styled spans; `alignment` |
| `BookList` | `elements`, one bullet for each |
| `BookPicture` | `content` (an image or a path), `title` |
| `BookInsertion` | the placeholder |

`BookBook`, `BookChapter` and `BookList` pass their `collapsed` field to the syntax node, so they fold in the view.

A paragraph holds a `TextBlock`, not a string. The spans of the block carry their own font and colour, so a paragraph can mix styles without a markup language. A typed character goes to the span under the caret through the `splice_value!` step of the text package.

`BookToSyntax()` has one rule for each type. Three rules are `@projection_template` rules: the placeholder, the paragraph and the picture. Three are hand-written, because the template markers can not express their shape:

- `BookBook` puts an author leaf in front of the chapters only when the author is not `nothing`;
- `BookChapter` shows `numbering` and `title` as one leaf, so its reference map moves a caret by the length of the number;
- `BookList` puts a bullet in front of each projected element.

The three hand-written rules map only the step that they own. They give the rest of a path to the IO map of the child, so they do not dispatch on the type of an element.

The example chain adds `WordWrapping` between `SyntaxToText` and `TextToGraphics`, so a paragraph breaks at the width of the window.

### The theme

`BookTheme` holds the look of the Book projections: the text of the title, the author and its prefix, a chapter title and its numbering, a paragraph (also the blank lines between the parts), a placeholder, a bullet and a picture. Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `BookToSyntax(; theme)` gives each projection the style of its role
with `get_book_style`, from `theme`, a `BookTheme` scaled or not, or the
default styles for `nothing`, and the book has no graphics row of its own, so
a view draws it through the syntax and the text. The natural
registration gives the scaled theme of the `Appearance` of the editor, so the view
follows its scales, and the appearance tab shows a section for `BookTheme`.

## How it fits

`ProjecturedBook` depends on the kernel and the platform. It uses the syntax, text, graphics and natural slices, but not the serialization or file-format slices. No other package depends on it.

Its `__init__` makes one call: `register_natural_syntax!(:book, …)`, with the row `BookDocument => BookToSyntax()`. So the general renderer draws a book in a tab. The domain makes no `register_natural_domain!` call, so no format name, no file extension and no parser exist for it.

## Design decisions

- **No text form.** A book is made by a program or by the assistant, not read from a file. The package has no parser, no file type and no dependency on the file packages. No plan records the reason.
- **Rich text is data.** A paragraph holds styled spans, not Markdown. The view does not parse the paragraph, and an edit changes a span directly.
- **The abstract root is declared by hand.** `BookDocument` does not use `@domain`, and the domain has no `@gestures` tables.

## Usage

```julia
book = BookBook("Projectured User Guide", "The Projectured Authors", [
    BookChapter("Introduction", "1", [
        BookParagraph(TextBlock(TextString("Reactive cells propagate changes.",
                                           StyleFont("Ubuntu Mono", 20), color_default))),
    ]),
])
run_example(book, make_book_projection_example(); name = "book")
```

- Examples: `book_example`, from `make_book_document_example()` and `make_book_projection_example()`. The atomic catalog has one document for each type.
- Test: `test_book()` runs the layering guard and `test_book_to_syntax`.

## Limits

- A book can not be saved as text or loaded from a text file. A `.pdoc` snapshot of the serialization slice stores it, as it stores any document.
- No structural gesture exists: you can edit the text, but a key does not add a chapter or a paragraph.
