# Syntax Tree Selection

Preliminary plan for selecting a *whole* syntax element — a full `SyntaxNode`, `SyntaxLeaf`, or wrapper (`SyntaxDelimitation`, `SyntaxIndentation`, …) — as a single unit, in addition to the character-level cursor selections that already exist (`.open{k}`, `.value{k}`, `.close{k}`, `.children[i]…`).

## Motivation

Today a selection inside the syntax domain always lands *inside* a leaf or node (a character cursor in a delimiter/value, or a child index). There is no way to say "the entire `[1, 2, 3]` array node is selected" or "this whole identifier leaf is selected" as one atom. Whole-element selection is needed for:

- range edits (cut/copy/paste a subtree, drag-and-drop a node)
- structural navigation (expand selection to enclosing node, shrink to first child)
- visual highlighting of the active subtree
- mapping selections cleanly **backward** from text/cursor positions to the enclosing syntax element, and **forward** from a domain-level element (a `JsonArray`, an `XmlElement`) into the syntax tree and onward to text.

## Design Sketch

### 1. A "whole element" reference

Introduce a marker reference step that addresses *the element itself* rather than a position inside it. Two options to evaluate:

- **(a) `SelfReference`** — a new `ReferenceStep` meaning "this node, as a whole". A selection path that ends in `SelfReference` denotes whole-element selection. Cheap and explicit.
- **(b) Empty-path convention** — interpret a `ReferencePath` that terminates at a `SyntaxNode`/`SyntaxLeaf` (no further `.value` / `.children` step) as whole-element selection. No new type, but ambiguous against "no cursor placed yet".

Lean toward (a); revisit during implementation.

### 2. Selection storage

Same recursive `selection::Reference` cells already in place — only the *terminal* step changes. A node selected as a whole stores `SelfReference` (or the agreed marker) in its `selection` cell; ancestors store the path to it as today.

### 3. Range / multi-element selection (stretch)

A second pass can add a *range* selection over sibling children: e.g. `.children[2..4]` selects three adjacent subtrees. Out of scope for the preliminary plan but the marker design should not preclude it — keep the reference step extensible.

### 4. Backward mapping (text → syntax element)

Reader side of `SyntaxToText` and the various `*ToSyntax` projections must translate:

- a character-cursor selection in text → the **enclosing** syntax element when the user issues a "select enclosing" gesture
- a click that lands on a delimiter or whitespace boundary → the node whose delimiter it is

Each projection's `iomap` already round-trips positions; extend it so that a `SelfReference` on the *output* side resolves to `SelfReference` on the corresponding *input* node.

### 5. Forward mapping (domain element → syntax → text)

When upstream code sets the selection to "this `JsonArray`" (whole element), the printers must:

- propagate `SelfReference` through the printer chain (`JsonToSyntax` → `SyntaxToText`)
- in text, render as a *range highlight* spanning open-delimiter start to close-delimiter end of the syntax node it printed

This is symmetric to (4): the iomap must carry `SelfReference` in both directions.

### 6. Editor surface (later)

- Keyboard: `Ctrl+Shift+Up` expand selection to enclosing element; `Ctrl+Shift+Down` shrink.
- Mouse: double-click on a leaf selects the whole leaf; triple-click selects the enclosing node.

Not part of the first slice — the first slice is the data model and iomap plumbing.

> **Built (with different bindings).** The realized editor surface uses **Alt+click**
> to select the innermost node and **Alt+arrows** / **Ctrl+Alt+Home** to navigate,
> rather than the Ctrl+Shift / double-/triple-click scheme sketched here. See the
> "Interaction" section below for the implemented bindings.

## First Slice (what to actually build first)

**Status: done.** Chose option (b) — the empty-path convention — over option (a)
(`SelfReference`). A whole-element selection is **not a distinct reference step**;
it is just a path that terminates *at* the element, i.e. an `EmptyReferencePath`
(`∅`). Each node stores only its remaining path, so the one node whose `selection`
cell holds `∅` is the wholly-selected one; ancestors hold a non-empty path routing
down to it, and descendants hold `nothing`. A `SelfReference` marker was built
first and then removed: it was an unnecessary extra degree of freedom, since tree
position already disambiguates and `evaluate_reference(doc, ∅)` already returns the
element. Tests: `test/src/projection/SyntaxTreeSelectionTest.jl`
(`test_syntax_tree_selection`).

1. ✅ No new reference type. `evaluate_reference(document, EmptyReferencePath())`
   already returns the element itself — that *is* the whole-element semantics.
2. ✅ `set_selection!` / `replace_selection!` / `clear_selection!` accept
   `∅`-terminated paths with no change: the `∅` terminal falls through their
   `path isa ConcreteReferencePath || return` guard (no child to recurse into).
3. ✅ `@reference_case` gained a writable **empty-path pattern** `∅` (the macro
   already matched zero-step patterns internally; there was just no surface
   syntax). `∅ => @reference()` maps a whole-element selection through as
   identity. The macro's no-match fallthrough is unchanged (`nothing`).
4. ✅ Selection mappers carry `∅` both ways. `@reference_case`-based mappers use
   the `∅ => @reference()` branch (default fwd, JSON leaf/array/object fwd+bwd,
   `SyntaxLeafToText` fwd); the flat-offset mappers and printer cells keep a small
   `x isa EmptyReferencePath && return @reference()` guard. A whole `JsonArray`/
   `JsonObject`/`SyntaxLeaf` round-trips `∅`; a *nested* whole-child survives the
   syntax level as `.children[i]` (terminating `∅`) and back to `.elements[i]`.
5. ✅ Tests added (forward/backward for array, object, leaf; the empty-path
   predicate; `set_selection!`/`clear_selection!` placing `∅` at the target node;
   nested whole-child round-trip).

### Later slices — status

- ✅ **Text-range highlight for a nested child** — built. `_syntax_to_flat` now
  returns a wholly-selected descendant's flat range, and `SyntaxNodeToText`'s
  selection cell emits `ConcreteReferencePath(TextRectangularReference(start,
  stop), ∅)` for a nested `.children[i]` selection (SyntaxToText.jl). See
  "Visualization — Region box" below.
- ✅ **Visual highlighting in `TextToGraphics`** — built. The region box is drawn
  in its own highlight layer; `_selection_range` normalizes `∅` ⇒ `(0, N)` and
  `TextRectangularReference(s, e)` ⇒ `(s, e)`, then paints a translucent
  `GraphicsRect` over the covered segments' bounding box.
- ✅ **Editor surface (navigation flavour)** — built. Alt+click selects the
  innermost node; Alt+↑/↓/←/→ move to parent / first child / previous / next
  sibling; Ctrl+Alt+Home selects the root. Any non-Alt keystroke/click drops
  back to a normal cursor. Tests: `SyntaxTreeNavigationTest.jl`
  (`test_tree_navigation[s]`, `explore_tree_selections`);
  `SyntaxTreeSelectionTest.jl` updated for the box.
  - **Keyboard mechanism (updated, commit `f74e1a0`):** the `TreeNavigateOperation`
    courier was **removed**. The raw key event is recognized *and* resolved in
    one place — `SyntaxToText`'s `KeyDown` reader, where the tree and selection
    are in hand (`_tree_navigate`). `TextToGraphics` declines alt-modified
    navigation keys so the event falls through the chain. This fixed navigation
    in pipelines with intermediate projections (e.g. `julia`, which has
    `LineNumbering` between the layers).
  - **Mouse (pending move):** Alt+click still builds a text whole-element path
    (`_build_tree_selection_path` in TextToGraphics) that `SyntaxToText` inverts.
    Moving this promotion into the syntax reader is tracked in
    [finish-syntax-tree-navigation.md](finish-syntax-tree-navigation.md), which
    depends on [reader-gesture-context.md](reader-gesture-context.md).
- ⏳ **Range / multi-element selection (plan §3)** — still deferred.
  `TextRangeReference` (the ragged cross-span char-range sibling of
  `TextRectangularReference`) is named in the design but not built.
- ⏳ **Wrapped/paragraph text (`ListNode` / `_print_listnode`)** — still draws no
  selection chrome and uses an empty coord map; needs the same highlight-layer
  treatment later.

## Visualization — Region box (✅ built)

How a whole-element selection is *drawn*, and where in the pipeline the highlight
is introduced. **Status: implemented** as described below — `TextRectangularReference`
exists (Reference.jl), `SyntaxNodeToText` emits it for nested children,
`TextToGraphics` renders the translucent `GraphicsRect` in a dedicated highlight
layer, and the Z-ordered hit test landed alongside it. The design notes are kept
for rationale.

### Rendering style: Region box
One translucent, rounded `GraphicsRect` over the **bounding box** of the selected
element's text. A single-line leaf gets a tight, exact box; a multi-line node gets
a bounding box that hugs the indented `SyntaxIndentation` block (it over-covers
interior trailing whitespace — accepted, reads as "the whole block"). Alternatives
weighed and rejected: *text polygon* (per-line ragged tint — looks like a character
drag-selection, not a structural pick); *gutter bar* (less precise about extent);
*stroked outline* (needs a stroke primitive — `GraphicsRect` is fill-only). A
structural selection should also read distinct from a future text-range selection
(different colour).

### Text-domain representation: two new flat-index steps
**A `RangeReference` must NOT be reused** for these — that single-axis form is for a
character range *within one span* (`elements[i].content[s:e]`). The multi-span Text
forms get their own vocabulary. Two new `ReferenceStep`s, both carrying **two flat
char indices** — offsets measured from the start of the `TextText`, counting straight
through every span (0-based, half-open `[start, end)`, the same flat model
`_syntax_to_flat` / `child_char_ranges` already use):

```
TextRectangularReference(start, end)   # → axis-aligned bounding box  (structural box)
TextRangeReference(start, end)         # → ragged text-flow polygon   (char range; planned sibling)
```

Identical payload; the **type selects the geometry** at render time. `TextRangeReference`
is the unrelated cross-span character-selection feature; we add it here only so the
pair is coherent — this slice builds `TextRectangularReference`.

Path shape: a single top-level step on the `TextText`, e.g.
`ConcreteReferencePath(TextRectangularReference(start, end), ∅)` — *not* under
`elements[i]`, since the offsets are flat across all spans, not into one element.

Cases:

- **Whole element at the top of what a projection prints** → already arrives as `∅`
  on the whole `TextText`. `SyntaxLeafToText` (3 spans `[open, value, close]`) and
  `SyntaxNodeToText` (flattened subtree) both already map a `∅` input selection
  forward to `∅` output (SyntaxToText.jl:69, :185). So a single leaf or a top-of-subtree
  node needs **no new step** — TextToGraphics normalizes `∅` to the full range `(0, N)`.

- **A wholly-selected *nested* child** → what `∅` cannot express (it means the *whole*
  TextText). The parent flattens its whole subtree into one `TextText`, so child *i*
  occupies a flat char sub-range `[start, end)`. Emit
  `TextRectangularReference(start, end)`. A distinct *type*, so it never collides with
  `RangeReference`. This is the gap behind today's degrade where `map_reference_forward`
  / `_syntax_to_flat` return `-1` for a `∅` terminal (SyntaxToText.jl:148-153).

**Why this is not the deleted `SelfReference` marker.** `SelfReference` was redundant
because the document tree still held the node to disambiguate. Here, flattening into
one `TextText` *destroys* the per-child grouping, so `TextRectangularReference`
re-supplies information that is otherwise absent in the flat domain — it carries data
(the flat extent), not redundancy, and lives only at the Text layer. (The alternative
that would let `∅` work everywhere is to stop flattening — emit a nested `TextText`
per syntactic child so `∅` on a sub-`TextText` means "box" — but that is a large
restructure of `_collect_spans` + TextToGraphics layout; rejected unless we want it.)

**Producing it.** No new bookkeeping: `child_char_ranges` (SyntaxToText.jl:141, :190)
*already* holds each child's flat char range, and `_syntax_to_flat` already walks the
path to a descendant. When the addressed descendant's selection terminates in `∅`,
extend `_syntax_to_flat` to return that descendant's flat range `[start, end)` (today
it returns a single cursor offset, `-1` for `∅`) and have the `selection` cell emit
`TextRectangularReference(start, end)`. Because it tracks the child's exact flat
extent, the box hugs the child and excludes the parent's separators/indent.

**Plumbing.** `set_selection!` must treat `TextRectangularReference` /
`TextRangeReference` as terminal ("don't navigate into a child", like
`PositionReference` / `ProjectionReference`); the `@reference` builder and
`@reference_case` need surface syntax for them if mappers are to construct/match them.

### Where the rectangle is introduced
`TextToGraphics.projection_print`, inside the `both` cell — the *same* site and
reason as the cursor rect. It is the only layer with pixels: each `SegCoord`
carries measured `x/y/width/height`; nothing upstream (JSON, Syntax) knows pixels,
they carry only the selection *path*. Mechanics: `_selection_range(styled.selection)`
normalizes both box forms to a flat char range — `∅` ⇒ whole text `(0, N)`;
`TextRectangularReference(start, end)` ⇒ `(start, end)` — converts the two flat
offsets to pixel positions with the existing per-segment measurement, gathers the
covered `SegCoord`s, and computes the bounding box `x0=min(x), y0=min(y), x1=max(x+w),
y1=max(y+h)`; emit `GraphicsRect(x0, y0, x1-x0, y1-y0, accent, alpha≈50, radius≈4)`.
Branch at the draw site: a box selection (`∅` / `TextRectangularReference`) ⇒ box and
no cursor; a point (`content{k}`) ⇒ cursor exactly as today (they are mutually
exclusive). A future `TextRangeReference(start, end)` reuses the same flat→pixel
conversion but paints the ragged per-line polygon instead of the bounding box.

### Layering: a separate canvas so the text elements aren't disturbed
The highlight goes in its **own `GraphicsCanvas` layer**, *not* interleaved into the
text segment list. `TextToGraphics` emits a parent canvas =
`[highlight_layer (behind), text_layer (front)]`; the text layer is byte-for-byte
today's canvas, so `char_to_coord` ↔ element-index alignment stays pristine and
keyboard nav / `_text_selection_range` / `_hit_segment` are untouched.

Precedent: `GraphicsCanvasToGraphicsImage.projection_print` already prepends a
checker-board background to its *output* (`vcat(bg_rects, orig_cells)`) while its
reader hit-tests the *input* canvas — so output-side decoration provably never
disturbs text indexing. The highlight follows the same layers pattern, but is
produced by `TextToGraphics` because only it can turn the selection range into
pixels.

### Hit testing: respect Z order
The backend paints `for elem in elements` in list order (`Sdl.jl`), so Z = list
order and the last element is topmost. The highlight layer sits *behind* the text
layer, so hit-testing must be **topmost-first**: replace the type-priority scan in
`GraphicsCanvasToGraphicsImage.projection_read` (all `GraphicsRect`s, then all
`GraphicsText`s) with a single reverse scan returning the first element whose real
bounds contain the click. A click on a glyph then lands on the text painted on top
of the highlight — no swallowing, no need for a per-element "decoration" flag. This
also subsumes the original "rects first (e.g. cursor)" intent (an interactive rect
placed on top is topmost → hit first) and fixes the latent cursor-click no-op.

Open implementation details:
- With the extra parent canvas, `_translate_click` must strip one leading
  `ElementReference` (parent → text-child) before the `char_to_coord` lookup.
- Confirm how the recursive canvas read (`CopyingProjection`) dispatches a
  `MousePress` among overlapping sibling layers — it must prefer the front (text)
  layer (same topmost-first principle, applied one level up).

### Build slices (✅ 1 and 2 done)
1. **Single-line leaf / top-of-subtree (rides `∅`).** No new step: the forward
   mapping already emits `∅` (SyntaxToText.jl:69, :185). TextToGraphics learns
   `selection isa EmptyReferencePath` ⇒ box over all `SegCoord`s, in its own
   highlight layer, with Z-ordered hit test. Smallest end-to-end proof
   (string → leaf → text → graphics).
2. **Nested child (introduces `TextRectangularReference`).** Add the new step; extend
   `_syntax_to_flat` to return the descendant's flat range `[start, end)` so the
   `selection` cell emits `TextRectangularReference(start, end)` (no new bookkeeping —
   `child_char_ranges` already holds the flat extent). TextToGraphics gains the
   `TextRectangularReference` branch (`∅` and `TextRectangularReference` share the
   same box renderer). Same graphics, no new layout.
- The `ListNode` path (`_print_listnode`) draws no selection chrome today and uses
  an empty coord map — wrapped/paragraph text needs the same layer treatment later.

## Interaction: Creating & Navigating Tree Selections (✅ built)

Keyboard navigation is recognized **and** resolved in `SyntaxNodeToText`'s
`KeyDown` reader against the live tree (`_tree_navigate`); `TextToGraphics`
declines the Alt chords so the raw event falls through. There is **no courier
operation** — `TreeNavigateOperation` was removed in commit `f74e1a0`. Alt+click
is still recognized in `TextToGraphics`'s click reader
(`_build_tree_selection_path`), pending the move into the syntax reader tracked
in [finish-syntax-tree-navigation.md](finish-syntax-tree-navigation.md). Tests in
`SyntaxTreeNavigationTest.jl`.

### Entering tree selection mode

- **Alt + mouse click** → select the innermost syntax tree node at the click
  position. The click's pixel coordinates are resolved to a character position
  (existing `_translate_click` / `_hit_segment` path), then walked upward
  through the syntax tree to find the tightest enclosing `SyntaxLeaf` or
  `SyntaxNode`. That node receives `∅` as its selection, producing a
  whole-element highlight.

### Navigating within tree selection mode (Alt + cursor keys)

Once a node is selected (its `selection` is `∅`):

- **Alt + ↑** — move selection one level up to the parent node.
- **Alt + ↓** — move selection one level down to the first child.
- **Alt + ←** — move selection to the previous sibling (same parent, index − 1).
- **Alt + →** — move selection to the next sibling (same parent, index + 1).
- **Ctrl + Alt + Home** — select the root node (`Ctrl+Alt+Home` in the
  `SyntaxNodeToText` `KeyDown` reader → `ReplaceSelectionOperation(∅)`).

At boundaries (no parent / no child / first or last sibling) the selection
stays unchanged (no wrap-around).

### Leaving tree selection mode

Any regular keystroke, mouse click (without Alt), or cursor movement
(without Alt) exits tree selection mode and places a normal cursor at the
appropriate position within the formerly-selected node.

## Open Questions

- ~~Does whole-element selection need a dedicated reference step?~~ **Resolved at the document/syntax level: no** — it is the empty path (`∅`); the default `map_reference_forward`/`backward` and the `@reference_case` `∅` pattern pass it through, so any domain (XML, filesystem, …) inherits whole-element selection for free. **But the Text layer is the exception:** because `SyntaxNodeToText` flattens a subtree into one flat `TextText`, a wholly-selected *nested child* is a contiguous span sub-range that `∅` cannot name, so it does need the dedicated `TextRectangularReference(start, end)` step (flat char offsets across all spans; see the Visualization section). `∅` still covers the whole-`TextText` case.
- How should whole-element selection compose with `ProjectionReference` (projection-introduced delimiters)? Probably: an `∅` selection on a projection-introduced node is allowed and renders as that delimiter's range.
- Interaction with `ContentIoMap` wrappers (`Dragging`, navigation overlays) — confirm they pass an `∅` selection through unchanged.
