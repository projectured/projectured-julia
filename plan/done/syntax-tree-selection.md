# Syntax Tree Selection (whole-element) — done

**Status: done.** Selecting a *whole* syntax element — a full `SyntaxNode`,
`SyntaxLeaf`, or wrapper — as a single unit, in addition to the character-level
cursor selections that already existed. The data model, forward/backward mapping,
region-box rendering, and the keyboard **and** mouse interaction all shipped.

Two stretch slices remain deferred and are tracked separately in
[`syntax-tree-selection.md`](../pending/syntax-tree-selection.md) (range /
multi-element text selection; wrapped-text `ListNode` highlight).

## Motivation

A selection inside the syntax domain used to always land *inside* a leaf or node
(a character cursor in a delimiter/value, or a child index). There was no way to
say "the entire `[1, 2, 3]` array node is selected" as one atom. Whole-element
selection is the basis for structural navigation, subtree highlighting, and clean
backward/forward mapping between a domain element and its text.

## Data model — the empty-path (`∅`) convention

Chose the **empty-path convention** over a dedicated marker step. A whole-element
selection is **not a distinct reference step**; it is a path that terminates *at*
the element, i.e. an `EmptyReferencePath` (`∅`). The one node whose `selection`
cell holds `∅` is the wholly-selected one; ancestors hold a non-empty path routing
down to it, descendants hold `nothing`. A `SelfReference` marker was built first
and then removed — an unnecessary extra degree of freedom, since tree position
already disambiguates and `evaluate_reference(doc, ∅)` already returns the element.

What shipped:

1. No new reference type — `evaluate_reference(document, EmptyReferencePath())`
   already returns the element itself.
2. `set_selection!` / `replace_selection!` / `clear_selection!` accept
   `∅`-terminated paths unchanged (the `∅` terminal falls through their
   `path isa ConcreteReferencePath || return` guard).
3. `@reference_case` gained a writable **empty-path pattern** `∅`
   (`∅ => @reference()` maps a whole-element selection through as identity).
4. Selection mappers carry `∅` both ways. `@reference_case`-based mappers use the
   `∅ => @reference()` branch; the flat-offset mappers and printer cells keep a
   small `x isa EmptyReferencePath && return @reference()` guard. A whole
   `JsonArray` / `JsonObject` / `SyntaxLeaf` round-trips `∅`; a *nested* whole-child
   survives the syntax level as `.children[i]` terminating in `∅` and back to
   `.elements[i]`.
5. Tests: `test/src/projection/SyntaxTreeSelectionTest.jl`
   (`test_syntax_tree_selection`).

**Resolved open question.** *Does whole-element selection need a dedicated
reference step?* At the document/syntax level **no** — it is `∅`, and the default
`map_reference_forward`/`backward` plus the `@reference_case` `∅` pattern pass it
through, so any domain (XML, filesystem, …) inherits whole-element selection for
free. **The Text layer is the exception** (see below).

## Visualization — region box

A whole-element selection draws as one translucent, rounded `GraphicsRect` over
the **bounding box** of the selected element's text. A single-line leaf gets a
tight box; a multi-line node gets a bounding box hugging the indented block.
(Alternatives weighed and rejected: text polygon — looks like a character drag;
gutter bar — imprecise; stroked outline — needs a stroke primitive.)

### Text-domain representation

A `RangeReference` is **not** reused — that single-axis form is for a character
range within one span. The multi-span Text forms get their own step, carrying two
flat char indices (offsets from the start of the `TextText`, counting straight
through every span; 0-based, half-open `[start, end)`):

```
TextRectangularReference(start, end)   # → axis-aligned bounding box (structural box)  ✅ built
TextRangeReference(start, end)         # → ragged text-flow polygon (char range)        ⏳ deferred
```

Path shape: a single top-level step on the `TextText`, e.g.
`ConcreteReferencePath(TextRectangularReference(start, end), ∅)` — not under
`elements[i]`, since the offsets are flat across all spans.

Cases handled:

- **Whole element at the top of what a projection prints** → arrives as `∅` on the
  whole `TextText`; `SyntaxLeafToText` and `SyntaxNodeToText` already map a `∅`
  input selection forward to `∅` output. TextToGraphics normalizes `∅` to the full
  range `(0, N)` — no new step needed.
- **A wholly-selected *nested* child** → what `∅` cannot express (it means the
  *whole* TextText). The parent flattens its subtree into one flat `TextText`, so
  child *i* occupies a flat sub-range `[start, end)`. `_syntax_to_flat` returns
  that descendant's flat range and `SyntaxNodeToText`'s selection cell emits
  `TextRectangularReference(start, end)` — no new bookkeeping, `child_char_ranges`
  already holds the extent. This is why the Text layer needs the dedicated step
  even though `∅` suffices everywhere else: flattening *destroys* the per-child
  grouping, so the step re-supplies the flat extent (data, not redundancy).

### Where / how it is drawn

`TextToGraphics.projection_print` (the only layer with pixels) introduces the
rectangle inside the `both` cell, the same site as the cursor rect.
`_selection_range` normalizes both box forms to a flat char range (`∅` ⇒ `(0, N)`;
`TextRectangularReference(s, e)` ⇒ `(s, e)`), converts to pixels via the existing
per-segment measurement, computes the bounding box, and emits a translucent
`GraphicsRect`. A box selection draws a box and no cursor; a point selection draws
a cursor — mutually exclusive.

The highlight goes in its **own `GraphicsCanvas` layer** behind the text layer, so
the text segment list is byte-for-byte unchanged and `char_to_coord` ↔ element
indexing stays pristine (keyboard nav / `_hit_segment` untouched). Hit-testing in
`GraphicsCanvasToGraphicsImage.projection_read` is **topmost-first** (a single
reverse scan returning the first element whose bounds contain the click), so a
click on a glyph lands on the text painted over the highlight — this also subsumed
the old "rects first" intent and fixed a latent cursor-click no-op.

## Interaction — keyboard + mouse

Both halves of tree navigation are recognized **and** resolved in
`SyntaxNodeToText`'s reader against the live tree — **no courier operation**
(`TreeNavigateOperation` was removed in commit `f74e1a0`):

- **Keyboard (`f74e1a0`):** the `KeyDown` reader resolves the Alt chords via
  `_tree_navigate`; `TextToGraphics` declines the Alt navigation keys so the raw
  event falls through. Bindings: `Alt+↑/↓/←/→` → parent / first child / previous /
  next sibling; `Ctrl+Alt+Home` → root. At boundaries the selection stays put.
- **Mouse (`027628c`):** the gesture-aware `Change` reader promotes a mapped
  Alt+click to a whole-element selection via `_pos_to_tree_selection`. With the
  originating gesture threaded through the reader chain (see
  [`reader-gesture-context.md`](reader-gesture-context.md)), the text/graphics
  layers stay dumb (plain character cursor) and the Alt modifier reaches the syntax
  reader through `change.gesture`. `_build_tree_selection_path` is gone.

Any non-Alt keystroke / click drops back to a normal cursor at the appropriate
position. The realized bindings (Alt+click / Alt+arrows) differ from the
Ctrl+Shift / double-/triple-click scheme originally sketched. Tests:
`SyntaxTreeNavigationTest.jl` (`test_tree_navigation[s]`, `explore_tree_selections`);
`SyntaxTreeSelectionTest.jl` for the region box.
