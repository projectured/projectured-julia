# Finish syntax tree navigation

Completes the migration of tree-selection navigation off the graphics layer and
into `SyntaxToText`, where the tree and selection live. The keyboard half is
**done and committed**; this plan covers the mouse half and the cleanup that
follows. It depends on
[`reader-gesture-context.md`](reader-gesture-context.md) for the mouse work.

Context: this is the "Interaction" slice of the larger
[`syntax-tree-selection.md`](syntax-tree-selection.md) plan, now being
re-grounded after `TreeNavigateOperation` was removed.

## Done (committed)

Commit `f74e1a0` — *"Remove TreeNavigateOperation; resolve tree navigation in
SyntaxToText reader"*:

- `TreeNavigateOperation` deleted (struct, `evaluate_operation`, exports).
- Keyboard tree navigation is now recognized **and** resolved in
  `SyntaxToText`'s `KeyDown` reader (`projection_read(::SyntaxNodeToText, …, ::KeyDown)`),
  using the existing `_tree_navigate`:
  - `Ctrl+Alt+Home` → root (`EmptyReferencePath`)
  - `Alt+↑/↓/←/→` → parent / first child / previous / next sibling
- `TextToGraphics` now **declines** alt-modified navigation keys so the raw
  event falls through the chain instead of emitting a courier operation.
- Net fix: tree navigation no longer breaks across intermediate projections.
  The `julia` example (which has `LineNumbering` between `SyntaxToText` and
  `TextToGraphics`) went 0 → 1 reachable tree-selection state; no example
  regressed. Verified with `test_tree_navigations()` + selection/repl sweeps.

Why it works: `Sequential`'s reader already offers the raw event to every step
last→first, and `LineNumbering`/`WordWrapping` forward raw events (they did
*not* forward the old `TreeNavigateOperation`).

## Remaining work

### 1. Move the mouse alt-click promotion into `SyntaxToText` ⛓️ (needs reader-gesture-context)

Today the "alt-click selects the whole element" path is split across three
layers:

- [`GraphicsCaching.jl:133-164`](../../program/src/projection/primitive/GraphicsCaching.jl#L133-L164)
  — pixel hit-test; **alt** is consumed here and encoded as an *element-only*
  path (`ElementReference(i)`, no `PointReference`).
- `TextToGraphics` — turns the element-only path into a text whole-element path
  `.elements[i]∅` via `_build_tree_selection_path` (two call sites: the raw
  `MousePress` reader and `_translate_click`), and tags clicks with
  `from_click=true`.
- `SyntaxToText` — `map_reference_backward` inverts `.elements[i]∅` to a whole
  syntax element via `_parse_tree_elem_path`.

The Lisp original instead keeps the text→graphics layer **dumb** (it produces
only a character-cursor selection) and **promotes to whole-element in the syntax
reader**, using the raw gesture + the backward-mapped op + the current selection
([`syntax-to-text.lisp:1236-1246`](../../../projectured-lisp/source/projection/primitive/syntax-to-text.lisp#L1236-L1246)).

Target shape (after the gesture is reachable in the syntax reader):

- **`GraphicsCaching`**: drop the alt special-case — always emit
  `ElementReference(i) → PointReference(x,y)` (a plain click).
- **`TextToGraphics`**: delete `_build_tree_selection_path` and both its call
  sites; a click always becomes a plain character cursor
  (`_build_selection_path`).
- **`SyntaxToText`**: in the `ReplaceSelectionOperation` reader, when the gesture
  is a `MousePress`, decide whether to promote the mapped selection to the
  enclosing element's `∅` (whole-element). All tree-selection logic now lives
  here.

### 2. Remove the `from_click` flag (cleanup)

Once the gesture is available in the syntax reader, `from_click::Bool` on
`ReplaceSelectionOperation` ([`Operation.jl:35-61`](../../program/src/common/Operation.jl#L35-L61))
is redundant. Its only consumer is the marker-toggle disambiguation in
`SyntaxToText`'s `ReplaceSelectionOperation` reader — replace `op.from_click`
with `gesture isa MousePress`. Then:

- drop the field and the keyword constructor in `Operation.jl`;
- drop the `from_click=true` arguments in `TextToGraphics`'s click readers.

(Keep this in sync with — or fold into — the payoff section of
[`reader-gesture-context.md`](reader-gesture-context.md).)

### 3. Decide the whole-element trigger ⚠️ open decision

With the full gesture in hand both are cheap; pick the UX:

- **Keep Alt+click** (current behaviour) — promote when
  `gesture.modifiers.alt`. Zero behaviour change for users; documented in the
  master plan and the [[whole-element-selection]] note.
- **Lisp re-click** — promote when the click maps to the *already-selected*
  position (`mapped == current selection`); repeated clicks climb the tree.
  Needs no modifier and matches the original, but changes the binding.
- **Both** — alt-click and re-click.

Recommendation: **keep Alt+click** unless we want strict Lisp parity.

### 4. Update the master plan's "Interaction" section

[`syntax-tree-selection.md`](syntax-tree-selection.md) §"Interaction"
(lines ~260-293) and the §"Later slices" entry still describe
`TreeNavigateOperation` / `_build_tree_selection_path` as the mechanism. Rewrite
to: *raw gesture handled in `SyntaxToText`'s reader; no courier operation*.

### 5. (Optional / future) Lisp-style selection modes

The Lisp version is richer than ours: a selection has a **mode** (text vs
syntax), toggled by `Ctrl+Space`. In syntax mode **plain** arrows navigate the
tree; in text mode **Alt+**arrows jump the cursor to tree-relative positions
(first char of parent/child/sibling) —
[`syntax-to-text.lisp:1051-1207`](../../../projectured-lisp/source/projection/primitive/syntax-to-text.lisp#L1051-L1207).
Our `Alt+arrow`-on-`∅` is a consistent simpler subset. Adopting the full
mode system is a separate, larger effort — note here, do not scope into this
plan.

## Suggested phasing

1. Land [`reader-gesture-context.md`](reader-gesture-context.md) (mechanism).
2. Mouse promotion in `SyntaxToText` + delete `_build_tree_selection_path` +
   `GraphicsCaching` alt special-case (item 1). One commit.
3. Remove `from_click` (item 2). One commit.
4. Doc update (item 4).
5. Unblock Phase 3 of [`event-case-migration.md`](event-case-migration.md)
   (migrate the now-stable `TextToGraphics` / `SyntaxToText` readers to
   `@event_case`).

## Testing

Narrowest first, per [`CLAUDE.md`](../../CLAUDE.md):

- Keyboard (already passing): `test_tree_navigation(json_example)`,
  `test_tree_navigations()`, `explore_tree_selections` in
  [`SyntaxTreeNavigationTest.jl`](../../test/src/editor/SyntaxTreeNavigationTest.jl).
- Mouse: [`ClickRoundtripTest.jl`](../../test/src/editor/ClickRoundtripTest.jl),
  [`MouseClickTest.jl`](../../test/src/editor/MouseClickTest.jl),
  `test_selection(json_example)`, `test_text_to_graphics()`.
- Whole-element rendering still covered by
  [`SyntaxTreeSelectionTest.jl`](../../test/src/projection/SyntaxTreeSelectionTest.jl).
- After items 1-2, re-run a full `test_tree_navigations()` + a state-count diff
  vs. the previous commit to confirm no example regressed (the technique used
  when committing the keyboard half).

## Open decisions

1. **Whole-element trigger** — Alt+click (recommended) vs re-click vs both
   (item 3).
2. **`from_click` removal** — do it here (item 2) vs in the reader plan.
3. **Selection modes** — adopt the Lisp text/syntax mode system later? (item 5,
   out of scope for now.)

## Dependencies

- **Blocked by** [`reader-gesture-context.md`](reader-gesture-context.md) for the
  mouse work (items 1-2). The keyboard half is already done and needed none of it.
- **Unblocks** Phase 3 of [`event-case-migration.md`](event-case-migration.md).
