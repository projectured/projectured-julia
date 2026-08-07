# RST domain slice

Add an `rst` feature slice to `ProjecturedDomain`. The slice must parse the
reStructuredText files of `inet-cpp`, hold them in `@document` structs, and
project them two ways: the original RST syntax, and a natural notation that
hides the markup.

Status: **pending**. No code exists yet.

## 1. Goal

1. Parse every `.rst` file of `/home/projectured/workspace/inet-cpp`.
2. Represent the result in `@document` structs, so the editor can select and
   edit every part.
3. Project the document to syntax in two styles:
   - `:source` — the original RST text, colourised. Every marker is editable.
     This is also the save path.
   - `:rendered` — natural notation. Section titles are large and bold, a
     figure shows the real picture, an admonition is a box, a role is a styled
     chip. No markup characters.
4. Register `.rst` as a file document, so `document_to_text` and the file
   loader work.

The `markdown` slice is the model to copy. It has the same shape: a document
module, a parser, a two-style `ToSyntax` projection, and a `FileDocument`
wrapper. Every name below follows the markdown name, one for one.

| Markdown | RST |
| --- | --- |
| `MarkdownModule`, `MarkdownDocument` | `RstModule`, `RstDocument` |
| `markdownparse`, `markdownparse_file` | `rstparse`, `rstparse_file` |
| `MarkdownToSyntax(; style=:source \| :rendered)` | `RstToSyntax(; style=:source \| :rendered)` |
| `MarkdownFile` | `RstFile` |
| `make_markdown_projection_example` | `make_rst_projection_example` |
| `make_markdown_rendered_projection_example` | `make_rst_rendered_projection_example` |
| `markdown_example`, `markdown_rendered_example` | `rst_example`, `rst_rendered_example` |
| `MarkdownToLayout.jl` | deferred — see section 10 |

## 2. The corpus

Numbers from `/home/projectured/workspace/inet-cpp`, measured on 2026-08-07.

- 349 files, 50943 lines.
- The largest file is `doc/src/users-guide/ch-network-autoconfig.rst` at 38 kB.

### Directives

| Directive | Count | Directive | Count |
| --- | ---: | --- | ---: |
| `literalinclude` | 733 | `code` | 6 |
| `figure` | 668 | `raw` | 5 |
| `code-block` | 339 | `warning` | 4 |
| `video` | 127 | `math` | 4 |
| `note` | 118 | `audio` | 4 |
| `toctree` | 45 | `table` | 2 |
| `video_noloop` | 15 | `only` | 2 |
| `image` | 13 | `important` | 2 |
| `todo` | 11 | `graphviz` | 2 |
| `role` | 11 | `list-table` | 1 |
| | | `include` | 1 |
| | | `caution` | 1 |

### Directive options

`language` 726, `width` 582, `start-at` 508, `end-before` 343, `align` 602,
`end-at` 272, `start-after` 138, `name` 116, `maxdepth` 46, `diff` 14,
`height` 13, `scale` 10, `emphasize-lines` 8, `class` 7, `lines` 6, `glob` 6,
`format` 4, `alt` 2, `titlesonly` 1.

### Inline roles

`ned` 2381, `par` 756, `download` 512, `cpp` 373, `protocol` 124, `doc` 92,
`math` 81, `fun` 56, `var` 55, `file` 29, `msg` 27, `ini` 24, `gate` 21,
`ref` 9, `guilabel` 6, `sub` 5, `menuselection` 4, `raw-latex` 3, `command` 1.

The project defines its own roles in `doc/src/global.rst` with `.. role::`.
The parser does not need to know the role names. It keeps the name as a
string. The projection maps the name to a style through a table.

### Other constructs

- Section adornments use `=`, `-`, `~`, `^`, `+`, `*`, `#`.
- 3883 inline literals (`` ``x`` ``), 640 strong spans, many emphasis spans.
- 271 hyperlink references (`` `text <url>`_ ``).
- 419 internal targets (`.. _ug:cha:queueing:`).
- 337 comments.
- 523 enumerated list lines, about 1700 bullet list lines.
- 187 line block lines (`| …`).
- 111 literal blocks introduced by `::`.
- About 567 definition list candidates.
- 10 files hold a grid table. No file holds a simple table.
- 4 substitution definitions, 3 footnotes.

## 3. Document model — `rst/Rst.jl`

Module `RstModule`. Abstract root `RstDocument <: Document`. Every struct uses
`@document`. A struct that holds a child sequence gets
`@forward_vector_protocol`.

Keep the `@document` constructor rule in mind. A struct with at least one
required field gets positional constructors. A struct with no required field
gets the `Foo([...])` sugar instead. Order the fields so the sequence field
reaches the `CellVector`-wrapping constructor, as `MarkdownList` does.

### Cursor

- `RstInsertion(value::Any = nothing)`

### Inline nodes

- `RstText(content::String)`
- `RstLiteral(content::String)` — `` ``x`` ``

  `RstText` and `RstLiteral` hold one string, as `MarkdownText` and
  `MarkdownCode` do. Give each one the same four methods that
  `MarkdownModule` gives its string leaves: `Base.getindex`,
  `Base.setindex!`, `set_cell_function!`, and `set_cell_value!`.

- `RstEmphasis(content::CellVector)` — `*x*`
- `RstStrong(content::CellVector)` — `**x**`
- `RstRole(name::String, content::String)` — `:ned:`Foo``. A role body holds
  no nested markup, so a plain string is enough.
- `RstReference(text::String, target::String, anonymous::Bool = false)` —
  `` `text <url>`_ `` and `` `name`_ ``. An empty `target` means a named
  reference to a target defined elsewhere.
- `RstSubstitutionReference(name::String)` — `|name|`
- `RstFootnoteReference(label::String)` — `[#]_`

### Block nodes

- `RstSection(level::Int, adornment::String, title::CellVector, elements::CellVector, collapsed::Bool = false)`
  The document tree is nested even though the RST source is flat. `adornment`
  keeps the character the file used, so emit reproduces the file's style.
- `RstParagraph(content::CellVector)`
- `RstLiteralBlock(content::String)` — the indented block after `::`
- `RstLineBlock(lines::CellVector)` — each line is an `RstParagraph`
- `RstBulletList(marker::String, items::CellVector, collapsed::Bool = false)`
- `RstEnumeratedList(style::String, items::CellVector, collapsed::Bool = false)`
  `style` is `"1."` or `"1)"`.
- `RstListItem(elements::CellVector, collapsed::Bool = false)`
- `RstDefinitionList(items::CellVector)`
- `RstDefinitionItem(term::CellVector, elements::CellVector)`
- `RstFieldList(fields::CellVector)`
- `RstField(name::String, elements::CellVector)`
- `RstBlockQuote(elements::CellVector, attribution::String = "")`
- `RstTransition()`
- `RstComment(content::String)`
- `RstTarget(name::String)` — `.. _ug:cha:queueing:`
- `RstSubstitutionDefinition(name::String, body::RstDocument)`
- `RstFootnote(label::String, elements::CellVector)`
- `RstGridTable(header_rows::Int, rows::CellVector)`
- `RstTableRow(cells::CellVector)`
- `RstTableCell(elements::CellVector)`
- `RstRoot(elements::CellVector, collapsed::Bool = false)`

### Directives

Give the frequent directives their own struct. Give the rest one generic
struct. The natural notation needs named fields. A picture needs a path, a
code block needs a language, an admonition needs a kind. A generic option
vector would force the projection to search a vector by string on every read.

Every typed directive also carries `extra::CellVector` of
`RstDirectiveOption(name::String, value::String)`. The parser puts every
option it does not name into `extra`, so emit loses nothing.

- `RstLiteralInclude(path::String, language::String, start_at::String, end_at::String, start_after::String, end_before::String, extra::CellVector, collapsed::Bool = false)`
- `RstFigure(path::String, align::String, width::String, caption::CellVector, extra::CellVector)`
- `RstCodeBlock(language::String, code::String, extra::CellVector, collapsed::Bool = false)`
- `RstVideo(path::String, width::String, height::String, loop::Bool, extra::CellVector)`
  `.. video_noloop::` sets `loop` to `false`.
- `RstImage(path::String, width::String, height::String, alt::String, extra::CellVector)`
- `RstAudio(path::String, extra::CellVector)`
- `RstAdmonition(kind::String, elements::CellVector, collapsed::Bool = false)`
  Covers `note`, `warning`, `important`, `caution`, `todo`.
- `RstToctree(maxdepth::Int, titlesonly::Bool, glob::Bool, entries::CellVector, extra::CellVector)`
  Each entry is an `RstText`.
- `RstMathBlock(content::String)`
- `RstRawBlock(format::String, content::String)`
- `RstRoleDefinition(name::String, base::String, extra::CellVector)`
- `RstDirective(name::String, argument::String, options::CellVector, elements::CellVector, collapsed::Bool = false)`
  The generic fallback. It catches `only`, `graphviz`, `table`, `list-table`,
  `include`, and `code`.

The typed structs cover 2099 of the 2114 directive uses. The generic struct
catches the other 15.

## 4. Parser — `rst/RstParser.jl`

Module `RstParserModule`. Exports `rstparse(text)` and `rstparse_file(path)`.
Follow `MarkdownParserModule`: pragmatic, not specification-conformant, but
enough for the corpus.

RST is indentation-driven. Write a block reader that takes a line range and an
indent column, and returns a `Vector{RstDocument}`.

1. Skip a blank line.
2. If the line starts with `.. `, read explicit markup.
   - `.. name:: argument` — a directive. Read the option lines
     (`   :name: value`), then the blank line, then the indented body.
     Dispatch on `name` to the typed struct or to `RstDirective`.
   - `.. _name:` — an `RstTarget`.
   - `.. |name| directive::` — an `RstSubstitutionDefinition`.
   - `.. [label]` — an `RstFootnote`.
   - Anything else — an `RstComment`.
3. If the next line is an adornment line of `=`, `-`, `~`, `^`, `+`, `*`, or
   `#`, and it is at least as long as this line, this line is a section title.
4. If the line starts with `| `, read an `RstLineBlock`.
5. If the line starts with `- `, `* `, or `+ `, read an `RstBulletList`.
6. If the line starts with `1.` or `1)`, read an `RstEnumeratedList`.
7. If the line starts with `+---`, read an `RstGridTable`.
8. If the line matches `:name: value`, read an `RstFieldList`.
9. If the line is unindented and the next line is indented, read an
   `RstDefinitionList`.
10. Otherwise read a paragraph up to the next blank line. If the paragraph
    ends with `::`, the following indented block is an `RstLiteralBlock`.

**Section nesting.** RST gives no fixed meaning to an adornment character. The
parser keeps a stack of the characters it has seen. A character already on the
stack closes back to that level. A new character opens one level deeper. Store
the character in `RstSection.adornment`.

**Inline parsing.** Scan the character vector once. Test the delimiters in this
order, because a later one can appear inside an earlier one:

1. ``` ``literal`` ```
2. `` :role:`content` ``
3. `**strong**`
4. `*emphasis*`
5. `` `text <url>`_ `` and `` `name`_ ``
6. `|substitution|`
7. `[label]_`

An unclosed delimiter degrades to literal text, as the Markdown parser does.

## 5. Projection — `rst/RstToSyntax.jl`

Module `RstToSyntaxModule`. One entry point:

```julia
RstToSyntax(; style::Symbol = :source)
```

It returns a `TypeDispatchingProjection`, exactly as `MarkdownToSyntax` does.
`style` is `:source` or `:rendered`.

**On the style name.** The natural notation is `:rendered`, the same word
`MarkdownToSyntax` uses for the same thing. Do not call it `:natural`. The word
`natural` already means the opposite in this repository:
`natural_syntax_projection` returns the **source** projection, because "natural
format" means the file text format. `YamlToSyntax(; style)` is a different
axis, `:block` against `:flow`, and is not a precedent here.

Write every rule with `@projection_template` where possible, so the reader
comes from the wiring. Hand-write only the rules that must cascade a style to
their children.

### `:source` — the original syntax

Colourised raw RST. Every marker is an editable text span.

- A section prints the title, a newline, and the adornment line repeated to the
  title length.
- A role prints `:name:` in grey and the content in the role's colour.
- A directive prints `.. name:: argument`, then one line per option, then the
  indented body.
- An inline literal prints its backquotes.
- Blocks stack flush-left with `indentation=0` and a newline separator, the
  `BookToSyntax` idiom that `MarkdownToSyntax` follows.

### `:rendered` — the natural notation

No markup characters.

- A section title is large and bold. The size follows the level, as
  `MarkdownHeadingToStyledNode` does.
- `RstStrong` and `RstEmphasis` cascade a font weight or slant to their
  descendant text through the ambient `:md_style` mechanism of the printer
  context. Copy the School A pattern of `MarkdownToSyntax`: a container only
  augments the ambient style, and the leaf reads it.
- `RstLiteral` is plain monospace, no backquotes.
- `RstRole` renders as a styled chip. A table maps the role name to a colour
  and a font: `ned` and `gate` in one colour, `cpp`, `var`, and `fun` in
  another, `par` and `ini` in a third, and so on.
- `RstFigure` and `RstImage` show the real picture. Use `ImageFile` and
  `decode_image`, as `MarkdownImageToStyledNode` does. The caption sits below
  in a smaller font.
- `RstCodeBlock` is an indented monospace block with no `.. code-block::`
  line.
- `RstAdmonition` is a box with the kind as a bold label.
- `RstToctree` is a list of links.
- `RstLiteralInclude` shows the path and the slice bounds as a compact header
  over an empty body. Reading the referenced file is out of scope. See
  section 9.
- `RstTransition` is a horizontal rule.
- `RstComment` and `RstTarget` are hidden or dimmed.

**The rendered pipeline word-wraps.** `make_markdown_rendered_projection_example`
inserts `WordWrapping(measure=measure)` between `SyntaxToText()` and
`TextToGraphics`, because rendered prose must wrap. The source pipeline does
not, because source lines are already broken by the file. Copy both
pipelines exactly.

## 6. File document — `rst/RstFile.jl`

Copy `MarkdownFile.jl`.

- `@document struct RstFile <: FileDocument` with `filename::String` and
  `content::RstDocument = RstRoot()`.
- `emit_text(f::RstFile) = document_to_text(content(f))`.
- `populate_file!` reads the file and calls `rstparse`.
- Register the natural format:
  - `natural_syntax_projection(::RstDocument) = RstToSyntax()`
  - `natural_extension(::RstDocument) = ".rst"`
  - `parse_natural(::Val{:rst}, text) = rstparse(text)`
- `register_file_document_type!(".rst", RstFile)`.

A cross-file marker convention is not needed for the inet corpus. Skip it for
now. If it becomes necessary, use an `RstComment` whose content starts with
`pred-ref`, which is the analogue of the Markdown fenced block.

## 7. Examples and tests

### Examples

- `package/domain/example/document/Rst.jl`
  - One atom per struct, for the catalog, in the style of
    `document/Markdown.jl`.
  - `make_rst_document_example()` — a compact document that uses a section
    tree, a paragraph with a `:ned:` role and an inline literal, a bullet
    list, a `code-block`, a `figure`, a `note`, and a `literalinclude`. Base
    it on a real showcase file.
- `package/domain/example/projection/Rst.jl` — copy
  `example/projection/Markdown.jl` line for line, including the
  `measure=truetype_measure_text` keyword.

  ```julia
  function make_rst_projection_example(; measure=truetype_measure_text)
      ChainingProjection(
          RecursiveProjection(RstToSyntax()),
          RecursiveProjection(SyntaxToText()),
          TextToGraphics(measure=measure),
      )
  end

  function make_rst_rendered_projection_example(; measure=truetype_measure_text)
      ChainingProjection(
          RecursiveProjection(RstToSyntax(; style=:rendered)),
          RecursiveProjection(SyntaxToText()),
          WordWrapping(measure=measure),
          TextToGraphics(measure=measure),
      )
  end
  ```

- In `package/domain/example/Examples.jl`, add
  `const rst_example = Example("rst", make_rst_document_example, make_rst_projection_example)`
  and `const rst_rendered_example = Example("rst_rendered", make_rst_document_example, make_rst_rendered_projection_example)`,
  then list both in the example vector.
- Add one `AtomicDocument(:rst, "<name>", make_rst_<name>_document_example)`
  per struct to `domain_atomic_documents` in the same file.
- Add the `include` lines and the `export` lines to
  `package/domain/example/ProjecturedDomainExample.jl`, beside the markdown
  ones.

### Tests

- `test_printer(rst_example)`, `test_reader(rst_example)`,
  `test_position_navigation(rst_example)`, `test_repl(rst_example)`.
- A parser round-trip test on a fixture folder. Copy 5 representative files
  from `inet-cpp` into `package/domain/test/fixture/rst/`:
  - `showcases/tsn/framereplication/manualconfiguration/doc/index.rst` —
    sections, figures, `literalinclude`, bullet and enumerated lists, a line
    block.
  - `doc/src/users-guide/ch-queueing.rst` — a long chapter with targets, many
    `:cpp:` and `:ned:` roles, and definition-like lists.
  - `showcases/index.rst` — a `toctree`.
  - `showcases/wireless/txop/doc/index.rst` — a grid table.
  - `doc/src/global.rst` — `.. role::` definitions.
- **Round-trip criterion.** Do not require byte equality. The corpus writes an
  adornment line that is sometimes longer than its title, and it uses a mix of
  two-space and three-space indents. Require **AST idempotence** instead:
  `rstparse(document_to_text(rstparse(text)))` must equal `rstparse(text)`.
  Report the number of files whose emitted text also matches byte for byte, as
  a quality figure, but do not assert it.
- An opt-in corpus sweep, not wired into the aggregator:
  `test_rst_corpus(dir)` parses every `.rst` under `dir` and reports the files
  that fail to parse or that fail idempotence. The `inet-cpp` repository is not
  a dependency of this repository, so the aggregator must not need it.

## 8. Wiring

- Create the folder `package/domain/main/rst/`.
- Add to `package/domain/main/ProjecturedDomain.jl`, next to the markdown
  entries:
  - `include("rst/Rst.jl")` in the document group.
  - `include("rst/RstParser.jl")` in the parser group.
  - `include("rst/RstToSyntax.jl")` and `include("rst/RstFile.jl")` after
    `markdown/MarkdownFile.jl`.
- The `rst` slice has no cross-slice edge. It stays independent in the slice
  DAG, so the layering guard `test_domain_layering()` needs no change.
- Add the slice to the folder list in
  [package/domain/doc/architecture.md](../../package/domain/doc/architecture.md).
- Write [package/domain/doc/rst.md](../../package/domain/doc/rst.md), a per-slice
  guide in the style of `json.md`.

## 9. Steps

Do the work in a dedicated git worktree. Commit after each step.

1. **Fixtures.** Copy the 5 files into `package/domain/test/fixture/rst/`.
   Write `test_rst_corpus(dir)` as a stub that only counts files.
2. **Document model.** Write `rst/Rst.jl`. Write the atoms in
   `example/document/Rst.jl`. Register them in the catalog. Check that the
   catalog tests pass.
3. **Parser, block level.** Write `rst/RstParser.jl` for sections,
   paragraphs, lists, literal blocks, comments, targets, transitions, and
   directives. Inline parsing returns one `RstText` for now. Check that the 5
   fixtures parse.
4. **Parser, inline level.** Add the 7 inline forms. Check the fixtures again.
5. **Source projection.** Write the `:source` half of `rst/RstToSyntax.jl`.
   Add `rst_example`. Run `test_example(rst_example)`.
6. **Round-trip.** Add the idempotence test. Fix the parser and the printer
   until the 5 fixtures pass.
7. **File document.** Write `rst/RstFile.jl`. Register `.rst`. Check that
   `document_to_text` works on a parsed fixture.
8. **Rendered projection.** Write the `:rendered` half. Add
   `rst_rendered_example`. Run `test_example(rst_rendered_example)`.
9. **Corpus sweep.** Run `test_rst_corpus("/home/projectured/workspace/inet-cpp")`
   over all 349 files. Fix every parse failure and every idempotence failure.
   Record the final pass count in this plan.
10. **Documentation.** Write `package/domain/doc/rst.md`. Update
    `package/domain/doc/architecture.md`. Move this plan to `plan/done/`.

## 10. Deferred

These are out of scope. Record them here so the next person does not look for
them.

- **`literalinclude` resolution.** The projection does not read the referenced
  file and does not apply `start-at` / `end-at`. It shows the reference. To
  resolve it, the slice needs a loader context, which is the `FileProject`
  seam.
- **`include` directive.** The same reason. Only 1 use in the corpus.
- **Sphinx role semantics.** A `:ned:` role does not resolve to a NED type, and
  a `:doc:` role does not resolve to a page. The role is a styled string.
- **`only::` conditional builds.** The document keeps both branches.
- **Simple tables, option lists, citations, doctest blocks.** The corpus uses
  none of them.
- **Auto-numbered footnotes.** The corpus has 3 footnotes. The label stays a
  string.
- **Byte-exact emit.** See the round-trip criterion in section 7.
- **`RstToLayout.jl`.** The markdown slice has a fifth file,
  `MarkdownToLayout.jl`, which rewraps a `MarkdownRoot` into a
  `VerticalLayout` so a page is a stack of blocks. It exists only for embeds:
  an embedded document that is a widget must not pass through a syntax tree,
  or it arrives as reflected text and never sees a click. The inet corpus has
  no embed, so the RST slice does not need the file yet. Add it when a
  `literalinclude` starts to resolve into a live document, which is the same
  seam as the first deferred item.
