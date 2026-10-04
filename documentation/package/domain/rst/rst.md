# RST domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [markdown.md](../markdown/markdown.md), [natural.md](../../platform/natural/natural.md)

The RST domain, `ProjecturedRST`, holds reStructuredText as a tree of about forty document types, with a parser, two presentations and a page of blocks. It has the shape of the [Markdown domain](../markdown/markdown.md), and this document says where it differs from Markdown and from the [shape of every domain](../../../design/domain-anatomy.md). It covers the section tree, the written indentation, the parser rules, the reference marker and the round-trip criterion.

## How it works

The documents are in three groups:

- **Inlines**: `RstText`, `RstLiteral`, `RstEmphasis`, `RstStrong`, `RstRole`, `RstReference`, `RstSubstitutionReference`, `RstFootnoteReference`.
- **Blocks**: `RstRoot`, `RstSection`, `RstParagraph`, the lists and their items, `RstLiteralBlock`, `RstLineBlock`, `RstBlockQuote`, `RstGridTable`, `RstComment`, `RstTarget`, `RstFootnote` and a few more.
- **Directives**: eleven typed structs and one generic `RstDirective`.

As in Markdown, the domain does not use `@domain`. It declares `RstDocument` by hand, `RstInsertion` has a `value::Any` field, and no `@gestures` table exists. A text edit of a field goes through the shared splice.

### Sections nest, the source does not

RST writes a section as a title line under an adornment line, and the adornment character alone sets the depth. No character has a fixed meaning: the order in which a file first uses a character sets its depth in that file.

The document is a tree instead. An `RstSection` owns every block down to the next title at its own depth or above. `RstSection.adornment` keeps the character that the file used, and `overline` records a line above the title. So a save writes the convention of the file and does not impose one.

### Directives are typed where the rendered view needs it

`RstLiteralInclude`, `RstFigure`, `RstCodeBlock`, `RstImage`, `RstVideo`, `RstAudio`, `RstAdmonition`, `RstToctree`, `RstMathBlock`, `RstRawBlock` and `RstRoleDefinition` have named fields. A figure must find its picture, a code block its language and an admonition its kind. Every other directive is an `RstDirective` with a `name`, an `argument`, an `options` list and a body in `elements`. A typed directive keeps the options that it does not name in `extra`, so a save loses nothing.

`RstRole` holds `name` and `content` as two strings. A role has no nested markup, and the set of role names is open, because a document declares its own roles with `.. role::`.

### Two presentations

`RstToSyntax(; style)` takes `:source` or `:rendered`, the same two words as `MarkdownToSyntax`:

- **`:source`** shows the RST text with colours. Every marker is on the page, and every one-line field is editable.
- **`:rendered`** shows no markers: large bold titles, bold and italic text, a role as a coloured chip, a figure as its picture, `•` bullets and a `────` rule.

The rendered table starts from the source table and replaces only the rules whose presentation differs. Many of them are the same rule with a different field value, for example `RstBulletListToSyntaxNode(marker="•  ")`. The rules that must change the font of every text below them are new: bold, italic and a section title put an ambient `:rst_style` in the printer context, and the text leaf reads it. `MarkdownToSyntax` passes its style down in the same way.

In the rendered view a directive shows what it means, not how it is spelled:

| Directive | The rendered view |
| --- | --- |
| `.. figure::` | the picture, with its caption under it |
| `.. code-block:: ini` | the code alone, indented |
| `.. note::` | the word `Note` over an indented body |
| `.. toctree::` | the word `Contents` over the entries |
| `.. literalinclude::` | one line, `↳ path (language, from … to)` |

A table maps the role name to the colour of its chip, and an unknown name gets a neutral grey. The rule that draws the `↳` arrow takes `RstTheme.rendered_marker_text`, a role over the code font in the family DejaVu Sans Mono, because the chrome font has no such glyph.

### Indentation is written, not computed

Every compound of this domain has `indentation = 0` and writes the indent into its own `open` and `sep` text. The current column travels as an ambient `:rst_indent` in the printer context. A container that owns an indented body pushes a deeper indent, and every rule that writes a newline puts the ambient after it.

The `indentation` field of a compound can not do this. It writes a newline before the first child too, and it always costs one indent level of the pipeline, so the items of a list would leave their marker column. `@projection_template` builds a printer from `(prj, doc)` alone and has no access to the context. So two macros of `source/domain/rst/RstToSyntax.jl`, `@rst_flat` and `@rst_indented`, call `print_template_document`, the entry point of the template macro, and give the builder the ambient column as well. A rule keeps its template body, and the reader still comes from the template.

### Seven opaque bodies

The body of a code block, a literal include, a literal block, a math block, a raw block, a comment and a grid table is text of more than one line, indented under its marker. A `bound` leaf maps a splice back by offset, and an indent written into the text would move every offset after the first line. So these seven bodies print through a computed `TextString`. They are correct on the page and in a saved file, but you can not edit them in the source view. Every other field is `bound`.

### The page as a stack of blocks

`source/domain/rst/RstToLayout.jl` makes a `VerticalLayout` of an `RstRoot` and also of an `RstSection`. Each block then goes through its own chain, and a file of another domain in the page stands in an embed card from `make_embed_card`. Markdown needs only the root rule, because a Markdown page is flat. An RST section owns its blocks, so without the section rule each embed below the first title would stay in a syntax tree.

The rule moves the blocks and does not change them, so the reference maps only change the head: `elements[i]` becomes `children[i]`. In a section the title takes the first slot, so the index moves by one. The title prints as one line of text in the font of its level.

### The text form

`parse_rst` works on a vector of lines that its caller has already dedented to column zero, and tries the block constructs in a fixed order. A construct that owns an indented body, such as a directive, a list item or a definition, dedents that body and gives it to the same reader. So nesting needs no special case. Sections come out flat, as title markers, and one pass after the read assigns the depths by order of first use and builds the tree.

Two rules are easy to break:

- **A paragraph joins its lines with a space.** RST reflows a paragraph, so a line break in it has no meaning. A stored newline would print a line at column zero, which ends the list item or directive body that holds the paragraph.
- **Inline markup obeys the start-string and end-string rules.** A start-string must have a character that is not blank after it, and an end-string must have one before it. Without these rules a wildcard such as `*.x = 1` in running text opens an emphasis span. A reference has its own end finder, because the `_` after its closing backquote belongs to its marker.

### The file and the reference marker

`RstFile` is the file type for `.rst`. A reference to a node in another file is a directive whose argument is the marker:

```
.. pred-ref:: <<file("child.json")>>
```

The directive needs no parser rule: an unknown directive name becomes an `RstDirective`, and a save writes it back unchanged. A `pred-ref` whose argument is not a marker stays the directive that it was, so a typing mistake shows on the page.

`find_rst_section(document, title)` returns the first section, depth first, whose title reads `title`. `get_rst_title_text` gives that plain text, with every inline marker dropped. The search returns the section node itself, because an RST section already owns its blocks. It is the RST method of `get_document_section`, so `<<section(file("page.rst"), "Title")>>` embeds a section of a page, and a title that no section has raises an error.

### The theme

`RstTheme` holds the look of the RST projections: the text of the markers, the source text, a literal, a target, a value, a reference, a substitution, a directive, an admonition and a section title; for the rendered form the body text, the bold and the italic font, the four title fonts, the color of a title, the caption, the rendered markers, and the gap between the blocks of a page. The color of a role takes the color of the text of its kind. Each value has
the default that the domain draws with no appearance. A projection holds its
styles as fields, and no theme; nothing in it scales or asks whether a theme is
scaled. `RstToSyntax(; style, theme)` gives each projection the style of its role with `get_rst_style`, from `theme`, a `RstTheme` scaled or not, or the default styles for `nothing`, and the layouts of a page and of a section take `block_gap` the same way. A section title holds the font of each of its levels and its color as fields, picked by the level while it prints, rather than a `theme` field read at print time. The natural
registration gives the scaled theme of the `Appearance` of the editor, so the view
follows its scales, and the appearance tab shows a section for `RstTheme`.

## How it fits

`ProjecturedRST` depends on the kernel and the platform, using the layout and widget slices for the page and the embed cards. Unlike other domains, it does not use the domain slice's `@domain` machinery, and no other domain depends on it.

Its `__init__` makes four calls:

| Call | What it gives |
| --- | --- |
| `register_natural_domain!(RstDocument; rung = :syntax, make = () -> RstToSyntax(), format = :rst, …)` | the source form for files, text export and the tools |
| `register_natural_syntax!(:rst, …)` | the `:rendered` syntax for the general renderer |
| `register_natural_graphics!(:rst_page, …)` | an `RstRoot` and an `RstSection` drawn as a stack of blocks |
| `register_file_document_type!(".rst", RstFile)` | the file type |

## Design decisions

- **The document is a tree of sections.** A section can then be moved as a unit and named by its title. The adornment stays in the document, so a save keeps the convention of the file. See [plan/done/rst-domain.md](../../../../plan/done/rst-domain.md).
- **A directive is typed only where the rendered view reads its fields.** The alternative is a search of the option list by name on each read. The generic `RstDirective` holds the rest.
- **The indent is written into the text.** The `indentation` field of a compound costs one pipeline level, and RST needs the three-space body indent that `.. ` has.
- **An opaque body is not splice-editable.** An editable body would need offsets that account for the indent of each line; the domain keeps the offsets of `bound` exact instead.
- **The section also becomes a layout.** An embed in a section then takes its own clicks, as an embed in the root does.

## Usage

```julia
doc = RstRoot([
    RstSection(1, "=", [RstText("Title")];
               elements = [RstParagraph([RstText("Body "), RstStrong([RstText("text")]), RstText(".")])]),
])
source   = RstToSyntax()                    # style = :source
rendered = RstToSyntax(style = :rendered)
doc      = parse_rst("Title\n=====\n\nBody **text**.\n")
section  = find_rst_section(doc, "Title")
print_natural_text(doc)                     # the RST source
```

- Examples: `rst_example` shows the source view, and `rst_rendered_example` shows the rendered view with word wrap. The factories are `make_rst_document_example`, `make_rst_projection_example` and `make_rst_rendered_projection_example`. The atomic catalog has one document for each type.
- Test: `test_rst()` runs the layering guard, `test_rst_parser()`, `test_rst_round_trip()` on the fixtures in `test/domain/rst/fixture/rst/`, and `test_rst_embed_card()`. The umbrella serializer tests cover the `pred-ref` marker.
- `test_rst_corpus(dir)` parses every `.rst` file under `dir`, prints it and parses it again, and returns the counts. It is not part of `test_rst()`, because the corpus is not in this repository.

### The round-trip criterion is AST idempotence

`parse_rst(print_natural_text(parse_rst(text)))` must equal `parse_rst(text)`. Byte equality is not required and is not reached: a paragraph is joined onto one line, an adornment is drawn again at the width of the title, and a directive body is indented to three spaces. What must hold is that a read of a saved file gives back the document that it came from. [plan/done/rst-domain.md](../../../../plan/done/rst-domain.md) records that every file of the documentation tree that the domain was built for meets this criterion.

## Limits

- **`literalinclude` and `include` do not read their file.** The projection shows the path and the slice bounds, and it does not apply `start-at` or `end-at`. A read needs a loader context, such as the `FileProject` of the serialization slice, and the projection has none.
- **A role is a styled string.** A Sphinx role such as `:doc:` does not resolve to its target.
- **The source view prints the start number of an enumerated list on every item.** A template rule has no access to the index of an item. RST numbers the items again when it renders them, and a re-parse gives the same list. The rendered view counts correctly, because `RstEnumeratedListToStyledNode` builds its items by hand.
- **`RstSectionToStyledNode` has no reference mappers.** The rendered section prints, but a selection does not map through it, so navigation in the rendered view stops at a section. The source view and the page of blocks map fully.
- **The title of a section in the page of blocks is flat.** Its inline markup prints as plain text, because a layout child gets no ambient `:rst_style`. A selection maps into the blocks of the section, not into its title.
- **The rendered grid table keeps the drawn grid.** It does not lay the cells out as a table.
- **A figure path resolves against the working directory of the process**, not against the file of the figure. A path that does not resolve prints as text.
- **An inline marker is not read.** Only a block-level `pred-ref` directive is a marker. Markdown splits its text runs around a marker in a line of prose, and RST has no such rule.
- **No projection reads `collapsed`.** `RstRoot`, `RstSection` and `RstDirective` have the field, but no rule gives it to the output.
- **No structural gestures exist.** You can edit the text of a field, but no key inserts a block.
