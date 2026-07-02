# Rendered ("beautiful") Markdown projection

## Goal

A second Markdown presentation that renders **formatted output** — no visible
syntax markers (`#`, `**`, `*`, backticks, `[]()`, ` ``` `, `>`, `-`, `---`).
Instead:

- Headings → large **bold** text, size decreasing by level.
- `**bold**` → bold font; `*italic*` → italic font (markers gone).
- `` `code` `` → monospace, subtle colour/background, no backticks.
- `[text](url)` → the link *text* in a link colour (URL optionally as a tooltip).
- `![alt](url)` → the actual decoded image (falling back to the alt text).
- fenced code block → a monospace block, no fences, indentation preserved.
- blockquote → left-indented / left-barred gray text, no `>`.
- lists → real bullet glyphs (`•`) / numbers, indented; no `-`/`1.` literals.
- thematic break → a horizontal rule, not `---`.
- paragraphs → flowing, word-wrapped prose.

The existing `MarkdownToSyntax` (the **source view** — colourised raw markdown,
fully editable including the markers) stays exactly as is. This plan adds the
*rendered* view alongside it.

## Decision: a `style` parameter, mirroring `YamlToSyntax(; style)`

I first recommended separate projections (structural difference), but the sibling
YAML feature shipped just before this (`YamlToSyntax(; style=:block|:flow)`) set
the house pattern, and **the user chose to match it**, with the refinement: *swap
per-type sub-projections rather than branch inside the template builders — reuse a
type's projection where it renders identically, replace it where it differs*.

So: **`MarkdownToSyntax(; style::Symbol = :source | :rendered)`** assembles a
`TypeDispatchingProjection` choosing, per node type, the source or rendered
handler. There are **no `if style` conditionals inside any builder** — the choice
is made once, at assembly time, exactly like YAML. Three mechanisms, per type:

1. **Reuse** the same projection unchanged where source == rendered:
   `Insertion`, `Paragraph`, `Root`, `List`, `CodeBlock`, `Image`.
2. **Field-parameterise** (add fields with source defaults; the rendered
   constructor passes different values — YAML's `open/close/sep/indent` trick):
   `Code` (`tick` `` ` ``→`""`), `ListItem` (`bullet` `- `→`• `), `Quote`
   (`> `→`▏ `), `ThematicBreak` (`---`→`────` in DejaVu).
3. **Swap in a hand-written projection** only where the rendering genuinely differs
   — the cascading inline styles (see below): rendered `Text`, `Strong`,
   `Emphasis`, `Heading`, `Link`.

### Cascading inline style (the one hard part)

Rendered bold/italic/heading requires the *descendant text* to change font, but
each leaf normally picks its own fixed font and the codebase forbids re-walking
document types in a parent (School A). Solution: an **ambient `:md_style` carried
in the printer context** (`with_property`/`get_property`). A container
(`Strong`/`Emphasis`/`Heading`/`Link`) is hand-written: it augments the ambient
style with its mode and delegates its `content` children through the recursion; the
hand-written rendered `Text` leaf reads the ambient style. Because all four
containers share a `content` collection, they share one abstract
`MarkdownStyledInline` with a single print/forward/read and four one-line typed
`backward` methods (modelled on `YamlSequenceToBlockSyntaxNode`). Output shapes
match the template's, so downstream (`SyntaxToText → WordWrapping → TextToGraphics`)
is reused unchanged.

`BookToSyntax` remains the aesthetic reference (marker-free, font-driven prose).

## Status

**Done (this increment)** — `MarkdownToSyntax(; style=:source|:rendered)` in
`MarkdownToSyntax.jl`; `markdown_rendered_example` +
`make_markdown_rendered_projection_example` (adds `WordWrapping`), registered and
exported. Rendered: big bold headings (size by level), real bold/italic, plain
inline code, `•` bullets, `▏` quote bars, `────` rules, blue link text. Cascading
via ambient `:md_style` in the printer context; hand-written rendered `Text` +
shared `MarkdownStyledInline` (Strong/Emphasis/Heading/Link) with four one-line
typed `backward` methods. Verified: `test_printer`/`test_reader`/
`test_text_navigation` on `markdown_rendered_example` + source regression +
`test_parse_markdown_blocks` = **4826 pass / 0 fail / 0 error**; source view
unchanged.

**Done (follow-up increment)** — the previously-deferred items:
- **Real images**: rendered `MarkdownImageToStyledNode` (hand-written, modelled on
  `BookPictureToSyntaxLeaf`) — an `alt` caption above the decoded image
  (`TextGraphics` + lazy `decode_image` when `url` is a file on disk), falling back
  to the url text otherwise. Both `alt` and `url` remain editable.
- **Code-block fences dropped**: `MarkdownCodeBlockToSyntaxNode` gained
  `open_fence`/`close_fence` fields; the rendered constructor sets them `""` (mono
  block, dim language label).
- **Ordered-list numbering**: rendered `MarkdownListToStyledNode` (hand-written,
  modelled on `YamlSequenceToBlockSyntaxNode`) wraps each item with a per-index
  marker — `1. 2. 3.` when `ordered`, `•` otherwise; rendered `MarkdownListItem`
  carries no bullet. (The source view's list is unchanged.)
- **Assistant on-screen rendering**: the conversation/assistant `MarkdownDocument`
  dispatch (`_conversation_widget_graphics`, `make_conversation_projection_example`)
  now uses the rendered chain; `_block_text`/`_doc_source` in `WorkbenchAssistant`
  stay on the source chain, so the model still receives raw markdown.

**Still a known limitation** (not fixable without a font/backend change):
- **bold-italic** combined face — no such font exists; nesting keeps the inner
  weight (bold inside italic → bold, etc.).

## Design

New primitive family `MarkdownToStyledSyntax.jl` — one projection per node type
(`Markdown<Node>ToStyledSyntax…`), assembled by `MarkdownRenderedToSyntax()` (a
`TypeDispatchingProjection`, mirroring `MarkdownToSyntax()`). Modelled on
`BookToSyntax`.

- **Use `@projection_template` wherever it suffices** (most inline/block nodes —
  leaves and homogeneous-collection nodes with no marker, just styled open/sep).
- **Hand-write the few that need more** (like `SqlToSyntax` mixing template leaves
  with hand-written nodes): ordered-list numbering (needs the element index, which
  the template's `collection(:f) do e` element builder does not expose), the image
  (embedded `TextGraphics` + lazy `decode_image`, per `BookPictureToSyntaxLeaf`),
  and the thematic-rule (embedded graphic).
- **Bidirectionality**: content (heading/paragraph/bold text, list items, code,
  urls) stays editable via the template-derived (or hand-written) readers. There are
  no markers to edit — that is what the source view is for; the rendered view is a
  content editor, exactly like Book.

### Node-by-node rendering spec

| Node | Rendered output |
|------|-----------------|
| `MarkdownRoot` | flush-left blocks, blank-line `sep`, `indentation=0` (BookBook idiom) — same as source |
| `MarkdownHeading` | `collection(:content)`, **no** `#` open, bold sans font sized by level (see table), extra top gap |
| `MarkdownParagraph` | `collection(:content)`, regular sans, `sep=""`, wrapped downstream |
| `MarkdownStrong` | `collection(:content)`, **no** `**`, bold sans applied to content |
| `MarkdownEmphasis` | `collection(:content)`, **no** `*`, italic sans |
| `MarkdownCode` (inline) | `bound(:content)` leaf, monospace + distinct colour/bg, **no** backticks |
| `MarkdownLink` | fixed node: content in link-blue (no `[` `]`); URL dropped from view (optional tooltip via `TooltipDecorator`) |
| `MarkdownImage` | hand-written: `TextGraphics(decode_image(ImageFile(url)))` + caption; fall back to `alt` text if not loadable (Book's lazy pattern) |
| `MarkdownCodeBlock` | monospace block, gray bg / left bar, small language label, **no** fences, `indentation` kept |
| `MarkdownQuote` | `collection(:elements)`, left indent + gray italic (or a `▏` left-bar glyph), **no** `>` |
| `MarkdownList` | `collection(:items)`, indented; unordered via template, **ordered numbering hand-written** |
| `MarkdownListItem` | `• ` bullet (unordered); `N. ` supplied by the ordered `MarkdownList` rule |
| `MarkdownThematicBreak` | a horizontal rule: v1 = a run of `─` (U+2500) in gray; v2 = a real `GraphicsLine` via `TextGraphics` |
| `MarkdownInsertion` | faint "insert markdown here" (unchanged) |

### Heading size map (DejaVu sans bold)

`h1 → 36`, `h2 → 28/24`, `h3 → 22`, `h4 → 20`, `h5/h6 → 20` (regular-weight or
smaller). Body prose: sans regular 20; inline/block code: monospace 20.

## Constraints discovered (ground the implementation)

- **`StyleText` = font + color only — there is NO underline.** Links are
  distinguished by colour (blue), not underline. (If underline is ever wanted it is
  a `StyleText`/backend change, out of scope.)
- **Glyphs must be DejaVu for SDL.** Bullets/rule glyphs (`•`, `─`, `▏`) must use a
  DejaVu font, not Ubuntu — SDL has no font fallback and shows tofu otherwise (see
  the `sdl-no-font-fallback-chrome-glyphs` note). The browser backend is fine either
  way.
- **Images/graphics embed via `TextGraphics`** (Book proves the path;
  `SyntaxToText`, `WordWrapping`, `TextToGraphics` all already handle it).
- **`GraphicsLine`** (with `width`, `dash`) exists for a real horizontal rule — do
  not fake a rule out of many segments (see the `no-faking-with-segments` note);
  start with the `─` char run, upgrade to a single `GraphicsLine` if a true rule is
  wanted.

## Wiring

- `make_markdown_rendered_projection_example` = `MarkdownRenderedToSyntax →
  SyntaxToText → WordWrapping → TextToGraphics`; register `markdown_rendered_example`
  (reuse `make_markdown_document_example`).
- Include `MarkdownToStyledSyntax.jl` in `ProjecturedDomain.jl` (after
  `MarkdownToSyntax.jl`) and the example file in `ProjecturedExample.jl`.
- **Assistant follow-on**: switch the assistant/conversation dispatch entries for
  `MarkdownDocument` from `make_markdown_projection_example` (source view) to the
  rendered one — a chat wants formatted prose, not raw markdown. This is a one-line
  swap in `projection/Assistant.jl` (`_conversation_widget_graphics` extra) and
  `projection/Conversation.jl`. `_block_text`/`_doc_source` (LLM round-trip) must
  KEEP using the source-view chain (`_MARKDOWN_TO_TEXT`) so the model still receives
  real markdown — only the on-screen rendering changes.

## Implementation steps (incremental, each independently testable)

1. Scaffold `MarkdownToStyledSyntax.jl` + `MarkdownRenderedToSyntax()` + example +
   registration. Implement leaves and simple collection nodes first (Text, Strong,
   Emphasis, Code, Paragraph, Heading, Root). `test_printer(markdown_rendered_example)`
   + eyeball the rendered text.
2. Blockquote, unordered lists, thematic break (char rule). test.
3. Code block (mono block, language label). test.
4. Image (`TextGraphics` + lazy decode) and link colouring. test.
5. Ordered-list numbering (hand-written node with index). Optional / can defer.
6. Wire the assistant/conversation `MarkdownDocument` dispatch to the rendered view;
   confirm `test_parse_markdown_blocks` still green (it checks parsing, not rendering)
   and `_block_text` still emits source markdown.
7. `test_example(markdown_rendered_example)` (printer + reader + text navigation).

## Verification

Per repo convention: precompile + `test_printer`/`test_reader`/`test_text_navigation`
on `markdown_rendered_example` via an external run (heavy Julia crashes the editor
host — hand to a subagent/terminal), plus an eyeballed render of the example doc.

## Out of scope (future)

- A `MarkdownToWidget` card/scroll presentation (a third view).
- Rich link tooltips, task-list checkboxes, tables, footnotes.
- Underline styling (needs a `StyleText`/backend extension).
