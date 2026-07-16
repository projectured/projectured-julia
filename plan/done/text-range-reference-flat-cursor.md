# TextRangeReference — a flat, structure-independent text cursor/selection

**Status:** pending

## Problem

The text-domain character cursor is currently anchored *to a span*: a caret is a
structural reference path such as

```
::TextBlock.elements::CellVector[i]::TextLine.elements::CellVector[j]::TextString.content::String{c}::Position
```

built by `_build_selection_path` ([Text.jl:706](../../package/visual/main/text/Text.jl#L706)),
and a text edit is a `ReplaceStringRangeOperation` whose `reference` ends in
`.content[s:e]` on a single span.

Because the caret is anchored to a span, the one logical caret at a span boundary
has **two encodings** — `(prevspan, prevlen)` and `(nextspan, 0)` — which
`_step_left` / `_step_right` explicitly treat as duplicates and skip
([Text.jl:401-421](../../package/visual/main/text/Text.jl#L401-L421)). Which one
survives a walk depends on the direction of travel, so the *same* visual caret is
represented by two different references depending on how the cursor arrived. This
is why `test_text_nav_invariants` cannot assert `reverse(left) == right` and
settles for length + endpoint agreement
([ClipboardRoundtripTest.jl:356](../../package/visual/test/editor/ClickRoundtripTest.jl#L356)).

The same span-anchoring hides a **second bug**: at a hard line break the
boundary-skip in `_step_right` jumps from end-of-line-N straight to
`(lineN+1, 1)`, skipping the start-of-line-N+1 caret entirely — even though those
are genuinely different visual carets on different rows.

### Root cause

A caret's identity is tied to the TextBlock's *span/line structure* instead of to
the text it presents. Two blocks that render identical text but split it into
spans differently produce different caret references for the same visual position.

## Solution

Represent the text cursor / linear selection in a single canonical **flat**
coordinate: 0-based character offsets into the TextBlock's concatenated rendered
stream — the exact space `text_flat_offsets`
([Text.jl:755](../../package/visual/main/text/Text.jl#L755)) already defines and
that `TextRectangularReference`
([TextRectangularReference.jl](../../package/visual/main/text/TextRectangularReference.jl))
already uses for whole-element box highlights. We are **completing an existing
pattern**, not inventing a mechanism.

Two new pieces:

1. **`TextRangeReference(start, stop)`** — a text-domain reference step holding
   flat 0-based offsets. `start == stop` is the caret; `start < stop` is a linear
   selection. Sibling to `TextRectangularReference`; distinct type because the two
   route to *opposite* behaviours (rectangular ⇒ structural mode, decline char
   motion; range ⇒ the character cursor itself).

2. **`ReplaceTextRangeOperation`** — a text-domain edit expressed in flat
   coordinates. Unlike `ReplaceStringRangeOperation` it can span multiple
   spans/lines, which is what makes break/whitespace deletion expressible.

### Locked decisions

1. **Whitespace/break offsets are valid caret rests _and_ deletable.** The flat
   stream counts `TextNewline`/`TextSpacing`/`TextLine` indentation as characters
   (`text_flat_length`, [Text.jl:736-741](../../package/visual/main/text/Text.jl#L736-L741)),
   so the caret may rest on them. This is a capability *gain*: it lets the user put
   the caret on a break and delete it (e.g. join two lines). Deletability is
   decided by re-rooting — a range over a break that maps to a real underlying
   character edits it; a range over pure layout (syntax indentation, soft
   word-wrap break) has no pre-image and the edit declines at the lowering stage.
   This deletes the special boundary-skip code rather than adding to it.

2. **One canonical form.** Readers emit *only* the flat `TextRangeReference` form
   for text carets/selections. The structural `content{c}::Position` /
   `content[s:e]` cursor encoding is dropped, and its build/parse helpers
   (`_build_selection_path`, `_text_replace_path`, `_text_selection_range`,
   `_cursor_coord`, the structural branch of `text_selection_flat`) are deleted.

3. **A dedicated `ReplaceTextRangeOperation`.** Rather than lower flat→span at the
   reader and reuse `ReplaceStringRangeOperation`, the flat edit is a first-class
   operation. It is lowered to input-domain ops (`ReplaceStringRangeOperation` for
   the in-leaf case, structural ops for cross-boundary edits) at the syntax↔text
   seam where the span→input-reference mapping is known.

## Design detail

### The step

`TextRangeReference` mirrors `TextRectangularReference` exactly:

```julia
@cell_struct struct TextRangeReference <: ReferenceStep
    start::Int
    stop::Int
end
ReferenceModule.step_kind(::TextRangeReference) = :structural   # terminal, non-descending
ReferenceModule.evaluate_step(step::TextRangeReference, block) = ...  # Position(start) if caret, else (start,stop)
```

- Lives in the text slice (`package/visual/main/text/`), imported the same way
  `TextRectangularReference` is included in `ProjecturedVisual.jl`.
- `evaluate_step` legitimately consults the document (the TextBlock is `document`
  here) to stay evaluatable; the kernel reference layer never names it.
- `show`, `==`, and `annotate_reference_types` / `strip_reference_types` handling
  follow the rectangular precedent (a terminal step whose descended value is not a
  document node). The caret path collapses to just `::TextBlock ▸ TextRangeReference`
  — one structural step instead of the 3–4 today.

**Caret space definition (decision 1 made concrete).** The valid caret offsets
are `0 … text_flat_length(block)` inclusive. `_step_*` become `offset ± 1` with
clamping — the entire boundary-duplicate branch disappears. At a line break the
break occupies one flat position, so end-of-line-N (before the break) and
start-of-line-N+1 (after it) are *distinct adjacent* offsets, both reachable —
fixing the second bug for free.

### The operation

```julia
struct ReplaceTextRangeOperation <: Operation
    reference::ReferencePath   # rooted at a TextBlock, terminal TextRangeReference(start, stop)
    replacement::String
end
```

- Carries its flat range in the terminal `TextRangeReference` so the generic
  `reroot_operation` / `reroot_reference` prepend machinery
  ([Primitive.jl:224](../../package/base/main/document/Primitive.jl#L224)) applies
  unchanged, exactly like `ReplaceStringRangeOperation`.
- `evaluate_operation(editor, op::ReplaceTextRangeOperation)` handles the case
  where `editor.document` *is* a standalone TextBlock: resolve the flat range to
  the touched spans (via `text_flat_offsets`/`_flat_base`) and splice; a cross-span
  range becomes multiple span splices (+ element removal for a deleted break). For
  projected documents the op never reaches `evaluate_operation` as-is — it is
  lowered upstream (below).

**Blast-radius control — a shared abstract supertype.** The inventory shows the
majority of `ReplaceStringRangeOperation` sites are *generic* — they only prepend
steps to / backward-map `.reference` and rebuild the op (ReaderDefaults
[:35](../../package/base/main/projection/ReaderDefaults.jl#L35), ScreenToScreen,
clipboard reroot, WidgetToGraphics `_retarget_op`, and the domain rewrites in
versioning/workbench/markdown/book/yaml). Only ~6 stage handlers actually *parse
the single-span `.content[s:e]` shape* (via `_parse_text_elem_range`) and shift
char ranges. So introduce

```julia
abstract type ReplaceRangeOperation <: Operation end
struct ReplaceStringRangeOperation <: ReplaceRangeOperation … end
struct ReplaceTextRangeOperation   <: ReplaceRangeOperation … end
```

and rewrite the **generic** reroot/backward-map/passthrough methods against
`::ReplaceRangeOperation` (both carry `reference` + `replacement`, so the bodies are
identical). Then `ReplaceTextRangeOperation` rides all of them for free, and only
the span-local parsers need a new concrete method. This turns S6 from "~15 files"
into "~6 real handlers + retype the generics." `ReplaceNumberRangeOperation` can
join the same supertype opportunistically (it shares the shape) but is out of scope.

### Type taxonomy (three distinct things — do not collapse)

| Name | Kind | What it is | Role |
|---|---|---|---|
| `ReplaceStringRangeOperation` | concrete (**exists**) | edit a char range `[s:e]` within **one string field**; reference ends `FieldReference + RangeReference` | lower-layer currency; **unchanged, not renamed** |
| `ReplaceTextRangeOperation` | concrete (**new**) | edit a **flat range over a whole TextBlock**, may cross spans/lines; reference ends `TextRangeReference(s,e)` | text-layer op; lowered **into** the row above at the syntax seam |
| `ReplaceRangeOperation` | **abstract** (new) | supertype with **no instances, no behaviour** | dispatch grouping only |

- **`ReplaceRangeOperation` is not a rename of `ReplaceStringRangeOperation`.** It is a
  new abstract *parent* inserted above it: `ReplaceStringRangeOperation <:
  ReplaceRangeOperation`. `ReplaceStringRangeOperation` keeps its name and behaviour
  and stays the currency at the primitive/widget/base layers.
- **The abstract type covers *transport only*** — rerooting/backward-mapping the
  `reference`, which is byte-identical for both ops (both are just
  `(reference, replacement)`). It carries **no** resolution/apply/lowering logic;
  that is exactly what the two concrete ops differ on and dispatch separately for.
- **Why the concrete `ReplaceTextRangeOperation` is justified** (not just "reuse the
  string op with a `TextRangeReference` terminal"): dispatch is on the *op type*, not
  on the terminal step (a runtime value inside `ReferencePath`), so one op would force
  an `if terminal isa TextRangeReference …` branch into every span-local handler; and
  a distinct type makes the "flat op must be lowered before reaching the base" invariant
  type-checked — a leaked flat op is an immediate `MethodError`, not a silent
  `_split_replace_reference` no-op.
- **The abstract type is optional convenience.** Its only job is to avoid duplicating
  the generic transport methods; a `Union{…}` alias or duplicated methods are
  equivalent. The *concrete* new op is required regardless.

### Lowering & threading

The flat text coordinate is meaningful only inside text-domain documents. A flat
edit is remapped across the text→text stages and **lowered at the syntax↔text
seam**, where the span→input mapping exists:

- **Text→text stages** (`WordWrapping`, `TextFiltering`, `SelectionInverting`):
  remap the flat offsets between output and input TextBlock (unwrap word-wrap,
  invert filtering/splitting). These stages already remap
  `ReplaceStringRangeOperation` references; they gain a `ReplaceTextRangeOperation`
  method that transforms `start`/`stop` instead of the `.content[range]` suffix.
- **Syntax→text** (`SyntaxLeafToText`, `SyntaxCompoundToText`): the lowering point.
  `SyntaxCompoundToText.read_intent(ReplaceStringRangeOperation)`
  ([SyntaxToText.jl:865](../../package/visual/main/syntax/SyntaxToText.jl#L865))
  **already** converts an incoming reference to flat offsets and dispatches to the
  child zone / separator / chrome. A `ReplaceTextRangeOperation` arrives *already
  flat*, so it skips the parse+`_text_elem_path_to_flat` step and reuses the same
  zone dispatch. The in-leaf case lowers to `ReplaceStringRangeOperation` (today's
  behaviour); a cross-child / cross-break range lowers to a `CompoundOperation`
  or a structural op (new capability); pure-chrome offsets decline.
- **clipboard / widget** (`ClipboardToAny`, `ObjectToWidget`,
  `ProjectionConfiguring`): mirror their existing `ReplaceStringRangeOperation`
  reroot/handlers for the new op.

The **forward** direction of the syntax↔text reference map (projecting a base
selection *down* to a text caret for rendering) now emits
`TextRangeReference(flat, flat)` instead of the structural cursor path.

### Rendering

The caret rect reuses the flat→pixel path that already serves the rectangular
highlight: `_highlight_char_range`
([TextToGraphics.jl:1019](../../package/visual/main/text/TextToGraphics.jl#L1019))
recognises `TextRangeReference` (caret ⇒ `start == stop`), and
`_compute_highlight_geo` / `_seg_cursor_x` place the pixel via `span_flat_offsets`
([TextToGraphics.jl:1043](../../package/visual/main/text/TextToGraphics.jl#L1043)).
This *simplifies* the render layer: `_layout_overlay`
([:561](../../package/visual/main/text/TextToGraphics.jl#L561)) currently derives
`cursor_pos = _cursor_coord(sel)` and `_layout_group`
([:526](../../package/visual/main/text/TextToGraphics.jl#L526)) places the caret
from the span-local `cursor_pos.char - seg_char_start`. With a flat caret both drop
the span-local arithmetic and use the absolute offset the highlight path already
computes; the Up/Down/Home/End line-motion readers
([:156-200](../../package/visual/main/text/TextToGraphics.jl#L156)) likewise switch
from `sc.span_path == current.span && sc.char_start <= current.char <= sc.char_end`
to a flat-offset comparison. The span-local cursor computation is deleted.

## Open semantic questions (recommended answers)

- **Break deletion vs. structural mutation.** Deleting a content newline inside a
  multiline string ⇒ a `ReplaceStringRangeOperation` on that string. Deleting a
  break *between* two syntax children (array elements on separate lines) ⇒ a
  structural syntax edit or a decline — **recommend: decline for v1**, land the
  in-string and single-line cases first, add cross-element joins later.
- **Multi-span selections.** A flat range crossing spans is now representable.
  **Recommend:** support it for rendering/copy immediately (geometry already
  handles it), but lower cross-span *edits* to a `CompoundOperation` only where all
  touched spans share one input string; otherwise decline in v1.
- **`ReplaceNumberRangeOperation`.** Number leaves use the sibling number op. Keep
  them string-range-based for now; the flat cursor still *selects* them, and the
  edit lowers through `SyntaxLeafToText` to the number op unchanged.

## Progress & resumption notes (live)

### Edit milestone + rename — status (latest)

**Done & verified (committed on `text-range-reference`):**
- **Nav milestone** — GREEN. `test_position_navigations` 0 Fail / 0 Error / 8 Broken;
  zero regressions vs base commit (verified side-by-side). 11 direction-stall
  `@test_broken`s in `test_text_nav_invariants` now *pass* — the flat cursor fixed
  the direction-dependence (the original bug), confirmed at the sweep level.
- **Edit machinery (S5+S6)** — `_text_insert`/`_text_delete` emit
  `ReplaceTextRangeOperation`; `TextToGraphics._gesture_op` lowers it to the
  structural single-span `ReplaceStringRangeOperation` over its input block via
  `_lower_text_range` (so the whole existing edit chain carries it up unchanged;
  cross-span declines, v1). Verified: json 160/0, xml 516/0, syntax full, text 449/0,
  word_wrapping 335/0 typein.
- **Text-document typein** — the test now builds a flat caret for a `.content`
  span target (`_flat_typein_sel` in TypeinTest).
- **Empty-string regression fixed** — `_flat_to_span_char` anchors on the first span
  when all spans are empty (an undelimited `""`), restoring the caret.
- **T1 rename** — `TextRectangularReference` → `TextSpanReference` (variant 3),
  per [text-selection-variants.md]; pure rename, verified.

**Remaining — ALL DONE (this session):**
1. **nav-invariants reconciliation — DONE** (commit `6d22c03e`). Re-derived the
   `nav_broken` registry from an empirical per-example walk (verified byte-identical
   on the pre-change tree, so the flat caret does not touch the walk — the registry
   was merely stale). Dropped the 11 now-passing markers (`json_insertion`, `syntax`,
   `focusing`, `sql_syntax`, `dragging` from `NAV_LEFT_WALK_STALLS`; `yaml` from
   `NAV_RIGHT_WALK_MISSES_END`); added `text`/`text_with_image`/`markdown_rendered`;
   new `NAV_LEFT_WALK_CYCLES` + a maskable `:cycle_left`/`:cycle_right` symbol for the
   leftward cycle; `searching` now throws both directions. Sweep: 220 pass / 25 broken
   / 0 fail. **The leftward incompleteness/cycle is a pre-existing projection
   round-trip issue on introduced-chrome carets — out of scope for the flat caret**
   (tracked in `left-motion-stalls-on-introduced-text.md`).
2. **Structural-shape test migration — DONE** (commit `80f12607`). Migrated TextTest,
   WordWrapping/TextHighlighting/SelectionInverting/TextFiltering round-trips,
   TextToGraphics (TextLine layout + inline-image hit-test), WidgetTextEdit to the flat
   caret. DocumentInsertion/XmlToSyntax/TypeReference needed **no** change (they test
   unchanged structural paths; the insertion caret is legitimately structural and its
   editing now works via the `_text_flat_selection` widening below). Source change:
   `_text_flat_selection` now also canonicalises a structural `.content{a:b}` caret to
   flat, so readers accept any selection form (fixes arrow-after-edit on the direct
   WidgetText→Text chain, which has no re-projection to re-flatten a value edit's
   structural caret).
3. **S8 cleanup — DONE** (commit `8a16e76a`). Deleted the three truly-dead helpers
   (`_build_selection_path`, `_cursor_coord`, `_text_span_text`) + the orphaned
   `@reference`/`@reference_case`/`Position` imports. **Kept** (still load-bearing):
   `_text_replace_path` (→ `_lower_text_range`), `_text_selection_range` (→
   `text_selection_flat` structural branch + `_text_flat_selection`), `_elements_prefix`,
   `_is_structural_selection`.
4. **Variants T2–T4 — DONE** (commit `fb895d4d`, over the plan
   `text-selection-variants.md`). T2: `_compute_highlight_geo` → `_compute_span_geo`.
   T3: reserved `TextColumnReference` (type + wiring + `_compute_column_geo`,
   unit-tested). T4: `_is_structural_selection` treats it as structural. **Deferred:**
   the live `_layout_overlay` column render (needs a per-row rect vector — the same
   render path a multi-line stream highlight needs, best validated against a producer).
5. **Console text edit — regression found + partially fixed** (commit `339bbe2d`). The
   full domain sweep caught that the edit milestone's "lower the flat op at
   TextToGraphics" broke the **console** pipeline (no TextToGraphics stage): the flat
   `ReplaceTextRangeOperation` reached SyntaxToText unlowered and was dropped. Taught
   `SyntaxLeafToText`/`SyntaxCompoundToText` to lower it against their own output →
   **console insert restored**. Console **backspace** stays `@test_broken`: it is a
   value↔chrome boundary delete whose flat range starts on the open-quote boundary, so
   `_lower_text_range` declines it as cross-span — the same v1 limitation the SDL typein
   already marks broken, pending the cross-span / multi-span edit pass.

**Still deferred (out of scope, not blockers):**
- **TextFirstLine** selection threading (only widget/conversation chains).
- **Variant 1 stream + variant 2 live column render** — the per-row rect overlay
  (`_compute_stream_geo` / wiring `_compute_column_geo` into `_layout_overlay`).
- **Cross-span / multi-span text edits** (value↔chrome boundary deletes) — the v1
  `_lower_text_range` declines them; this is the single deferred edit feature and would
  deliver on the "break/whitespace offsets are deletable" decision. Needs a
  boundary-aware range-start resolution (prefer the later span) + SDL @test_broken
  reconciliation.

**Full-suite verification (this session):** visual `47137 / 0 fail / 0 error / 1 broken`;
domain `102310 / 0 fail / 0 error / 10 broken`; nav-invariants `220 / 0 fail / 25 broken`;
console `34 / 0 fail / 2 broken`; full-stack json/xml/yaml typein+nav `0 fail`.



**Branch:** `text-range-reference` (worktree `/home/projectured/workspace/pjed-text-range`).
**Nav-first milestone: COMPLETE and verified.** Committed: S1 (step), S2 (op +
supertype), S3+S4 (text-layer flat cursor + render), SyntaxToText selection maps,
shared flat↔element helpers, and all text decorators (WordWrapping, TextHighlighting,
SelectionInverting, TextFiltering, LineNumbering).

**Verification (`--project=.`, i.e. repo root; the umbrella `package/projectured/test`
env does NOT resolve — use root):**
- `reverse(left)==right` proven on the "ab"/"cd" block (the original bug).
- `test_syntax_to_text` green.
- Broad `explore_position_selections` sweep over every navigable example:
  **32 navigate cleanly (0 errors, >0 states)**; the only 8 that don't are all
  **pre-existing known-broken** on main — their error signatures match the sweep's
  own `posnav_seed_broken`/`posnav_throws_broken` registries exactly
  (graph/collection/searching/rotating_vector/conversation_editor/filesystem/
  natural/navigator). **Zero regressions.**
- The 5 examples that temporarily broke mid-migration (text, word_wrapping,
  line_numbering, text_filtering, text_highlighting) all navigate again.

**Remaining (edit milestone, deferred):** S5 (edit readers emit
`ReplaceTextRangeOperation`), S6 (retype generics to `ReplaceRangeOperation` +
flat-aware handlers + lowering at SyntaxToText), S7 tests (flip nav-invariants to
assert full `reverse==`; migrate structural-shape expectations incl. the literal
string in DocumentInsertionTest), S8 cleanup (delete `_cursor_coord`,
`_build_selection_path`, `_text_selection_range`, `_text_replace_path`,
`_text_span_text`; also TextFirstLine selection threading, deferred — only in
widget/conversation chains).

**Key finding — flat-space consistency across stages (must respect when threading).**
Two flat spaces are in play and they only coincide at some stages:
- *Text-layer* flat (`_flat_base`/`text_flat_offsets`): **break/indentation-aware**
  (counts TextNewline, TextSpacing, TextLine indentation, implicit inter-line break).
  This is what `TextRangeReference` offsets are in.
- *SyntaxToText internal* flat (`_text_elem_path_to_flat`/`_flat_to_text_elem_path`):
  **span-content-only** (sums `length(content)`), and asserts every element is a
  `TextString`. So at the SyntaxToText **output** there are no breaks/indentation —
  the two spaces **coincide there**. Line breaks/indentation are introduced by
  *later* stages (WordWrapping soft breaks, LineNumbering, multi-line formatting),
  where the two spaces **diverge** and the stage's flat remap must bridge them.

Implication for threading: at SyntaxToText, changing the path *shape*
structural→`TextRangeReference` suffices (flat values already match). At
break-introducing decorators, the forward/backward maps must convert between the
break-aware outer offset and the inner offset (they already do an analogous remap
for the structural form — reuse that arithmetic, just carry a flat step).

**Remaining work (large):**
1. *Selection threading* — SyntaxToText (leaf/compound/list `map_reference_forward`
   + `map_reference_backward`, `_compose_node_selection`, click resolution) then the
   text→text decorators. Unlocks projected-doc navigation.
2. *Edit threading* — S5 (edit readers emit `ReplaceTextRangeOperation`) + S6
   (retype generics to `ReplaceRangeOperation`; flat-aware handlers at the ~6
   span-local sites; lowering at SyntaxToText).
3. *S7 tests* / *S8 cleanup* (delete `_cursor_coord`/`_build_selection_path`/
   `_text_selection_range`/`_text_replace_path`, `_text_span_text`; flip nav-invariants
   to assert full `reverse==` ; migrate structural-shape test expectations incl. the
   literal string in DocumentInsertionTest).

## Staged implementation

Each stage is one or more commits; run the narrowest test after each.

- [x] **S1 — step type.** Add `TextRangeReference` + `step_kind` / `evaluate_step`
  / `show` / `==`; wire `annotate/strip_reference_types`. Unit-test the step in
  isolation. *(no behaviour change yet)* — **Done.** New file
  `text/TextRangeReference.jl` (mirrors `TextRectangularReference`); `evaluate_step`
  returns `Position(start)` for a caret and `(start,stop)` for a range; generic
  `annotate/strip` need no special-casing (verified `strip` → `⌶{3}`). Prints
  `⌶{s}` / `⌶{s:e}`. Layering guard passes with it in the qualified-files set.
- [x] **S2 — operation type.** Add `ReplaceTextRangeOperation` + `evaluate_operation`
  (standalone-TextBlock case) + `reroot_operation` / `reroot_reference`. — **Done.**
  `abstract type ReplaceRangeOperation <: Operation` added in `PrimitiveModule`;
  `ReplaceStringRangeOperation` reparented onto it (dispatch-neutral — no method
  targets the abstract type until S6). `ReplaceTextRangeOperation` defined in the
  text slice, subtyping it, `(reference, replacement)` shape with a terminal
  `TextRangeReference`. Canonical flat space is the **break/indentation-aware**
  `text_flat_offsets`/`_flat_base` space (matches render + `text_selection_flat`),
  *not* the content-only `_text_span_infos` sum used by the existing
  `splice_value!(::TextBlock)`. `evaluate_operation` handles the in-span case and
  declines off-span/cross-span (v1). Verified: reroot, insert, range-replace,
  flat post-caret.
> **Staging correction (discovered during implementation).** The real commit
> boundaries are **selection migration** and **edit migration**, not S3/S4/S5/S6.
> `ReplaceSelectionOperation` threads *up* through every stage via
> `map_reference_backward` (ReaderDefaults:36) and *down* via `map_reference_forward`,
> so projected-doc **navigation** needs every text-producing stage (SyntaxToText +
> the text→text decorators) to read/emit the flat `TextRangeReference`, not just the
> text layer. S3+S4 (text-layer cursor + render) only makes **standalone TextBlock**
> navigation work; the stage selection-maps are the rest of the selection chunk.
> The good news: those stages already convert `(span,char)↔flat`
> (`_text_elem_path_to_flat`/`_flat_to_text_elem_path` in SyntaxToText), so emitting/
> reading the flat step *directly* is mostly a **simplification** of each map.

- [x] **S3 — flat caret + motion (text layer).** — **Done.** Deleted
  `_step_left/_step_right/_char_*/_word_step_*` (boundary-skip gone); motion is now
  `±1` clamp in the flat stream (`_text_char_motion`), word motion over `_flat_chars`
  (`_word_left/right_flat`), `_text_jump` → flat `0`/`total`. Producers emit
  `_flat_caret_ref` (a `TextRangeReference`). Added `_text_flat_total`, `_flat_chars`,
  `_text_flat_selection`, `_flat_cursor_coord`. **Verified on the "ab"/"cd" two-line
  block: `reverse(left-walk) == right-walk` — the original boundary-duplicate bug is
  fixed.** `_cursor_coord`/`_build_selection_path` now dead (removed in S8).
- [x] **S4 — render (text layer).** — **Done.** `_layout_overlay` derives the caret
  `(span,char)` from the flat selection via `_flat_cursor_coord`/`_flat_to_span`
  (keeping `_layout_group`'s geometry); graphics producers (click, line-motion,
  `_translate_click`) convert their `(span,char)` hit to flat via `_flat_hit_op`
  (`_flat_base`+`_flat_caret_ref`); `_highlight_char_range` recognises a
  `TextRangeReference` range. *Known v1 limitation:* a caret in a break/indentation
  gap has no owning span → renders invisibly (nav tests tolerate a `nothing` caret).
  *TextGraphics flat-length skew* (`text_flat_length`=0 vs render `_box_flat_length`=1)
  left unaligned — only affects graphics-in-text; reconcile later.
- [x] **Selection threading (SyntaxToText).** Done — see the SyntaxToText commit;
  `test_syntax_to_text` green.
- [~] **Selection threading (decorators).** Nav-suite ground truth: 6 examples
  navigate cleanly with no decorator work (plain_text, syntax, json, xml, yaml,
  markdown); 5 fail at the seed because a decorator can't read the flat caret
  (text→WordWrapping, word_wrapping, line_numbering, text_filtering, text_highlighting).
  Shared helpers `text_flat_to_elem`/`text_elem_to_flat` added; each decorator's
  selection map now reads the flat caret, remaps `(element,char)` through its
  seg/kept/mapping table, and re-emits flat. **Done:** WordWrapping, LineNumbering.
  **In progress:** TextHighlighting, SelectionInverting, TextFiltering.
  **Deferred:** TextFirstLine (only in widget/conversation chains, not a nav example).
- [x] **S5 — edit readers. DONE** (edit milestone). `_text_insert`/`_text_delete` emit
  `ReplaceTextRangeOperation`; backspace/delete flat semantics incl. crossing a
  break (per decision 1 / open questions). Cross-span/boundary deletes still v1-decline.
- [x] **S6 — threading & lowering. DONE** (edit milestone; console lowering seam
  added this session, `339bbe2d`). (a) Introduce `abstract type
  ReplaceRangeOperation` and retype the *generic* reroot/backward-map/passthrough
  methods (Primitive reroot, ReaderDefaults, ClipboardToAny reroot, WidgetToGraphics
  `_retarget_op`, ScreenToScreen, the domain rewrites) onto it — both ops then ride
  them unchanged. (b) Add real flat-aware `ReplaceTextRangeOperation` methods to the
  ~6 span-local parsers: the lowering seam (`SyntaxLeafToText`,
  `SyntaxCompoundToText`), the char-range shifters (`SelectionInverting`,
  `TextFiltering`, `WordWrapping`, `TextHighlighting`, `TextFirstLine`), the widget
  readers (`ObjectToWidget`, `ProjectionConfiguring`), and `evaluate_operation` in
  Primitive.jl. See inventory §C for the split.
- [x] **S7 — tests. DONE** (`80f12607`, `6d22c03e`). Migrated every test hard-coding
  the structural cursor to the flat caret; reconciled the `nav_broken` registry
  (empirically, from a per-example walk) rather than asserting a full
  `reverse(left) == right` — the leftward introduced-caret asymmetry is pre-existing
  and stays `@test_broken` (masked, incl. the new cycle mode). `test_typein` /
  `test_position_navigation` were already flat from the edit milestone.
- [x] **S8 — delete dead code. DONE** (`8a16e76a`). Removed `_build_selection_path`,
  `_cursor_coord`, `_text_span_text` + orphaned imports. **Kept** `_text_replace_path`
  (→ `_lower_text_range`), `_text_selection_range` + the structural branch of
  `text_selection_flat` (→ `_text_flat_selection` canonicalises a structural caret to
  flat, a robustness the console/insertion paths rely on) — decision-2's "one
  canonical form" holds at the *output* (readers always re-emit flat) without deleting
  the structural *reader*.

## Migration inventory (touch list)

Exhaustive; grouped by role. The canonical caret being replaced is
`::TextBlock.elements::CellVector[i]::TextString.content::String{c}::Position`
(block-level) or the in-line `…TextLine.elements::CellVector[j]::TextString.content…`
form; the range form ends `.content[s:e]`.

### A. Producers of the structural cursor/range path → emit flat instead

*text/Text.jl:* `_build_selection_path`
([:699-713](../../package/visual/main/text/Text.jl#L699)) — the canonical builder;
`_text_selection_range` ([:598-628](../../package/visual/main/text/Text.jl#L598));
`_text_replace_path` ([:630-633](../../package/visual/main/text/Text.jl#L630));
`_elements_prefix` ([:637-644](../../package/visual/main/text/Text.jl#L637));
`_cursor_coord` ([:683-689](../../package/visual/main/text/Text.jl#L683), the
`content{c}` `@reference_case`); `_is_structural_selection`
([:693-697](../../package/visual/main/text/Text.jl#L693)); callers
`_text_insert`/`_text_delete`/`_text_jump`/`_text_word_motion`/`_text_char_motion`
([:503-574](../../package/visual/main/text/Text.jl#L503)); the `@gestures TextBlock`
table ([:377-386](../../package/visual/main/text/Text.jl#L377)); `@insertion TextBlock`
default caret ([:317](../../package/visual/main/text/Text.jl#L317)).

*text/TextToGraphics.jl (cursor produced from graphics):* click →
`_build_selection_path` at [:126](../../package/visual/main/text/TextToGraphics.jl#L126)
and `_translate_click` [:952](../../package/visual/main/text/TextToGraphics.jl#L952);
Home/End [:169](../../package/visual/main/text/TextToGraphics.jl#L169); Up/Down
[:200](../../package/visual/main/text/TextToGraphics.jl#L200).

*text/PrimitiveToText.jl (the `PrimitiveString.value[range]` value-domain vocabulary
a leaf edit maps through — interacts but is not the TextBlock caret):* fwd/bwd maps
[:37-57](../../package/visual/main/text/PrimitiveToText.jl#L37); `_string_value_path`
[:164](../../package/visual/main/text/PrimitiveToText.jl#L164); `@gestures
PrimitiveString` + `_string_delete` [:177-201](../../package/visual/main/text/PrimitiveToText.jl#L177).

### B. Forward reference-map sites (selection projected DOWN to text) → emit `TextRangeReference`

Each text-domain projection has a `_forward_map` emitting the structural
`_text_elem_path`; each also passes `TextRectangularReference`/`∅` through unchanged
(no change needed for those):

- *SyntaxToText.jl:* local emitter `_text_elem_path`
  [:1393](../../package/visual/main/syntax/SyntaxToText.jl#L1393);
  `map_reference_forward(::SyntaxLeafToText)` [:89](../../package/visual/main/syntax/SyntaxToText.jl#L89);
  `print_document(::SyntaxLeafToText)` selection cell
  [:125](../../package/visual/main/syntax/SyntaxToText.jl#L125);
  `map_reference_forward(::SyntaxCompoundToText)` [:331-370](../../package/visual/main/syntax/SyntaxToText.jl#L331)
  (**already emits `TextRectangularReference` at [:363](../../package/visual/main/syntax/SyntaxToText.jl#L363)**);
  `_shift_own_flat`/`_shift_child_cursor` [:265](../../package/visual/main/syntax/SyntaxToText.jl#L265);
  `_compose_node_selection` [:702-727](../../package/visual/main/syntax/SyntaxToText.jl#L702);
  `map_reference_forward(::SyntaxListToText)` [:955](../../package/visual/main/syntax/SyntaxToText.jl#L955).
- *text→text stages* (each `_forward_map` + selection cell): WordWrapping
  [:237-335](../../package/visual/main/text/WordWrapping.jl#L237), TextFiltering
  [:150-206](../../package/visual/main/text/TextFiltering.jl#L150), SelectionInverting
  [:218-287](../../package/visual/main/text/SelectionInverting.jl#L218), TextHighlighting
  [:199-267](../../package/visual/main/text/TextHighlighting.jl#L199), TextFirstLine
  [:172](../../package/visual/main/text/TextFirstLine.jl#L172), LineNumbering
  [:110](../../package/visual/main/text/LineNumbering.jl#L110).

### C. `ReplaceStringRangeOperation` handlers

**Generic (retype to `::ReplaceRangeOperation`, then free for both ops):**
Primitive.jl reroot [:226](../../package/base/main/document/Primitive.jl#L226);
ReaderDefaults [:35-88](../../package/base/main/projection/ReaderDefaults.jl#L35);
ClipboardToAny reroot [:595](../../package/visual/main/clipboard/ClipboardToAny.jl#L595);
WidgetToGraphics `_retarget_op` [:761](../../package/visual/main/widget/WidgetToGraphics.jl#L761);
ScreenToScreen [:202](../../package/visual/main/backend/ScreenToScreen.jl#L202);
domain rewrites — versioning [:259](../../package/domain/main/versioning/VersioningToAny.jl#L259),
workbench [:677](../../package/domain/main/workbench/WorkbenchToWidget.jl#L677),
markdown [:309+](../../package/domain/main/markdown/MarkdownToSyntax.jl#L309),
book [:245+](../../package/domain/main/book/BookToSyntax.jl#L245),
yaml [:239](../../package/domain/main/yaml/YamlToSyntax.jl#L239),
insertion [:270](../../package/domain/main/insertion/InsertionToSyntax.jl#L270);
FileSystemToSyntax declines [:104](../../package/domain/main/filesystem/FileSystemToSyntax.jl#L104).

**Span-local parsers (need a real flat-aware `ReplaceTextRangeOperation` method):**
- `evaluate_operation` + `_split_replace_reference`
  [Primitive.jl:119-184](../../package/base/main/document/Primitive.jl#L119) — needs a
  flat→field-value resolver for the standalone-TextBlock path.
- **The lowering seam** `SyntaxCompoundToText.read_intent(::ReplaceStringRangeOperation)`
  [SyntaxToText.jl:865-925](../../package/visual/main/syntax/SyntaxToText.jl#L865)
  (already flat→child dispatch — the flat op skips its parse step) and
  `SyntaxLeafToText` [:150](../../package/visual/main/syntax/SyntaxToText.jl#L150).
- Char-range shifters (all use `_parse_text_elem_range`, all single-span today):
  SelectionInverting [:260](../../package/visual/main/text/SelectionInverting.jl#L260),
  TextFiltering [:182](../../package/visual/main/text/TextFiltering.jl#L182),
  WordWrapping [:296](../../package/visual/main/text/WordWrapping.jl#L296) (already
  rejects cross-span), TextHighlighting [:241](../../package/visual/main/text/TextHighlighting.jl#L241),
  TextFirstLine [:152](../../package/visual/main/text/TextFirstLine.jl#L152).
- Widget: ObjectToWidget [:289](../../package/visual/main/widget/ObjectToWidget.jl#L289),
  ProjectionConfiguring [:107](../../package/visual/main/widget/ProjectionConfiguring.jl#L107).

### D. Render (text/TextToGraphics.jl)

`SegCoord` [:56](../../package/visual/main/text/TextToGraphics.jl#L56);
`_layout_overlay` (`_cursor_coord`, `span_flat_offsets`, `_highlight_char_range`,
`_compute_highlight_geo`) [:561-587](../../package/visual/main/text/TextToGraphics.jl#L561);
`cursor_rect`/`highlight_rect` overlays [:259-269](../../package/visual/main/text/TextToGraphics.jl#L259);
`_layout_group` span-local caret placement [:449-535](../../package/visual/main/text/TextToGraphics.jl#L449);
`_seg_cursor_x` [:892](../../package/visual/main/text/TextToGraphics.jl#L892);
`_highlight_char_range` [:1019](../../package/visual/main/text/TextToGraphics.jl#L1019)
(extend to `TextRangeReference`); `_compute_highlight_geo` [:1043](../../package/visual/main/text/TextToGraphics.jl#L1043).

### E. Reused flat infra (no change, or simplify)

*text/Text.jl:* `text_flat_length` [:736](../../package/visual/main/text/Text.jl#L736),
`text_flat_offsets` [:744](../../package/visual/main/text/Text.jl#L744),
`text_selection_flat` [:767](../../package/visual/main/text/Text.jl#L767) (drop its
structural branch — decision 2), `_flat_base` [:798](../../package/visual/main/text/Text.jl#L798),
`text_selection_substring` [:658](../../package/visual/main/text/Text.jl#L658).
*SyntaxToText.jl:* `_flat_to_text_elem_path` / `_text_elem_path_to_flat`
[:1455-1485](../../package/visual/main/syntax/SyntaxToText.jl#L1455), the `_syntax_to_flat`
family [:1159-1315](../../package/visual/main/syntax/SyntaxToText.jl#L1159).
*TextToGraphics.jl:* `span_flat_offsets` build + `_box_flat_length`
[:564-594](../../package/visual/main/text/TextToGraphics.jl#L564).

### F. Tests to update (expectations keyed on the structural shape)

- Direct builder/parser assertions: TextTest.jl
  [:68-126](../../package/visual/test/document/TextTest.jl#L68); TextToGraphicsTest.jl
  [:219-328](../../package/visual/test/projection/TextToGraphicsTest.jl#L219).
- Round-trip `content{c}`/`content[s:e]` shape: TextFilteringTest, SelectionInvertingTest,
  TextHighlightingTest, WordWrappingTest, PrimitiveToTextTest, ObjectToWidgetTest,
  WidgetTextEditTest, PrimitiveTest (all under `package/visual/test/projection` &
  `.../document`).
- Domain: SyntaxTreeSelectionTest.jl [:107-131](../../package/domain/test/projection/SyntaxTreeSelectionTest.jl#L107)
  (`TextRectangularReference` — unchanged, good regression anchor); **DocumentInsertionTest.jl
  [:134-152](../../package/domain/test/projection/DocumentInsertionTest.jl#L134) asserts the
  literal string `"::TextBlock…content::String{0}::Position"`** — must change;
  TypeReferenceTest.jl [:123](../../package/domain/test/reference/TypeReferenceTest.jl#L123).
- Drivers/sweeps: NavigationPresets.jl, TypeinTest.jl, ClickRoundtripTest.jl, and
  ExampleSweeps.jl [:141-467](../../package/projectured/test/editor/ExampleSweeps.jl#L141).

## Risks

- **Bidirectional coverage.** Every stage that maps the cursor *down* (forward, §B)
  and the edit *up* (backward, §C) must agree on the flat coordinate. The
  single-source `text_flat_offsets` mitigates drift, but each stage needs a
  round-trip test. The §B forward surface is broad (SyntaxToText + 6 text→text
  projections) — this is the larger half of the work, and mostly mechanical
  (swap the `_text_elem_path` emitter for a flat one).
- **Scope of S6.** With the `ReplaceRangeOperation` supertype the *backward* threading
  is ~6 real handlers, not ~15 — the generics are retyped once. If a stage is missed,
  edits/selection silently no-op there — cover with a full-stack `test_example` per
  domain, not just single-stage tests (single-stage tests miss chain rules).
- **Cross-span operations are new.** Every §C span-local handler currently assumes one
  span; WordWrapping already `return nothing`s on cross-span. Until each learns the
  multi-span case, a cross-span `ReplaceTextRangeOperation` must decline rather than
  corrupt — enforce with an explicit v1 guard (open question 2).
- **Sealed files.** None of the target files are sealed today, but
  `cell/` and `reference/ReferenceLayer.jl` are; `TextRangeReference` lives in the
  visual tier and needs no kernel edits, keeping clear of the seal.
