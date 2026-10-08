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
> [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md)
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

**The consumers learn lines, and keep the gutter and the fold (moved here from
step 3 of [a-text-has-a-gutter-beside-its-lines.md](a-text-has-a-gutter-beside-its-lines.md),
the owner, 2026-10-07).** A `TextLine` now holds a `gutter` and a `fold` beside
its spans and its indentation. Each decorator passes a line through unchanged,
so it keeps both, and `test_text_gutter()` asserts it; but none of them knows
lines. Measured on a block of three lines on 2026-10-08:

- `WordWrapping` does not wrap inside a line. To wrap one, it must put soft breaks
  inside a `TextLine`, against the rule that a line holds no break, so that rule
  needs a decision; `TextToGraphics` must then break a row at such a break and
  map a caret across it. Its list of the lines must not depend on the width: the
  scroll pane offers the width of the view beside the gutter, which reads the
  gutter (Q4 of [a-scroll-pane-keeps-the-edges-of-its-content-in-view.md](../done/a-scroll-pane-keeps-the-edges-of-its-content-in-view.md)).
- `TextHighlighting` marks no match inside a line.
- `TextFiltering` joins the text of the spans at the top of the block, and a line
  adds none, so a pattern drops every line of a block of lines.
- `TextFirstLine` keeps every line of a block of lines, because it cuts only at a
  `TextNewline` or an embedded `'\n'`.
- The flat runs of the decorators (`_make_flat_runs`) count the break of a line,
  which `TextFolding` uses, but the decorators that split spans name a span by
  its index at the top of the block.

`TextLineFlattening`, the escape of shape C, would drop the gutter and the fold,
so it does not serve a text with a gutter.

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

### Step 3: the design (2026-10-08, in progress with the owner)

The owner asked to start this step on the branch `text-gutter` (2026-10-08). A
survey of the tree found where a line break of syntax text comes from, and it is
not only the indentation chrome that `indent_indices` widens:

- **The chrome of `SyntaxToText`**: a `TextString("\n")` and an indent span
  before each child of a node that indents, and before its close delimiter.
- **A leaf value**: a code block and a text of Markdown, a paragraph of a Book,
  a docstring of Julia, a text node of XML, a raw text of SQL, a
  `PrimitiveString`. No leaf shares the cell of its document: each is a derived
  `TextString`, and an editable one writes back through `bound`.
- **A delimiter or a separator of a domain**: about 40 in reStructuredText,
  more in Markdown, Book, SQL (a clause ends in `"\n"` and indents itself) and
  Formula.

**The flat offsets do not change.** A `"\n"` span counts one offset and so does
the implied break before a `TextLine`; an indent span of `n` spaces counts `n`
and so does the indentation `n` of a line. So a block of lines has the flat
offsets of the span list of today, and every mapper of `SyntaxToText` that
works in flat offsets (a caret, a box, `_syntax_to_flat`, an introduced position,
the zero-width edit) keeps working. What changes is every place that names a
span by its index in the list: `child_elem_ranges`, `own_spans`, `sep_indices`,
`marker_index`, `_text_elem_path_to_flat`, `_flat_to_span_char`, the parsers of
`.elements[j].content{c}`, `_resolve_click`, the edit reader, and
`SyntaxListToText`. `SyntaxToTextTest.jl` is the one test that asserts the span
list exactly; the navigation sweeps assert no counts, but their broken markers
can flip.

**Q1 Where the lines come from. Decided (a), the owner, 2026-10-08:** every
producer of syntax text emits lines.

- (a) **Every producer of syntax text emits lines.** A span that holds a `'\n'`,
  a leaf value or a delimiter of a domain, is split at each break into pieces on
  separate lines, with a table of segments that maps a piece back to its span by
  offset, as `WordWrapping` maps its pieces; the chrome of a node that indents
  becomes the indentation of its lines. Every break is a line, so a number counts
  every line, and a fold and a mark of the syntax ride on the lines.
- (b) **A stage after `SyntaxToText` makes the lines**: it splits the flat text at
  each `'\n'` into `TextLine`s, with the same table of segments. `SyntaxToText`
  stays as it is. But a fold of the syntax (step 3 of the fold plan) and a mark of
  a domain can not reach the lines through a flat text, unless they travel in it
  as elements of zero width, which D1 of the gutter plan did not choose.
- (c) **Only the chrome makes lines**, and a `'\n'` inside a span stays there,
  as `TextToGraphics` draws it today. The smallest change, but a code block of
  Markdown or a paragraph of reStructuredText is one line to the numbers and to
  the folds.

Q5 narrowed (a) on 2026-10-08: a leaf value is a run and is not split; a text of
many lines reaches the lines through the rule of
[a-text-span-holds-no-line-break.md](a-text-span-holds-no-line-break.md).

My recommendation was (a), because it is the direction decided on 2026-08-12
(this plan owns the change, and `SyntaxToText` emits lines), and only (a) gives
every break a line and lets the syntax put a fold and a mark on a line. Its cost:
the largest rewrite of the three, a split of leaf values with a table of
segments, and every index-based helper of `SyntaxToText` learns span paths.

**Q2 The join rule of a child.** The output of every leaf and every compound is
a block of one line or more, and the first line of a compound is its open line,
where its marker and its open delimiter go. The indentation of a line is relative
to the start of the compound that made it. A compound appends its own chrome and
its children so:

1. The first line of a child joins the open line of the parent: its spans are
   appended to that line.
2. Every other line of the child is a line of the parent, in order.
3. The last line of the child is the open line of the parent after it, so the
   separator or the close delimiter that follows goes on that line.
4. A parent that indents puts each child on a new line of its own, and before its
   close delimiter, and adds `indent_size` to the indentation of every line of
   the child, as it widens every indent span of the child today.
5. What a joined line holds of the fold and of the gutter of the child's first
   line, when the open line has some of its own. **Decided (b), the owner,
   2026-10-08:** the open line keeps its fold and takes the child's when it has
   none; the gutters join lane by lane, and the open line's mark stays in a lane
   that both fill.
   - (a) The open line keeps its fold and its gutter whole; when it has none, it
     takes those of the child's first line.
   - (b) The open line keeps its fold, and takes the child's when it has none, as
     T4 of the fold plan decided for two nodes on one line; the two gutters join
     lane by lane, and in a lane that both fill, the mark of the open line stays.
     A gutter of another type than the open line's is dropped.

My recommendation for 5 was (b), because a mark of a domain can come from a node
that starts in the middle of a line, such as the breakpoint of the second
statement of `x = 1; y = 2`, and (a) would drop it when the line has a gutter of
its own.

**Q3 The lazy list path. Decided (a), the owner, 2026-10-08:** a lazy list of
lines. `SyntaxListToText` prints a lazy list of syntax (a
`ListNode`) as a `TextBlock` whose elements are a lazy list of spans, with a
`TextNewline` between the spans of two elements. `TextToGraphics` draws such a
text as one canvas for each paragraph between two `TextNewline`s, and counts the
paragraphs from the head. With Q1, the output of each element is a block of
lines.

- (a) **A lazy list of lines.** Each node of the output list holds one
  `TextLine`; an element of the input contributes its lines in order, and no
  `TextNewline` stands between them, because a line implies its break. An element
  maps to the run of its lines, counted from the head. `TextToGraphics` draws one
  canvas for each line of the list, in place of one for each paragraph, and its
  list path learns a line; a gutter for a lazy text can then come, line by line.
- (b) **A lazy list of spans as today**, the lines of an element flattened back
  into spans with a `TextNewline` between them. Nothing in `TextToGraphics`
  changes, but a lazy text of syntax has no lines, so no gutter and no fold.

My recommendation was (a), because it is the one shape of text that Q1 chose,
also for a text with no end, and it opens the gutter of a lazy text (a limit in
`text.md`). Its cost: the list path of `TextToGraphics` and the mapping of
`SyntaxListToText` learn lines.

**Q4 A wrap inside a line.** Open. After step 3 every syntax text is a block of
lines, and the prose chain (`make_natural_prose_graphics`) and the application
chain put `WordWrapping` in front of `TextToGraphics`. Today `WordWrapping`
passes a `TextLine` through unwrapped, so a paragraph of prose would run past the
right edge. The width that a wrap uses is the width of the view beside the
gutter, and the gutter is as wide as its widest row.

- (a) **`WordWrapping` splits a line into many `TextLine`s.** The first keeps the
  gutter and the fold, and the others have none. But the list of lines then
  depends on the width, the rows of the gutter depend on the list, and the width
  of the view depends on the gutter: a cycle of cells.
- (b) **`WordWrapping` puts a soft `TextNewline` inside the `TextLine`.** The rule
  "a line holds no break" becomes "a line holds no hard break", and only a stage
  that wraps puts a break inside a line. `TextToGraphics` starts a new row there,
  at the indentation of the line, and the row of the gutter stands on the first
  row of the line. The list of lines and the rows of the gutter do not depend on
  the width, so there is no cycle. A soft break counts one flat offset, as a soft
  `TextNewline` counts today.
- (c) **`TextToGraphics` wraps a line itself** at the width that it gets, and
  `WordWrapping` stays for a list of spans. Two places then wrap text, and the
  renderer gets a second job.

*Recommendation: (b), because it is the only one of the three with no cycle and
one place that wraps, and the numbers, the folds and the gutter see one line for
one line of the source. Its cost: the grouping of `TextToGraphics` breaks a row
inside a line, and `WordWrapping` learns a span path in a line.*

**Q5 A keystroke in a leaf.** Found when the work started (2026-10-08).
**Decided by a new rule, the owner, 2026-10-08:** none of (a), (b) and (c)
below. A `TextString` holds no `'\n'`, and the domain states that a field can
hold lines by the type it gives the leaf value: a `TextString` is one run, and a
`String` or a `TextDocument` is text that can have lines, which the recursion
prints with a projection such as `StringToTextBlock`. That rule is the plan
[a-text-span-holds-no-line-break.md](a-text-span-holds-no-line-break.md). In this
plan a leaf value is a `TextString`, so the leaf never reads it: an edit of a leaf
leaves the lines valid, and a `'\n'` that a value still holds is a row inside its
line until its domain moves to the new rule. The question, as it stood:
To split a leaf value at its breaks, the leaf reads the content of the value. The
cell system has no cut-off for an equal value (decision 10 of
`architecture-decisions.md`), so then every keystroke in any leaf builds the lines
of the leaf again, and every compound up to the root joins its lines again.
`SyntaxToTextTest.jl` asserts the opposite today: an edit of the text of a leaf
leaves the span list valid. With lines, `TextToGraphics` lays out only the line
whose span changed, but only while the list of lines stays valid.

- (a) **Every leaf reads its value.** Every break is a line, also one that a
  paste puts into a JSON string. A keystroke costs a join from the leaf to the
  root and a layout of every line, about what one keystroke costs today, when
  syntax text is one group. The test changes to assert the opposite.
- (b) **Only a leaf that its domain marks reads its value.** A new field of
  `SyntaxLeaf`, such as `is_multiline::Bool = false`, set by the domains whose
  leaf holds a text of many lines: a code block and a text of Markdown, a
  paragraph of a Book, a docstring and a string of Julia, a text node of XML, a
  raw text of SQL. A keystroke in any other leaf lays out only its line. A break
  in an unmarked leaf, from a paste, stays inside its span: `TextToGraphics` draws
  it as a second row of the line, and the numbers count one line.
- (c) **No leaf reads its value**, and a break in a value is always a row inside
  a line (option (c) of Q1 for leaves). The delimiters and the chrome still make
  lines.

My recommendation was (b), because it keeps the property that the test asserts.
The owner stated the principle that moved the decision: an edit of the document
must cause little change in the output down the chain. A flag on the syntax still
makes the structure depend on the content, and the owner was not sure that the
syntax is the place to state a break. The type of the value states it at the
source.

### Step 3: the steps of the work

Each step is one commit, and the flat offsets stay the same in every step.

The design of step 1, found when the work started (2026-10-08):

- **The flat list of an output.** Each IO map keeps the flat list of its output:
  each span of each line in order, with an entry for the break before a line and
  an entry for its indentation. A break counts one offset and an indentation its
  width, so the offsets of the list are the offsets of the span list of today, and
  the mappers keep their logic over it. A child is a contiguous range of the list
  of its parent, as today.
- **A parent speaks to a child in the language of the child's output:** a flat
  caret, a span `[i, j]` of a line, or an edit of the characters of such a span.
  So a child that another projection prints works as a syntax child does.
- **Which spans are cut.** Only a delimiter or a separator of a compound that
  holds a `'\n'` is cut into lines. It is a constant of the domain, so the cut
  reads a cell that no edit writes. A leaf value and a span of another producer
  are one run each (Q5).
- **Which lines an ancestor indents.** A line that the chrome of a compound starts
  has an indentation that a compound that indents widens. A line that a break
  inside a delimiter or a separator starts has indentation 0 and keeps it, as
  today: the text of a span is its own, with its own spaces. The IO map records
  which lines are of the chrome.
- **Rule 5 waits** for the first producer that puts a gutter or a fold on a line
  of syntax text, step 3 of the fold plan.
- **The cost of a keystroke.** A leaf reads no content, so a keystroke in a leaf
  changes the content of one span and leaves every list of lines valid. With
  lines, `TextToGraphics` then lays out only the line of that span, where today
  syntax text is one group and a keystroke lays out the whole block. Step 5
  measures a keystroke before and after.

0. ~~**The baseline.**~~ **Done 2026-10-08**, at 32ad06496 (the head of the
   branch before step 3), each part in a process of its own. Every part ended,
   and only `test_platform` has failures: 14 Fail and 8 Error, in
   `ExternalAgentTurnTest.jl` (19), `McpLogTest.jl:55` (1) and
   `InterfaceApiTest.jl:46,49` (2), none of them in the text or the syntax.

   | part | Pass | Broken | part | Pass | Broken |
   |---|---|---|---|---|---|
   | `test_platform` | 107172 | 8 | `test_repls` | 24075 | 2 |
   | `test_position_navigations` | 8217 | 5 | `test_printers` | 292114 | 0 |
   | `test_typeins` | 5146 | 22 | `test_readers` | 24525 | 0 |
   | `test_text_navigation_invariants_all` | 379 | 10 | `test_click_roundtrips` | 42 | 0 |
   | `test_natural_renders_every_atom` | 2 | 0 | `test_tree_navigations` | 84 | 0 |
   | `test_json` | 227 | 0 | `test_domain_examples` | 344953 | 0 |
   | `test_yaml` | 54 | 2 | `test_mouse_clicks` | 34 | 12 |
   | `test_xml` | 80 | 0 | `test_natural_round_trips_every_atom` | 4 | 0 |
   | `test_math` | 182 | 0 | `test_markdown` | 262 | 0 |
   | `test_fsm` | 163 | 0 | `test_rst` | 109 | 0 |
   | `test_book` | 33 | 0 | `test_julia` | 526 | 0 |
   | `test_sql` | 660 | 0 | `test_dbcatalog` | 74 | 0 |
   | `test_formula` | 123 | 0 | | | |

   The logs are in `/var/tmp/text-gutter/baseline/`, and the worktree
   `projectured-julia-text-gutter-baseline` stays at that commit for a rerun.
1. ~~**A leaf and a compound make lines.**~~ **Done 2026-10-08.** One commit,
   because a compound can not join the lines of a leaf and splice the spans of a
   compound at the same time. `SyntaxCompoundToText` builds its lines by the join
   rule of Q2: the chrome of a node that indents becomes the indentation of its
   lines, and a delimiter or a separator that holds a `'\n'` is cut into lines.
   A leaf is one line of runs and never reads its value (Q5). `indent_indices`,
   the widened indent spans and the `"\n"` spans are gone. The lazy list path
   flattens the lines of each element back into spans until step 3.
   `SyntaxToTextTest.jl` asserts lines, with six new testsets.

   Checked against the baseline in a clone at a snapshot of the step (logs in
   `/var/tmp/text-gutter/probe2/`):
   - The same counts in `test_platform` (only the 22 failures of the baseline),
     `test_rst`, `test_formula`, `test_julia`, `test_readers`, `test_repls`,
     `test_position_navigations`, `test_typeins`, `test_sql`, `test_json` and
     `test_xml`. `test_book` passes after its test helper reads lines (33).
     `test_syntax_tree_selection` passes (29). `test_printers` passes 28696
     more, because a block of lines has more elements to check.
   - **Known, for step 4:** `test_markdown` has 7 Fail and 1 Error in
     `MarkdownWrapTest.jl` and `MarkdownTableTest.jl`, because `WordWrapping`
     does not wrap inside a line. Prose of a syntax view does not wrap until
     step 4.
   - Four tests read the span list of a syntax output and now read its flat
     string: `FileSystemToSyntaxTest.jl`, `BookToSyntaxTest.jl`,
     `SyntaxTreeSelectionTest.jl` and `SyntaxToTextTest.jl`.
2. *(merged into 1)*
3. **The lazy list of lines.** `SyntaxListToText` makes a lazy list of lines (Q3),
   and the list path of `TextToGraphics` draws one canvas for each line.
4. **The decorators learn lines.** `TextHighlighting`, `TextFiltering`,
   `TextFirstLine` and `SelectionInverting` name a span by its path in a line, and
   `WordWrapping` wraps inside a line as Q4 decides.
5. **The sweeps.** Run the guards and the suites of step 0 again, and compare. A
   broken marker that changes gets a reason or a fix.
6. **The documents.** `text.md` and the syntax document describe the lines of
   syntax text, and the limit "a lazy text has no gutter" goes.

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
