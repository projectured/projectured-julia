# Markdown domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [natural.md](../../platform/natural/natural.md), [serialization.md](../../platform/serialization/serialization.md)

The Markdown domain, `ProjecturedMarkdown`, holds a Markdown page as a tree of blocks and inlines. It has two presentations of one page, source and rendered, and it can hold a file of another domain as a block of the page. This document says where it differs from the [shape of every domain](../../../design/domain-anatomy.md).

<img width="396" alt="Markdown example" src="../../../asset/image/example/markdown-rendered.png">

## How it works

`MarkdownRoot` holds the page in `elements`. The blocks are `MarkdownHeading`, `MarkdownParagraph`, `MarkdownCodeBlock`, `MarkdownQuote`, `MarkdownList` with `MarkdownListItem`, `MarkdownTable` with `MarkdownTableRow`, and `MarkdownThematicBreak`. The inlines are `MarkdownText`, `MarkdownCode`, `MarkdownEmphasis`, `MarkdownStrong`, `MarkdownLink` and `MarkdownImage`. A container holds its children in a `CellVector` field: `content` for inlines, `elements`, `items` or `rows` for blocks. A table holds its `header` row, its body `rows`, and one alignment for each column in `alignments` (`:default`, `:left`, `:center` or `:right`). An entry of a table row is a `MarkdownParagraph`, because an entry is a run of inlines.

The domain does not use `@domain`. It declares `MarkdownDocument` by hand, and `MarkdownInsertion` has a `value::Any` field. It has no `@gestures` tables, so the structural edits of JSON do not exist here. A text edit of a field goes through the shared splice, as in every domain.

### Two presentations

`MarkdownToSyntax(; style)` selects one of two presentations:

- **`:source`**, the default, shows the Markdown text with colours. Every marker (`#`, `**`, `` ` ``, `[]()`, `- `, `>`) is a span that you can edit. All rules are `@projection_template` rules.
- **`:rendered`** shows the formatted page with no markers: large headings, bold and italic text, bullets, quote bars and the images. A container gives its font weight and size to the text below it through an ambient style in the printer context. The rules that pass this style on are hand-written; the other rules are the `:source` rules.

### The page as a stack of blocks

A page has a second route to the screen. `MarkdownRootToVerticalLayout` makes the page a `VerticalLayout` with one child for each block, and each block then goes through its own chain. The map is one step: `elements[i]` becomes `children[i]`.

A table takes this route too. The layout draws it as a `WidgetTable`: the entries of the header are its column headers, the entries of each row are a row of it, the columns share the width of the page, an entry breaks its lines at the edge of its column, and each column sits where the delimiter row says (the `align` of the column, with `:default` at the left). The widget table holds the paragraphs of the table and not copies, and the maps rename only the steps between the page and an entry: `header.elements[j]` is `column_headers[j]`, `rows[k]` is `rows[k]`, and `rows[k].elements[j]` is `cells[k][j]`. A click on a header puts the caret in its entry, as a click in a cell does; a whole column, `columns[j]`, has no place in the page, so it maps to nothing. In the syntax projection, in both presentations, a table is its source: pipes between the entries, and a delimiter row made from `alignments`.

This route exists for a block that is not Markdown. A page can hold any file document, for example a `JsonFile`, as an element. In one syntax tree that element would arrive as reflected text and would not take a click. In the layout it is drawn by its own projection inside an embed card that you can fold. `make_embed_card` makes the card once for each element and keeps it in an `IdDict`, so the fold state stays when a block is added above it. The layout maps only three operations into a card: `ReplaceSelectionOperation`, `InvokeActionOperation` and `ToggleCollapseOperation`.

### Links

A link follows its target with the target form of `OpenPageOperation` ([navigator.md](../../platform/navigator/navigator.md)). In the source view a press puts the caret in the text of the link, so Ctrl+click follows it and Ctrl+Shift+click opens it in a new tab; in the rendered view a plain click follows it, Ctrl+click opens a new tab, and the pointer is a hand over it. Each is an `override` rule, which takes the click from the caret of the text. The tooltip of a link shows its target. `find_navigator_target` of a page names a heading by its slug (`compute_markdown_heading_slug`, as GitHub writes an anchor), and of a `MarkdownFile` also a file beside it that exists; a URL names nothing.

## The text form

`parse_markdown` reads the blocks and the inlines listed above. It reads the Markdown that the documentation tools write: a list item takes the lines below it that start no block, a run of lines indented by 4 columns is a code block with no language, a Julia admonition (`!!! note "title"` and an indented body) is a quote whose first paragraph is the title in bold, and a GitHub table is a `MarkdownTable`. A `|` escaped as `\|` is a pipe in its entry. The parser joins the lines of a paragraph with a space, so a page printed back is not always the text it was read from: a paragraph is one line, an indented code block is fenced, an admonition is a quote, and an ordered list has bullets. `MarkdownFile` is the file type, for `.md` and `.markdown`. A reference to a node in another file is a fenced code block with the language `pred-ref`, because a fence is the opaque block of Markdown.

`get_markdown_section(document, title)` returns the part of a page from a heading to the next heading of the same or a higher level. The result shares the cells of the page. It is the Markdown method of `get_document_section`, so the `section(file("a.md"), "Title")` marker of a multi-file project can name a section. A missing title and a title that occurs twice both raise an error.

### The theme

`MarkdownTheme` holds the look of the Markdown projections: the text of the markers, of the source text, of code and of a language, of the marker of a heading, of a URL and an alt text; for the rendered form the body text, the bold and the italic font, the four heading fonts, the color of a heading and of a link, the caption, the rendered markers, and the gap between the blocks of a page. Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `MarkdownToSyntax(; style, theme)` gives each projection the style of
its role with `get_markdown_style`, from `theme`, a `MarkdownTheme` scaled or
not, or the default styles for `nothing`, and the layout of a page takes
`block_gap` the same way. A heading holds the four fonts of its levels as its
own fields, `heading_1_font` through `heading_font`, and picks among them by
the level it draws. The natural registration gives the scaled theme of the
`Appearance` of the editor, so the view follows its scales, and the appearance
tab shows a section for `MarkdownTheme`.

## How it fits

`ProjecturedMarkdown` depends on the kernel and the platform. Beyond what every text domain needs, it uses the layout, graphics and widget slices for the vertical layout, the images and the embed cards. No domain depends on it.

Its `__init__` registers three natural rows, because Markdown reaches two rungs of the natural ladder:

| Call | What it gives |
| --- | --- |
| `register_natural_domain!(MarkdownDocument; rung = :syntax, make = () -> MarkdownToSyntax(), format = :md, …)` | the source form for files, text export and the tools |
| `register_natural_syntax!(:markdown, …)` | the `:rendered` syntax for the general renderer |
| `register_natural_graphics!(:markdown_page, …)` | a `MarkdownRoot` drawn as a stack of blocks; a heading, a paragraph, a quote and a list break their lines at the page width |

So a file written by ProjecturEd is Markdown source, and a page in a tab is the rendered page.

## Design decisions

- **The presentation is a parameter of the projection.** The source and the rendered view are two projections of the same document, as the block and flow styles of YAML are. See [plan/done/markdown-rendered-projection.md](../../../../plan/done/markdown-rendered-projection.md).
- **A page is a stack of blocks, not only a syntax tree.** A block of another domain, or a live widget, then keeps its own projection and its own reader. The reason is in the header of `source/domain/markdown/MarkdownToLayout.jl`.
- **A section is addressed by the words of its heading.** A section keeps its address when it moves, and a rename makes the address fail with an error instead of pointing at the wrong section.
- **The reference marker is a fence.** XML uses an element and JSON a string for the same reason: each format spells a reference with its own opaque unit.

## Usage

```julia
page = MarkdownRoot([
    MarkdownHeading(1, [MarkdownText("Title")]),
    MarkdownParagraph([MarkdownText("Some "), MarkdownStrong([MarkdownText("bold")]), MarkdownText(" text.")]),
])
source   = MarkdownToSyntax()                    # style = :source
rendered = MarkdownToSyntax(style = :rendered)
section  = get_markdown_section(page, "Title")
page     = parse_markdown("# Title\n\nSome **bold** text.\n")
```

- Examples: `markdown_example` (source) and `markdown_rendered_example` (rendered, with word wrap). The factories are `make_markdown_document_example`, `make_markdown_projection_example` and `make_markdown_rendered_projection_example`.
- Test: `test_markdown()` runs the layering guard, the parser test (`test_markdown_parser()`, with excerpts of real tool answers and a parse of every guide), the page wrap test, the embed card test and the page table test (`test_markdown_page_table()`).

## Limits

- No test covers the syntax projection by itself.
- The parser reads a flat list only: an indented list item is an item of the same list. It reads no hard line break, no HTML and no math, and an `<img …>` line is a paragraph of text.
- No structural gestures exist: you can edit the text of a block but not insert a block with a key.
