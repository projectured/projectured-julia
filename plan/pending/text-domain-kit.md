# The Text domain: `@domain Text`, a `TextLine` document, and the `TextBlock` rename

> **Status (2026-08-12): IN PROGRESS.** Phase 1 (`@domain Text`) and Phase 2
> (the `TextBlock` rename) are done and verified in the current tree. Phase 3
> (`TextLine`) landed its document shape and made `TextToGraphics` line-native,
> but the payoff step — `SyntaxToText` emitting `TextLine(…; indentation)` and
> shedding its `indent_indices` splice machinery — is still not done
> (confirmed: `package/syntax/main/SyntaxToText.jl` still has no `TextLine(`
> construction and still carries `indent_indices`). All paths below are
> updated for the 2026-08-09 per-domain package split (`package/visual/` no
> longer exists; its content is now `package/text/`, `package/syntax/`,
> `package/natural/`, `package/console/`, `package/domain/`, and
> others). Historical "Verified" pass-count lines below cite aggregator
> functions (`test_visual()`, `test_domain()`) that no longer exist under
> those names post-split; the current equivalents are `test_substrate()`
> (text/syntax/widget/graphics/… live under `package/substrate/`) and the
> per-domain `test_<domain>()` functions — see
> [documentation/testing.md](../../documentation/guide/testing-guide.md).

> **Decision (2026-08-12): this plan owns the `SyntaxToText` emission change.**
> `SyntaxToText` emits `TextLine(...; indentation)` and sheds `indent_indices`
> and the splice-widening machinery. The reason is the recursive cost: today
> `_splice_child!` walks every span of a child subtree at every ancestor that
> indents, and rebuilds each line-start indent span. With an indentation field a
> re-indent is one addition.
>
> Phase 3 step 3 must also state the join rule for an inline child. A
> line-shaped output cannot splice a child mid-line without a rule for how the
> child's first and last lines merge into the open line. That rule is missing
> today.
>
> **Rejected.** Keep the flat span list and fix the width-0 slot inside the
> Syntax layer: it leaves the indent a span that the caret can reach. Split the
> emission change into a new plan: that settles ownership, not direction. Defer
> the call.

> **Waiting for step 3 of Phase 3 (2026-10-07):** three plans need
> `SyntaxToText` to emit `TextLine`, and the owner decided that this plan does
> it (D7 of [a-text-has-a-gutter-beside-its-lines.md](a-text-has-a-gutter-beside-its-lines.md)):
> that plan from its step 5,
> [a-text-folds-a-region-of-its-lines.md](a-text-folds-a-region-of-its-lines.md)
> from its step 3, and
> [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](a-scroll-pane-keeps-the-edges-of-its-content-in-view.md)
> in its step 3.

Three related changes to [package/text/main/Text.jl](../../source/text/Text.jl),
ordered so each lands on its own:

1. **`@domain Text`** — give the text domain the insertion kit every other domain has (PAR-DOMAIN-OWNS-EDITS).
2. **Rename `TextBlock`** — the stutter is a Lisp transliteration (`text/text`); pick a real name.
3. **`TextLine`** — a line-structured document node, so projections stop re-deriving line
   structure from a flat span list and indentation stops being a fake `TextString`.

(1) is small and mostly deletes code. (2) is mechanical. (3) is the real design work — it is the
one that needs a decision before any code is written.

---

## Phase 1 — `@domain Text`

### Why

[PAR-DOMAIN-OWNS-EDITS](../../documentation/rule/architecture-invariants.md#par-domain-owns-edits) ("Every domain defines its own structural
operations and its own insertion type") says to *"generate the whole insertion kit with one `@domain
X` line rather than re-implementing the root/placeholder/insertion/gesture/traits per domain"*.
The Text domain is the one editable domain that never got one, and the evidence that hand-rolling
rots is already in the tree:

- **`TextInsertion` is dead.** [Text.jl:58](../../source/text/Text.jl#L58) declares
  `@document struct TextInsertion <: TextDocument; value::Any = nothing; end`. It is constructed
  nowhere, printed nowhere, has no traits, no gesture, no reader. Its `value::Any = nothing` does
  not even match the kit's `value::String = ""`, so the shared insertion gestures
  (`_insertion_insert` / `_insertion_tab` / `_insertion_commit` in
  [InsertionToSyntax.jl](../../source/syntax/InsertionToSyntax.jl)) could not drive
  it if they ever reached it.
- **`TextNothing` does not exist.** There is no way to represent "this text slot is empty".
- **The `"text"` short name is a hand-written hack in the wrong package.**
  [InsertionToSyntax.jl:326](../../source/syntax/InsertionToSyntax.jl#L326) carries

  ```julia
  # `TextBlock` is a plain visual document, not an `@domain` kit, so its historic
  # `"text"` short name is a hand-written alias.
  DomainModule.insertion_aliases(::Type{<:TextBlock}) = ["text"]
  ```

  i.e. the *domain* package reaches down into a *visual* type to patch a missing kit.
- **A committed `"text"` insertion is unusable — confirmed in the REPL.**
  `make_insertion_document(TextBlock)` has no `@insertion` override, so it hits the generic fallback
  ([Domain.jl:124](../../source/domain/Domain.jl#L124)) → `TextBlock()` →
  `length(d.elements) == 0`, `getfield(d, :selection)[] === nothing`. The `@gestures TextBlock`
  `KeyPress` rule routes to `_text_insert` → `_text_selection_range`, which does
  `sel isa ConcreteReferencePath || return nothing` and so declines on a `nothing` selection: **the
  document you just inserted takes no keystrokes.** One `@insertion` line fixes it.

  ```
  resolve_insertion(Document, "text")        = TextBlock
  length(make_insertion_document(TextBlock).elements) = 0
  getfield(…, :selection)[]                  = nothing
  insertion_names(TextBlock)                  = ["TextBlock", "text text", "text"]
  TextInsertion in insertion_candidates(Document) = false   # the dead type isn't even a candidate
  ```

### What lands

In [Text.jl](../../source/text/Text.jl):

```julia
@domain Text                     # generates: abstract TextDocument <: Document (exported),
                                 #   TextNothing, TextInsertion(value::String = ""),
                                 #   the Insert-key gesture, and the traits
                                 #   (domain_prefix/domain_insertion/insertion_root/
                                 #    nothing_document/insertion_document/alias "text"/insertable)
```

- **Delete** the hand-written `abstract type TextDocument <: Document end` and the dead
  `@document struct TextInsertion` — the macro emits both. Drop `TextDocument` from the manual
  `export` list (`@domain` exports the root).
- **Delete** `DomainModule.insertion_aliases(::Type{<:TextBlock}) = ["text"]` from
  [InsertionToSyntax.jl](../../source/syntax/InsertionToSyntax.jl) and its comment.
- **Layering:** `DomainModule` lives in the `domain` package
  ([Domain.jl](../../source/domain/Domain.jl)). *(As executed, after the
  later per-domain package split: there is no `package/visual/` any more — the
  `text` package depends on `ProjecturedDomain` directly and imports it as
  `const DomainModule = ProjecturedDomain.DomainModule` in
  [ProjecturedText.jl:26](../../package/ProjecturedText/src/ProjecturedText.jl#L26), then
  `import ..DomainModule: @domain, @insertion` in `TextModule`. Same effect the
  original plan called for — a re-export was needed only under the old
  single-`visual`-package layout.)*

### `@insertion` factories — one, not five *(decided during implementation)*

```julia
@insertion TextBlock = @selected TextBlock([TextString("")]) elements[1].content{0}
```

That single line is the bug fix: an inserted text now arrives with one empty span and a caret in it,
so you can type immediately.

**The span types deliberately get no factory** — a change from the original sketch, which proposed
one each for `TextString` / `TextNewline` / `TextSpacing`. The reason: `insertable` is a property of
the *type*, not of the scope it is completed in, so a factory makes a span committable at the
**top-level** `DocumentInsertion` too — where the committed document is the *root*. The natural
projection routes any `TextDocument` root to the prose chain, whose printer is
`print_document(::TextToGraphics, _, ::TextBlock, _)`: a lone `TextString` root is a `MethodError`,
not a document. Nothing else can reach the span factories, either — the Insert gesture only exists
on `*Nothing` placeholders, and there is no "insert a span at the caret" gesture in `TextBlock`.

So span-level insertion is a **follow-up** that needs two things this phase does not have: a
caret-level insert gesture in the Text domain, and either a root-rendering story for a lone span or
a way to scope a candidate to a domain root. `TextGraphics` needs no explicit opt-out — with no
factory and a required `content` field it was never a candidate.

The Text insertion is still worth having: it is the `"text"` domain entry (two steps to a text, the
same shape as `"json"` → `JsonInsertion` → `"string"`), and `TextNothing` is a real empty-text
placeholder that renders and takes Insert.

### The `"text"` alias moves — a behaviour change to accept deliberately

`@domain Text` emits `insertion_aliases(TextInsertion) = ["text"]`, so at a top-level
`DocumentInsertion` the name **`"text"` now means "enter the Text domain"**, exactly as `"json"` →
`JsonInsertion` and `"julia"` → `JuliaInsertion`. The container is then reachable as `"text text"` /
`"TextBlock"` at the top level, or as `"text"` / `"Text"` *inside* the Text insertion (the
`domain_prefix` strip makes the exact match unambiguous there).

Keeping the alias on the container instead would leave two candidates answering exactly to `"text"`
and make `resolve_insertion` order-dependent. Take the convention.

- Update [DocumentInsertionTest.jl:39](../../test/projectured/projection/DocumentInsertionTest.jl#L39):
  `@test "text" in DS.insertion_names(TextBlock)  # hand-written alias` becomes the assertion that
  `"text"` resolves to `TextInsertion` and that `TextBlock` answers to `"Text"` under
  `root = TextDocument`.

### Rendering the new pair — cheapest correct route

`TextNothing` and `TextInsertion` are `<: TextDocument`, and the **natural projection** routes
`TextDocument => prose_chain` ([NaturalProjection.jl:160](../../source/natural/NaturalProjection.jl#L160))
— a Text→Graphics chain whose printer is typed `print_document(::TextToGraphics, _, ::TextBlock, _)`.
A bare `TextNothing` root would not render.

Every other domain solves this with two lines in its `*ToSyntax` type table pointing at the shared
`NothingToSyntaxLeaf` / `InsertionToSyntaxLeaf` (which are generic — they read the `@domain` traits,
not the type). Text has no `TextToSyntax` table, so put the two entries in the natural projection's
to-graphics dispatcher instead, **before** the `TextDocument` entry (exact type beats abstract):

```julia
TextNothing   => nothing_leaf_chain,     # NothingToSyntaxLeaf   → SyntaxToText → TextToGraphics
TextInsertion => insertion_leaf_chain,   # InsertionToSyntaxLeaf → SyntaxToText → TextToGraphics
TextDocument  => prose_chain,
```

Both renderers already exist in the domain package, one layer *above* visual — which is fine here
precisely because the wiring lives in the domain package too. **No new renderer, no new gesture
table, no visual-layer rendering work.**

*Out of scope for this phase:* rendering the pair in a **standalone** visual Text→Graphics chain
(`make_text_projection_example`), which would need `TextToGraphics` to grow span kinds or a
`TextNothingToText` / `TextInsertionToText` Text→Text pair. Nothing needs it yet: a `TextNothing`
only arises via the insertion machinery, which lives in the domain package. Revisit if we ever want
"delete the last span of a text" to leave an editable empty document.

### Phase 1 checklist — **done**

- [x] Confirm the `make_insertion_document(TextBlock)` defect in the REPL (empty spans, no selection).
- [x] `const DomainModule = …` in `ProjecturedVisual.jl`; import `@domain` / `@insertion` in `TextModule`.
- [x] `@domain Text`; delete the hand-written root and the dead `TextInsertion`.
- [x] `@insertion TextBlock` only — the span types stay non-candidates (see above).
- [x] Delete the `insertion_aliases(TextBlock)` hack from `InsertionToSyntax.jl` (and the now-unused
      `import ..DomainModule` / `TextBlock` imports it needed).
- [x] Natural-projection entries: `TextNothing` / `TextInsertion` in **both** tables — the to-syntax
      table (pointing at `InsertionNothingToSyntaxLeaf` / `DomainInsertionToSyntaxLeaf(TextDocument)`)
      and the to-graphics table (routing them to `syntax_to_graphics`, ahead of the abstract
      `TextDocument => prose_chain`).
- [x] Update `DocumentInsertionTest.jl`; add the "a committed insertion is editable" regression test.

**Verified:** `test_document_insertion()` 113/113; `test_example(text_example)` 1585/1585;
`test_visual_layering()` / `test_domain_layering()` green. `plain_text` (1187/7) and `natural`
(19801/35) fail identically on the base commit — pre-existing, not regressions. Driven end to end:
`TextNothing` renders through the natural projection → Insert yields a `TextInsertion` with the
caret in its buffer → that renders → `"text"` commits a `TextBlock` with one span and a caret →
typing emits a `ReplaceStringRangeOperation` instead of declining.

---

## Phase 2 — rename the container to **`TextBlock`** — **done**

**Yes, rename it.** The old name was a transliteration of the Lisp original's `text/text`; in Julia
the domain prefix is carried by the type name, so the container read as a stutter at every one of
its 451 occurrences.

The type is *a container of styled spans* (`TextString` / `TextNewline` / `TextSpacing` /
`TextGraphics`) — and, if Phase 3 lands, of `TextLine`s. Candidates:

| Name | Reads as | Against |
|---|---|---|
| **`TextBlock`** | a block that breaks into lines — the standard typographic pairing with `TextLine`, and natural whether it holds spans, lines, or both | faintly implies a block/inline distinction we don't otherwise model |
| `TextFlow` | an inline flow of spans that wraps into lines (CSS's model) | a flow *of already-broken lines* is a slightly odd reading |
| `TextContent` | honest, bland | says nothing; "content" is already a field name on every span |
| `TextParagraph` | prose-ish | collides with `BookParagraph`'s meaning; a text is not one paragraph |
| `TextSequence` | accurate | bureaucratic; every container is a sequence |
| `Text` | shortest | clashes with `Base.Text`; and the `@domain` convention wants the prefix |

**Decided: `TextBlock`** — it pairs with `TextLine`, it is the ordinary word for the thing that
breaks into lines, and it reads well at construction sites:
`TextBlock(TextString("hello"), TextNewline(font=f), TextString("world"))`. (Runner-up was
`TextFlow`.)

Mechanics, as executed:

- One mechanical sweep over `package/`, `documentation/`, `plan/pending/` and `plan/tentative/`;
  **`plan/done/` left alone** — those are history.
- **The one trap: `_TextTexture` / `_TextTextureKey`** in
  [ProjecturedSdl.jl](../../package/ProjecturedSdl/src/ProjecturedSdl.jl) — the SDL glyph-texture cache
  contains the old name as a *substring*, and a naive replace corrupts it into `_TextBlockure`.
  The sweep used a negative lookahead (`s/TextText(?!ure)/TextBlock/g`), which also carries the
  compound names across correctly (`PrimitiveStringToTextText` → `…ToTextBlock`,
  `TextTextToString` → `TextBlockToString`).
- Nothing structural depends on the name: reference paths are built from *field* names
  (`elements` / `content`), and `TypeReference` holds the type object, not a string.
- The name **is** user-visible in one place — the insertion vocabulary, which is derived from it.
  Inside the Text scope the container is now `block` / `text block` (prefix-free `Block`), not
  `text`. The bare domain name still commits it, but by *unambiguous prefix* rather than exact
  match, since it is the scope's only candidate. `DocumentInsertionTest`'s derived-name assertions
  are the record of this.

---

## Phase 3 — `TextLine` *(shape B decided; separator semantics decided)*

### The case for it is stronger than it looks

Line structure is *already* the organizing unit of the text layer — it is just re-derived from a
flat span list by every consumer, independently:

| Consumer | How it finds lines today |
|---|---|
| [TextToGraphics.jl:267-296](../../source/text/TextToGraphics.jl#L267-L296) | `lines_cell` scans `elements` for `TextNewline`, groups, then builds **per-line reactive cells** (`get_line_cells`, `_layout_line`) — lines are already the incrementality unit |
| [LineNumbering.jl](../../source/text/LineNumbering.jl) | *"Lines are delimited by TextNewline elements"*; prepends a prefix span per line and remaps every reference index |
| [WordWrapping.jl](../../source/text/WordWrapping.jl) | splices **soft `TextNewline`s** into the span list and maintains a `WrapSeg` back-map |
| [TextFirstLine.jl](../../source/text/TextFirstLine.jl) | truncates at the first `TextNewline` *or embedded `'\n'`* |
| [Console.jl:198](../../source/console/Console.jl#L198) | `_render_span!(::TextNewline)` → `'\n'` |
| [TextToString.jl](../../source/text/TextToString.jl) | `TextNewlineToString` |
| [SyntaxToText.jl:778](../../source/syntax/SyntaxToText.jl#L778) | emits `TextNewline` + an **indent `TextString`**, plus `indent_indices` and splice-widening machinery to keep carets out of it |

Two payoffs:

1. **Indentation becomes a line property, not a fake span.** `TextLine(spans...; indentation = 2)`
   means the indent is not an editable `TextString` a caret can land inside, and the width-0 indent
   slot problem (flagged in
   [simplest-syntax-document.md](./simplest-syntax-document.md)) is localized instead of
   distributed. `SyntaxToText`'s indent-splicing machinery shrinks or disappears.
2. **Line-shaped consumers stop scanning.** `TextFirstLine` becomes `elements[1]`; `LineNumbering`
   maps over lines instead of re-deriving and re-indexing them; `TextToGraphics`'s `lines_cell`
   becomes the identity.

### Semantics to nail down

- **"Contains no newline, implies one."** A `TextLine` holds spans but no `TextNewline`, and *no
  `TextString` whose content embeds a `'\n'`* — note today's text has **two** line mechanisms
  (`TextNewline` spans *and* embedded `'\n'` in a `TextString`, per `TextFirstLine`), and the
  invariant must forbid both. Nothing enforces it today; the pending
  [recursive-validation-core-functions](../done/recursive-validation-core-functions.md) work is the
  natural enforcement point. Until then it is a producer-side convention.
- **Separator, not terminator.** The implicit newline is emitted *between* consecutive lines, so `n`
  lines produce `n-1` breaks — matching today's span list exactly, and avoiding a phantom trailing
  blank line in `TextToGraphics` (whose `lines_cell` would otherwise split a trailing newline into
  an empty final line). Consequence: `text_flat_length(::TextLine) = sum(children) + (is_last ? 0 : 1)`,
  which means flat length is **not** a pure per-node function any more — or, if we prefer purity,
  the container adds the separator when concatenating. **Decide this explicitly; the flat-offset
  machinery depends on it.**

### The real cost: the flat cursor machinery goes from 2 levels to 3

Everything in [Text.jl](../../source/text/Text.jl) that touches carets assumes a **flat**
span list — `.elements[i].content{k}`, with an `Int` span index:
`_text_span_infos`, `_text_span_text`, `_step_left` / `_step_right`, `_word_step_*`,
`_text_selection_range`, `_text_replace_path`, `_build_selection_path`, `_cursor_position`,
`text_selection_flat` / `_text_cursor_flat`, plus `splice_value!(::TextBlock, …)`.

With lines the path is `.elements[i].elements[j].content{k}`, so the `Int` span index becomes an
**index path**. That is the bulk of the work, and it is contained in Text.jl plus
`TextToGraphics`'s `char_to_coord` and the `SyntaxToText` reference maps. Selections also get one
hop deeper, which touches `@reference_case` patterns and `TextRectangularReference`'s flat offsets.

### Shape — **B, decided**

`TextLine` is **one more element kind**: allowed in `TextBlock.elements` alongside the spans,
producers opt in, consumers learn it one at a time. Backward compatible, and it is what the request
describes ("just a domain document, maybe not all projections support it"). The flat helpers must
therefore handle *both* shapes — a flat span list and a line-nested one.

Rejected: **A** (`elements` holds only `TextLine`s) — cleanest model, but every reference path in the
text layer changes at once and an unstructured span sequence becomes unrepresentable.

Kept in reserve: **C** — a `TextLineFlattening` (Text→Text) projection that expands `TextLine`s back
into spans + `TextNewline` for consumers that have not learned lines yet. It is a proper projection,
so its reference maps keep carets consistent through it for free. Use it as the **escape hatch** for
the long tail (WordWrapping, TextFiltering, TextHighlighting, Console) rather than as the default —
a projection that must be hand-inserted into every chain is a maintenance burden.

**Sequence:** `text_flat_length` + the Text.jl cursor helpers learn index paths → `TextToGraphics`
goes line-native (it already groups by line) → `SyntaxToText` emits `TextLine(…; indentation)` and
sheds its indent splicing → the remaining consumers upgrade, or get `TextLineFlattening` in front.

### What landed — steps 1 and part of 4

**Done: the document and everything that edits it.**

- `TextLine` (`elements`, `indentation`), with the separator semantics above.
- The span coordinate is now an **index path** (`SpanPath = Vector{Int}`): `[i]` for a top-level
  span, `[i, j]` for span `j` of line `i`. The step / word-motion helpers already treated the span
  index as an opaque key (`==` and a `Dict` lookup), so they carried over untouched — only the
  *parse* end (`_text_selection_range`, the new `_cursor_coord`) and the *build* end
  (`_text_replace_path`, `_build_selection_path`) grew the extra `elements` hop.
- **`_cursor_position` and `_build_selection_path(::Int, ::Int)` keep their flat `Int` form** —
  `TextToGraphics` builds carets from `SegCoord.span_idx` and lays out flat blocks only. That is
  what kept this change off the critical path.
- `text_flat_offsets` is the one place the implicit break is materialized. **A line's indentation
  counts toward its flat length** — the renderers emit it as leading spaces, so a caret after an
  indented line would otherwise be misplaced. (Found by rendering, not by reading.)
- Rendering: `TextToString` (new `TextLineToString` leaf; the block emits the break, the line emits
  its indent and spans) and the console backend.

**Done: `TextToGraphics` is line-native** (step 2 of the sequence).

`SegCoord.span_idx :: Int` → `span_path :: SpanPath`. The reader carried over as predicted: the
`_build_selection_path(sc.span_path, …)` sites needed no change (the `Vector` method already
existed) and the `cursor_pos.span == …` comparisons became path comparisons by swapping
`_cursor_position` for `_cursor_coord` — which is now **deleted**, nothing else used the flat
reading. `_build_selection_path(::Int, …)` stays as a one-line delegation to the path method.

The layout **collapsed rather than grew**: `_layout_text` and `_layout_line` were two near-duplicate
span loops that had to agree by hand or the caret would drift off its glyph. Both passes now run one
grouping (`_line_groups`) and one span loop (`_layout_group`) — the per-line reactive sub-canvases
with `collect_spans = true`, the caret/highlight overlay with the running absolute `y` and the caret
to locate. `_layout_text` is gone; the overlay is `_layout_overlay`, which folds `_layout_group` over
the groups.

Two things the *rendering* caught that the reading did not (both now regression-tested in
`TextToGraphicsTest`):

- **An empty `TextLine` collapsed to nothing.** The blank-row fallback took its height from the
  group's terminating `TextNewline`, and a line has none — so a blank line in indented code would
  have vanished. It is sized by the block's *prevailing font* (`_block_font`), in a cell that only an
  empty line reads, so a font edit still re-lays out just the lines that draw glyphs. The mirror
  trap: the empty group a **trailing** `TextNewline` leaves behind is *not* a line and must keep its
  zero height, or every block ending in a newline grows a phantom row. Hence `is_line` on the group.
- **A line's indentation counts in the flat box space** — the space a `TextRectangularReference` is
  expressed in — as does its implicit break; the rule `text_flat_offsets` already encodes, and the
  one **`SyntaxToText` must count when it emits the lines**. A `TextNewline` still counts **zero**
  there, and that is not an oversight to unify away: `WordWrapping` splices *soft* newlines in at
  wrap points and documents the box space as invariant under them. The graphics box space and
  `text_flat_length` are therefore two deliberately different spaces. An inline `TextGraphics`
  counts 1 in both since
  [an-inline-image-is-one-caret-position.md](../done/an-inline-image-is-one-caret-position.md).
  Leave them apart.

Verified by driving the pipeline, not only by the suite: a line block renders indented with one row
per line, the graphics agree with `TextToString`'s string, a click on the second row yields
`.elements[2].elements[1].content{2}`, Down crosses into it. `test_visual` 51895/0/0; `test_domain`
byte-identical to the base commit (125978 passed, 93 failed, 1 errored — all pre-existing).

**Not done — the next commit:**

3. **`SyntaxToText` emits `TextLine(…; indentation)`** and sheds `indent_indices` + the
   splice-widening machinery. This is the payoff, and the first real producer. Its `_span_len` /
   `_text_elem_path_to_flat` accounting must grow the break and the indentation (see above), and its
   `_parse_text_elem_path` — a flat `[i]`-only parser, duplicated across `WordWrapping`,
   `TextFiltering`, `TextHighlighting`, `TextFirstLine`, `SelectionInverting` and `LineNumbering` —
   is what each of those consumers will have to learn a path for, or get `TextLineFlattening` (C) in
   front of.

**Found, not fixed** (pre-existing, both out of this phase's scope):

- A caret in an **empty** `TextString` renders no caret at all: the layout `continue`s past an empty
  sub-line before it can place one, so no `SegCoord` and no cursor rect. A freshly inserted `text`
  (one empty span, caret at `{0}` — Phase 1's `@insertion`) is exactly this shape. Fixing it means
  emitting a zero-width segment, which shifts `coord_map` indices and so the rasterized-image click
  path; do it deliberately, with `_translate_click` in hand.
- `TextSpacing` is never rendered by `TextToGraphics` (the span loop skips it) though it counts 1 in
  `text_flat_length`.

`TextLine` is deliberately **not** an insertion candidate — but *withholding the `@insertion` factory
is not enough*, which is the trap the test suite caught. Both of its fields are defaulted, so unlike
the span types (each has a required field, hence no zero-arg constructor) `TextLine` **is** zero-arg
constructible, and `insertable` therefore said yes. Two consequences, both real: `"text"` became
ambiguous (it prefixes both `text block` and `text line`, so the domain name stopped committing
anything), and a committed `text line` would put a lone line at the document *root*, which the prose
chain cannot print. The opt-out is explicit:

```julia
DomainModule.insertable(::Type{<:TextLine}) = false
```

It becomes a candidate when the Text domain grows a caret-level insert gesture and the pipeline can
render a line.

### Phase 3 guards

`test_syntax_to_text()`, `test_word_wrapping()`, `test_line_numbering()` (checked
2026-08-12: there is no `test_line_numbering` function today — use whatever
covers `package/text/main/LineNumbering.jl` at the time, or add one),
`test_typein(text_example)`,
`test_position_navigation(text_example; check_reaches_all=true)`, and `PrinterLocalityTest`
(`package/projectured/test/editor/PrinterLocalityTest.jl`; a new
document node per line is a new iomap per line — watch for reconciliation loss).

---

## Decisions

- **Rename target** — `TextBlock`. *(decided)*
- **`TextLine` shape** — B: one more element kind, with `TextLineFlattening` (C) held in reserve as
  an escape hatch. *(decided)*

- **Implicit newline** — **separator**. `n` lines → `n-1` breaks, no phantom trailing blank line.
  `text_flat_length` stays a pure per-node function and the *container* adds the break
  (`text_flat_offsets`); `TextBlockToString` and `TextToGraphics` both encode the same rule.
  *(decided, implemented)*

Still open:

- **`TextGraphics` insertability** — scaffold a placeholder image, or opt out with
  `insertable(::Type{TextGraphics}) = false`.
