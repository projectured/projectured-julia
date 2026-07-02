# Markdown domain

Add a Markdown document domain to ProjecturEd, following the JSON/XML pattern:
a domain, a `@projection_template`-based projection to Syntax, a parser, and an
example.

## Status

- [x] Domain: `package/domain/src/document/Markdown.jl` (`MarkdownModule`) — done in a
      previous step; wired into `ProjecturedDomain.jl`.
- [x] Projection: `package/domain/src/projection/primitive/MarkdownToSyntax.jl`
- [x] Parser: `package/domain/src/parser/MarkdownParser.jl`
- [x] Example: `package/example/src/document/Markdown.jl` +
      `package/example/src/projection/Markdown.jl`, registered as `markdown_example`.
- [x] Wiring: includes in `ProjecturedDomain.jl` (projection + parser) and
      `ProjecturedExample.jl` (example files, Examples.jl registration + export).
- [x] LLM assistant hookup: `markdown`/`md` added to `_code_part`'s recognized
      fence languages (`WorkbenchAssistant.jl`) so an assistant ```` ```markdown ````
      block parses to a `MarkdownRoot` content part; `MarkdownDocument` rendering
      wired into the conversation/assistant projection dispatch
      (`_conversation_widget_graphics` + `make_conversation_projection_example`);
      `_MARKDOWN_TO_TEXT` + `_doc_source`/`_block_text(::MarkdownDocument)` for
      round-trip serialization back to the model.

## Verified

Precompiles clean. `test_printer` + `test_reader` + `test_text_navigation` on
`markdown_example` and `test_parse_markdown_blocks` — **2632 pass / 0 fail / 0
error**. The template-derived reader is fully bidirectional (test_reader green),
and the assistant ```` ```markdown ```` fence yields a `MarkdownRoot` part.

## Design decisions

### Projection (`MarkdownToSyntax`) — `@projection_template` throughout

Every rule is a `@projection_template` builder. Mapping to proven template shapes:

| Markdown node        | Syntax shape                                             | Template feature |
|----------------------|----------------------------------------------------------|------------------|
| `MarkdownInsertion`  | opaque leaf `insert markdown here`                       | opaque leaf (JsonInsertion) |
| `MarkdownText`       | `bound(:content)` leaf                                   | bound leaf (JsonString) |
| `MarkdownCode`       | `bound(:content)` leaf, `` ` `` open/close               | bound leaf w/ delimiters |
| `MarkdownThematicBreak` | opaque leaf `---`                                     | opaque leaf |
| `MarkdownEmphasis`   | `collection(:content)` node, `*`/`*`                     | homogeneous collection (JsonArray) |
| `MarkdownStrong`     | `collection(:content)` node, `**`/`**`                   | homogeneous collection |
| `MarkdownParagraph`  | `collection(:content)` node, inline (sep="")             | homogeneous collection |
| `MarkdownHeading`    | `collection(:content)` node, reactive open `"#"^level*" "` | collection + reactive open marker |
| `MarkdownQuote`      | `collection(:elements)` node, `> ` prefix                | homogeneous collection |
| `MarkdownList`       | `collection(:items)` node, newline sep                   | homogeneous collection |
| `MarkdownListItem`   | `collection(:elements)` node, `- ` bullet                | homogeneous collection |
| `MarkdownRoot`       | `collection(:elements)` node, `\n\n` sep, indentation=0  | homogeneous collection (BookBook flush-left) |
| `MarkdownLink`       | fixed node `[content](url)`                              | `[SubNodeSlot(collection(:content)), KeySlot(bound(:url))]` (JuliaCall shape) |
| `MarkdownImage`      | fixed node `![alt](url)`                                 | `[KeySlot(bound(:alt)), KeySlot(bound(:url))]` |
| `MarkdownCodeBlock`  | fixed node ```` ```lang\ncode\n``` ````                  | `[KeySlot(bound(:language)), KeySlot(bound(:code))]` |

The template auto-derives the reader (selection forward/backward + string-replace
type-in) from the wiring, so no hand-written `map_reference_*`/`projection_read`.

Block stacking uses `indentation=0` + newline `sep` (the `BookBookToSyntaxNode`
"flush-left prose blocks" idiom), not bracket-style indentation.

### v1 deferrals (documented, not bugs)
- **Heading `level`**: rendered as a decorative reactive `open` marker (`## `), not
  an editable bound field. Editing the level via the projection is deferred; the
  parser sets it.
- **Ordered lists**: `MarkdownList.ordered` is not reflected in the rendering — both
  ordered and unordered render with `- ` bullets (the collection element builder has
  no index). Numbered rendering (`1.`) is deferred.
- **Authoring gestures**: no `@gestures` (structural inserts / type-to-replace of the
  insertion cursor). Printing, reading, selection and character type-in all work via
  the template-derived reader; structural authoring is a follow-up.
- **`collapsed`**: not wired to the syntax node's collapse mechanism yet.

### Parser (`MarkdownParser`, `markdownparse`)
Pragmatic (non-conformance) recursive/line-based parser → `MarkdownRoot`:
- Blocks: ATX headings (`#`..`######`), fenced code (```` ``` ````), thematic break
  (`---`/`***`/`___`), blockquote (`>`), lists (`-`/`*`/`+`, `1.`), paragraphs
  (consecutive non-blank lines merged).
- Inline: `` `code` ``, `**strong**`, `*emphasis*`, `![alt](url)`, `[text](url)`,
  plain text runs. Unmatched delimiters degrade to literal text.

Mirrors `JsonParser`'s `_Cur` cursor style for the inline scanner.
