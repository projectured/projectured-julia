# The RST domain

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

The `rst` slice holds reStructuredText: a document model, a parser, a
two-style projection, and a `FileDocument` wrapper. It was built against the
documentation of [INET](https://github.com/inet-framework/inet) — 349 files
and about 51 000 lines — and every one of those files parses and round-trips.

Files:

```
rst/  Rst.jl · RstParser.jl · RstToSyntax.jl · RstFile.jl
```

The slice depends on no other domain slice.

## The document

`RstModule` holds about forty `@document` structs in three groups.

**Inlines** — `RstText`, `RstLiteral`, `RstEmphasis`, `RstStrong`, `RstRole`,
`RstReference`, `RstSubstitutionReference`, `RstFootnoteReference`.

**Blocks** — `RstSection`, `RstParagraph`, `RstLiteralBlock`, `RstLineBlock`,
`RstBulletList`, `RstEnumeratedList`, `RstListItem`, `RstDefinitionList`,
`RstDefinitionItem`, `RstFieldList`, `RstField`, `RstBlockQuote`,
`RstTransition`, `RstComment`, `RstTarget`, `RstSubstitutionDefinition`,
`RstFootnote`, `RstGridTable`, `RstTableRow`, `RstTableCell`, `RstRoot`.

**Directives** — twelve typed structs plus one generic fallback.

### Sections nest, the source does not

RST writes a section as a title line under an adornment line, and the
adornment character alone decides the depth. RST gives no fixed meaning to any
character: the order in which a file first uses one decides what it means
there.

The document is a tree instead. A section owns every block below it, so it can
be collapsed and moved as a unit. `RstSection.adornment` keeps the character
the file used, so emit reproduces that file's own convention rather than
imposing one.

### Directives are typed where it pays

The twelve directives that carry meaning for the natural notation get their
own struct with named fields: `RstLiteralInclude`, `RstFigure`,
`RstCodeBlock`, `RstImage`, `RstVideo`, `RstAudio`, `RstAdmonition`,
`RstToctree`, `RstMathBlock`, `RstRawBlock`, `RstRoleDefinition`. Everything
else is an `RstDirective` with a name, an argument and an option list.

The reason is the rendered view: a figure has to find its picture, a code
block its language, an admonition its kind. Searching an option vector by
string on every read would be the alternative.

A typed directive still carries `extra`, the options it does not name, so emit
loses nothing. In the INET corpus the typed structs cover 2099 of the 2114
directive uses; the generic struct catches the other 15.

### Roles hold a plain string

`:ned:`Foo`` has no nested markup, so `RstRole.content` is a `String`. The name
is a string too: the role set is open, because a document declares its own
with `.. role::`. The projection maps the name to a colour through a table and
falls back to a neutral colour for a name it does not know.

## The parser

`parse_rst(text)` and `parse_rst_file(path)`. Pragmatic, not docutils, but it
covers the corpus.

The block reader takes a line vector that its caller already dedented to
column zero, and tries ten constructs in order. A construct that owns an
indented body — a directive, a list item, a definition — dedents that body and
hands it back to the same reader, so nesting needs no special case.

Sections come out flat, as title markers. One pass afterwards assigns the
depths by order of first use and builds the tree.

### Two rules that are easy to get wrong

**A paragraph joins its lines with a space, not a newline.** RST reflows a
paragraph freely, so where the author broke the line carries no meaning. A
stored newline would emit a line starting at column zero, which ends the list
item or the directive body the paragraph sits in.

**Inline markup obeys the start-string and end-string rules.** A start-string
must be followed by a non-blank, an end-string preceded by one. Without those
two rules `*.host.numApps = 1` — which the corpus writes in running prose —
opens an emphasis span. A reference gets its own end finder, because its
closing backquote is followed by the `_` that belongs to its marker.

## The projection

`RstToSyntax(; style)` builds a `TypeDispatchingProjection`. `style` is
`:source` or `:rendered`, the same two words `MarkdownToSyntax` uses.

The rendered table is built from the source table by replacing the rules whose
presentation differs, so a rule that reads the same either way is written once.

### `:source` — the original syntax

Colourised raw RST with every marker on the page and every one-line field
editable.

### `:rendered` — the natural notation

No markers. Large bold titles, real bold and italic, a role as a chip coloured
by what it names, a figure as the picture itself, `•` bullets, a `────` rule.

Every directive says what it means rather than how it is spelled:

| Directive | The natural notation |
| --- | --- |
| `.. figure::` | the picture, with its caption under it |
| `.. code-block:: ini` | the code alone, indented — the language names a colouring rule, not something the reader needs |
| `.. note::` | the word `Note` over an indented body |
| `.. toctree::` | the word `Contents` over the entries; `:maxdepth:` is a build setting and goes |
| `.. literalinclude::` | one line — `↳ path (language, from … to)` — instead of four option lines |

An enumerated list counts properly here. The source view prints the list's own
start number on every item, because a templated item cannot know its index and
RST renumbers on render anyway; the natural notation *is* the render, so
`RstEnumeratedListToStyledNode` builds its items by hand, where the index is
in hand.

**Glyphs come from DejaVu.** SDL does not fall back between fonts: a glyph the
chrome font lacks arrives as an empty box. Ubuntu Mono has `•` but not `↳`, so
the rules that draw an arrow name `font_dejavu_monospace_regular_20`.

Bold, italic and a section title change the font of every descendant text run,
which travels as an ambient `:rst_style` in the printer context: a container
augments it and delegates, the leaf reads it. That is the School A pattern
`MarkdownToSyntax` uses for the same job.

### Indentation is written, not computed

Every compound here carries `indentation=0` and puts the indent into its own
`open` and `sep` text, and the current column travels as an ambient
`:rst_indent`. A container that owns an indented body pushes a deeper indent;
every rule that writes a newline reads the ambient and puts it after the
newline.

The compound's own `indentation` field cannot do this job. It writes a newline
before the *first* child as well as between children, and it always costs one
indent level — so a list's items would leave their marker column, and a
definition's body could not sit on the line after its term.

`@projection_template` builds a printer from `(prj, doc)` alone and never sees
the context, so two macros in the file — `@rst_flat` and `@rst_indented` —
wrap `print_template_rule`, the entry point the template macro itself uses, and hand
the builder the ambient as well. A rule keeps its template body; only its
signature grows.

### Seven opaque bodies

The body of a code block, a literal include, a literal block, a math block, a
raw block, a comment and a grid table is multi-line text that has to be
indented under its marker. A `bound` leaf maps a text splice back by offset,
and pre-indenting the render would shift every offset past the first line. So
these seven render through a plain computed `TextString`: correct on the page
and correct on save, but not splice-editable in the source view. Every other
field is `bound`.

## The file document

`RstFile <: FileDocument` wraps an `RstDocument`. The module registers
`natural_syntax_projection` / `natural_extension` / `parse_natural`, and
`.rst` as a file document type, so `import_document`, `export_document` and
`document_to_text` all reach the slice by extension.

`find_rst_section(document, title)` finds a section by the plain text of its title.
Unlike the markdown counterpart it returns the node itself, because an RST
section already owns its blocks. It is also the slice's method of
`get_document_section`, the generic behind the `section(…)` marker verb, so
`<<section(file("page.rst"), "Title")>>` embeds a section of a page.

## Embedding another document

A cross-file reference reads as a directive whose argument is the marker:

```
.. pred-ref:: <<file("child.json")>>
```

The directive needs no parser rule. A name the parser does not know already
becomes an `RstDirective` carrying its name and its argument, and emit writes it
back unchanged. Load walks the block tree for a `pred-ref` directive whose
argument parses as a marker and rewrites each into a `ReferenceStub`; a
`pred-ref` whose argument is not a marker stays the directive it was, so a typing
mistake shows on the page instead of vanishing.

**Save is by marker, never by content.** `document_to_text` runs `RstToSyntax`
alone, whose table renders a stub and an embedded file document as the directive
they were written as. Reading is the other projection: the natural renderer
prints an embed as the document it embeds, in that document's own domain.

### A page is a stack of blocks

`RstToLayout.jl` rewraps an `RstRoot` **and** an `RstSection` into a
`VerticalLayout`, so each block renders in its own domain rather than joining one
syntax tree. That is what lets an embed be a widget: the card an embedded
document wears is a `WidgetCard`, and a widget squeezed through a syntax tree
would arrive as reflected text and would never see a click.

Markdown needs only the root rewrap, because a markdown page is flat. An RST
section owns its blocks, so without the section rule every embed below the first
title would still sit inside a syntax tree.

The rewrap moves the blocks without touching them, so the reference maps only
relocate the head: `elements[i] + rest ↔ children[i] + rest`, shifted by one in a
section, where the title takes the first slot.

## Testing

- `test_rst_parser()` — unit tests, one construct at a time.
- `test_rst_round_trip()` — the five fixtures in
  `package/projectured/test/fixture/rst/`, copied from the INET documentation.
- `test_rst_corpus(dir)` — an opt-in sweep of a whole documentation tree, not
  wired into `test_domain()` because the tree is not a dependency of this
  repository. Point it at a checkout:

  ```julia
  test_rst_corpus("/path/to/inet")
  ```

- `test_example(rst_example)` and `test_printer(rst_rendered_example)` for the
  two projections.
- `test_rst_embed()` — the `pred-ref` directive, the card an embedded document
  wears, and the save-by-marker invariant.

### The round-trip criterion is AST idempotence

`parse_rst(document_to_text(parse_rst(text)))` must equal `parse_rst(text)`.

Byte equality is not required and is not reached: a paragraph is rejoined onto
one line, an adornment is redrawn at the title's width, and a directive body
is re-indented to three spaces. What must hold is that reading an emitted file
gives back the document it came from. All 349 INET files satisfy it.

## Known limits

- **`literalinclude` does not resolve.** The projection shows the reference and
  its slice bounds; it does not read the file or apply `start-at` / `end-at`.
  Doing so needs a loader context, which is the `FileProject` seam.
- **`include` does not resolve**, for the same reason.
- **Sphinx role semantics.** A `:ned:` role does not resolve to a NED type and
  a `:doc:` role does not resolve to a page. A role is a styled string.
- **The source view prints an enumerated list's start number on every item.**
  An item does not know its index, and a re-parse recovers the same list, so
  nothing is lost on save — but a list starting at a number other than one
  loses that start. The rendered view counts properly.
- **`RstSectionToStyledNode` has no reference mappers.** The rendered section
  prints, but a selection does not map through it, so navigating the rendered
  view stops at a section boundary. The source view maps fully. The layout
  rewrap that the natural renderer uses does map a section's blocks.
- **A rewrapped section's title is flat.** `RstSectionToVerticalLayout` draws the
  title as one prose line in the level's font, with inline markup flattened to
  its text, because a layout child cannot receive the ambient `:rst_style` the
  syntax rule carries. A selection maps through the section's blocks but not into
  its title.
- **The rendered grid table keeps the drawn grid** rather than laying the
  cells out as a real table.
- **A figure path is resolved against the process working directory,** not
  against the file the figure came from, because the slice has no document
  directory to resolve against — that is the same loader seam `literalinclude`
  waits on. A path that does not resolve degrades to the path as text.
- **An inline marker is not read.** A `pred-ref` directive is a block. A marker
  written in a line of prose stays text: the markdown slice splits its text runs
  around one, and this slice has no counterpart yet.
