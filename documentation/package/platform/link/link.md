# Link

> **Kind:** design · **Status:** current · **Stands on:** [concepts.md](../../../design/concepts.md), [reference.md](../../kernel/reference.md), [document.md](../../kernel/document.md), [widget.md](../widget/widget.md), [navigator.md](../navigator/navigator.md)

The link slice of `ProjecturedPlatform` holds a link as data: a value that refers to a target and has a face. Each domain has link types of its own, such as a link of Markdown or a reference of rst, and the slice gives the general `Link` and the address `Url`. This document says what a link type answers, how a view gives a link its face, what pieces an address holds and how a person edits it, how an address opens outside the editor, and why a search stops at a link.

## How it works

### The functions of a link

A link type answers three functions:

| Function | Answers | Default |
| --- | --- | --- |
| `is_link(x)` | whether `x` is a link | `false` |
| `get_link_target(link)` | what the link refers to: a document, a place in a document as a `DocumentLocator`, or a `Url` | none: each link type defines it |
| `get_link_content(link)` | the face that the link carries: `nothing`, a string, or any document | `nothing` |

A view that shows a link reads three more, whose defaults come from the target:

| Function | Answers | Default |
| --- | --- | --- |
| `format_link_label(link)` | the text of the face | the content when it is a string; the name of the content when it is a document; else the name of the target as a tree shows it (`format_tree_node_label`), of the node that a place reaches now, `"?"` for a place that reaches nothing, or the address of a `Url` |
| `describe_link(link)` | the words of the tooltip | the name of a document; for a place, the name of the node and of the document that holds the place, such as "beta in Inner"; the address of a `Url` |
| `is_link_broken(link)` | whether the target is gone | `true` for a place that reaches no node, else `false` |

### The general link

`Link(target; content = nothing)` is a document that any document can hold: a note, a list, a section of the explorer. It holds its target directly, as an edge of the graph of the documents, not as an owner. A save of a file writes the target where the file owns it, and a marker at the link, such as `node(file("notes.pred"), "entries[1]")`; a target that only the link holds is written under the link. The load gives the same node at both places. `print_pred_text` writes a tree, and so writes such a node twice.

A tree names a link by its face, and gives it the icon of its target, with no count or condition of the target.

**A search stops at a link.** The walk of the documents asks each document which of its fields it enters (`is_field_walked`, [document.md](../../kernel/document.md)), and `Link` answers `false` for `target`. So a search of a note finds the alias of its link and does not read the large table that the link names, and finds the target where its own document holds it. A save does not use this walk.

### An address

`Url(text)` is an address as the web writes it, and a link to itself, so an address shows as a link wherever it stands. Its icon is `:external_link`.

A `Url` holds the seven pieces of RFC 3986 as fields, each one as it was written: not decoded, not changed to lower case, with no default port added. A piece that the address does not have is `nothing`, and a piece with no text is `""`: `guide.md?` has the empty query, and `guide.md` has no query. The path is never `nothing`, and the `//` part is there when `host` is not `nothing`.

| Address | Pieces that are not `nothing` |
| --- | --- |
| `https://julialang.org` | scheme `https`, host `julialang.org`, path `""` |
| `http://u:p@[::1]:8080/a?b#c` | scheme `http`, userinfo `u:p`, host `[::1]`, port `8080`, path `/a`, query `b`, fragment `c` |
| `mailto:someone@example.org` | scheme `mailto`, path `someone@example.org` |
| `file:///tmp/a%20b.txt` | scheme `file`, host `""`, path `/tmp/a%20b.txt` |
| `#install` | path `""`, fragment `install` |
| `1x:y` | path `1x:y`, because `1x` is no scheme |

- **The read never fails.** `Url(text)` reads with the regular expression of RFC 3986, appendix B, which matches every text, with the scheme limited to its grammar. In the `//` part, the userinfo is the text before the last `@`, and the port the text after the last `:` that stands after any `]`. An address with no host, such as `mailto:` or `urn:`, needs no special case: the text after the scheme is the path.
- **The print gives the same text.** `format_url(url)` prints the pieces by the rule of RFC 3986, section 5.3, so `format_url(Url(text)) == text` for every text, an address or not. `Url(; scheme, host, path, …)` makes an address from its pieces.
- **An edit reads the address again.** `make_url_text_operation(url, text)` writes each piece that `text` changes, in one operation, and `make_url_piece_operation(url, piece, text)` prints the address with one piece changed and reads it again: the host `julialang.org/docs` gives the host `julialang.org` and the path `/docs`. Both write the fields of the same `Url`, so a link that holds it keeps it. A write of one field with `ReplaceReferencedValueOperation` stays possible, as on any document, and can give pieces whose print reads back to other pieces; a program and the assistant change a piece with `make_url_piece_operation`.

- **An absolute address** (`is_absolute_url`) names a place outside the editor, such as `https://julialang.org` or `mailto:someone@example.org`. A `file:` address names a file, whose path `find_url_file_path` reads, with its escaped characters.
- **A relative address**, such as `#install` or `guide.md`, names a place that the page of the link resolves against itself, as a browser resolves a relative link against its page: `find_navigator_target` of the domain of the content.
- **`find_web_url(text)`** answers a `Url` for a text that is an address outside the editor: a scheme with `//` after it, or a `mailto:` address, and `nothing` for any other text. A domain whose links name their target by a text uses it, because a name can hold a colon, such as the rst name `ug:cha:queueing`, and a text with a colon reads as a scheme.

The page of an address is a view document: `make_document_view(url)` answers `UrlView(url)`, which a navigator makes at a visit and at its acquire. `UrlViewToWidget` draws three parts: the text line of the address, the list of its pieces with their names, "none" for an absent piece and "empty" for a piece with no text, and a button. The button reads "Open in the browser", or "Open the file" for a `file:` address, and it is off for a relative address.

### The text line

`UrlToSyntax` prints a `Url` as one line of syntax: a leaf for each piece that is there, and a leaf for each delimiter, `:`, `//`, `@`, `?` and `#`. The host draws in `typed_text` of the syntax theme, and the other pieces and the delimiters in `label_text`, as the address bar of a browser draws them. A selection in a leaf of a piece names the field, such as `.host{3}`. It is a `@projection_template` whose children come from a thunk, so a leaf comes and goes with its piece.

**A typed edit reads the whole address again**, as the address bar of a browser does. The syntax stage gives an edit to the line as a range in leaf `i`, and a delimiter is a leaf too, so the reader finds the place in the text of the address from the leaves before it. It changes the text there, calls `make_url_text_operation`, and puts the caret at the same place in the new text, in the first piece whose text holds that place. So `/docs` typed after the host goes into the path, `?` starts a query, a Backspace that removes `//` makes the host a part of the path, and a paste of a whole address fills every piece. One edit is one operation, and so one undo step.

The page puts the output of the line among its parts, as the navigator does with its path view, and sends a path and a typed edit in the line to `UrlToSyntax` through the IO map of the line.

### The open of an address

`make_target_open_operation(url, place)` of the widget slice has a method for a `Url`: a relative address opens with the target form of `OpenPageOperation`, which the content resolves; an absolute address answers `OpenUrlOperation(url, place)`. The operation is self-contained, so it goes up to the editor unchanged. The navigator slice evaluates it ([navigator.md](../navigator/navigator.md)): a `file:` address opens its file in a tab with a navigator, and any other address goes to `open_url!(editor.backend, address)`. The default of `open_url!` opens nothing and answers `false`; the SDL backend calls `SDL_OpenURL`, which gives the address to the system: the browser for `https:`, the mail program for `mailto:`.

### The view of a link

`LinkToWidget` draws any link as a `WidgetLink` ([widget.md](../widget/widget.md)): a face and a target. The face is the content of the link when it is a document, and else `format_link_label`; the icon is that of the target when the link carries no content; the tooltip is `describe_link`; the target is `get_link_target`; and the link draws muted and opens nothing while `is_link_broken`. Each part is a computed cell, so it follows the link and its target: a rename of the target renames the face. The output holds the selection and the mouse target of the link, so the line shows under the face while the pointer is on it.

`make_graphics_projection` draws a `Link` and a `Url` with `LinkToWidget` and the printer of `WidgetLink`, so they show as links inside any document that a renderer draws.

## How it fits

The slice uses the domain, layout, primitive, projection, style, syntax, text, tree and widget slices of the platform, and the kernel. It stands after the syntax slice, because the text line of an address is syntax and the default face reads `format_tree_node_label` of the tree slice, and before the navigator, which uses `Url` and evaluates `OpenUrlOperation`. It adds methods to `make_target_open_operation` of the widget slice, to `format_tree_node_label` of the tree slice, and to `get_document_decoration` and `make_document_view` of the domain slice.

The domains answer the functions for their own link types: a `MarkdownLink` has the target `Url(url)` ([markdown.md](../../domain/markdown/markdown.md)), and an `RstReference` the target `Url(target)`, or `Url("#<name>")` for a named reference ([rst.md](../../domain/rst/rst.md)). Their views stay in the text pipeline, and their pages answer a `Url` for an address of the web, so a click on a web link opens the browser.

## Design decisions

- **A link is data, and `WidgetLink` is one face of it.** The owner, 2026-10-25: "A Link can also be data, but WidgetLink would usually not be saved into a file like any other widget is not saved either. Any domain can have its own link type." Other views can show a link in other ways.
- **A link holds its target directly.** The owner, 2026-10-25: "the link can contain the document it refers to directly, there's no ownership here. It's an object graph which can be saved to disk."
- **The widget holds a face and a target, and no link.** The owner asked "why not just the face and the behaviour?", and agreed that the behaviour is the target and not a general action: a target is data, which a tooltip can describe, a view can find gone, and an assistant can read.
- **A click on a web address opens the browser at once.** The owner agreed on 2026-10-25. "Open as a page" shows the page of the address with its open.
- **A search stops at a link.** The owner agreed on 2026-10-25, so a link into a table of ten million rows costs a search of a note nothing. The walk asks `is_field_walked`, a field of a document, and not `is_walk_opaque`, which would also hide the alias of the link.
- **An address holds its pieces as written.** The owner asked on 2026-10-25 why a URL is not held by its pieces, scheme, host and port, and chose an address of pieces. A browser keeps a normalized address, which changes what a person wrote at the next save; a piece as written prints back the same text. The port is text for the same reason: `08080` and an empty port must print back as written.
- **A typed edit reads the whole address again**, and is no gesture for each delimiter key. The owner agreed on 2026-10-25. One rule handles a paste, a delete over a delimiter and a typed delimiter, and the pieces stay the stored structure.
- **The path and the query are one text each.** The segments of a path and the pairs of a query are a split of that text, and the pairs are a convention of HTML forms, not of RFC 3986.
- **A name that a page resolves is a relative `Url`.** A browser resolves `href="#install"` against its page in the same way, so the domains need no kind of target of their own.
- **The browser opens through the backend of the editor.** The clipboard reaches the system through a hook in a module, which is global state; the backend is the editor's own.

The plans with the alternatives are [plan/done/a-link-is-data-with-a-target-and-a-face.md](../../../../plan/done/a-link-is-data-with-a-target-and-a-face.md) and [plan/done/an-address-holds-its-pieces.md](../../../../plan/done/an-address-holds-its-pieces.md).

## Usage

```julia
using ProjecturedPlatform
note = ExplorerSection("Notes", Any[Link(page), Link(page; content = "the list"),
                                    Link(Url("https://julialang.org"); content = "Julia")])
format_link_label(Link(page))                 # the name of `page`, as a tree shows it
make_target_open_operation(Url("https://julialang.org"), :here)   # an OpenUrlOperation
url = Url("https://julialang.org/learning?lang=en")
url.host, url.query                            # ("julialang.org", "lang=en")
format_url(url)                                # "https://julialang.org/learning?lang=en"
make_url_piece_operation(url, :query, nothing)  # the edit that removes the query
```

A domain makes its own link type a link with three methods:

```julia
is_link(::MyLink) = true
get_link_target(link::MyLink) = link.document
get_link_content(link::MyLink) = link.text
```

- Tests: `test_link()` in `ProjecturedPlatformTest`, `test/platform/link/LinkTest.jl`; the walk that leaves out a field in `test_document_contract()` of `ProjecturedKernelTest`; the links of Markdown and rst in `test_markdown()` and `test_rst()`.

## Limits

- No command makes a link or changes its target: a program or the assistant builds one.
- No view shows the links that point to a document ("what links here").
- The face of a `Url` is its address: no read gives the title of a web page.
- No view lists the segments of a path or the pairs of a query, no function checks whether an address is valid, no comparison finds two addresses that are equal in meaning, and no function resolves a relative address against a base address.
- A `Url` has no natural row and no clipboard text of its own.
- A view shows a link as a `WidgetLink` only where it draws one: a roster cell or a tree that holds a link shows it by the view of its own type.
