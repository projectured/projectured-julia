# Finish syntax tree navigation

**Status: done.** Tree-selection navigation now lives entirely in `SyntaxToText`,
where the tree and selection are in hand — no courier operation, no tree intent
encoded in the text/graphics path. This was the "Interaction" slice of the
whole-element selection feature ([`syntax-tree-selection.md`](syntax-tree-selection.md)).

## What shipped

### Keyboard half — commit `f74e1a0` (pre-existing)

- `TreeNavigateOperation` deleted (struct, `evaluate_operation`, exports).
- Keyboard tree navigation recognized **and** resolved in `SyntaxNodeToText`'s
  `KeyDown` reader via `_tree_navigate`: `Ctrl+Alt+Home` → root; `Alt+↑/↓/←/→` →
  parent / first child / previous / next sibling. `TextToGraphics` declines the
  alt-modified navigation keys so the raw event falls through the chain.

### Gesture mechanism — see [`reader-gesture-context.md`](reader-gesture-context.md)

The mouse half depended on the originating gesture being reachable in the syntax
reader. That shipped as the four-commit `Change` refactor (the reader now threads
a `Change{gesture, operation}`), which also removed the `from_click::Bool` flag
(item 2 of the original plan — done there, not here).

### Mouse half — commit `027628c`

All pointer-driven tree behaviour moved into `SyntaxToText`:

- **`SyntaxNodeToText`** — the gesture-aware `Change` reader promotes a mapped
  click to a whole-element (tree) selection when
  `change.gesture isa MousePress && gesture.modifiers.alt`, reusing the existing
  `_pos_to_tree_selection` (the same helper the keyboard half and whole-element
  rendering already use). Marker-click fold detection runs first, so a click on a
  collapse glyph still folds.
- **`GraphicsCaching`** — dropped its alt special-case; a hit-test always emits
  `ElementReference(i) → PointReference(x,y)` (a plain click).
- **`TextToGraphics`** — deleted `_build_tree_selection_path` and both call sites
  (the raw `MousePress` reader and `_translate_click`); a click is always a plain
  character cursor.

The alt modifier reaches `SyntaxToText` through `change.gesture` regardless of
whether the click went via `GraphicsCaching` or the direct `MousePress` reader,
so the lower layers no longer encode tree intent in the path.

## Decisions resolved

- **Whole-element trigger (was open):** kept **Alt+click** (zero behaviour change
  for users). Lisp-style re-click / selection modes (the original item 5) remain a
  separate, larger future effort — out of scope here.
- **`from_click` removal:** done as the payoff of
  [`reader-gesture-context.md`](reader-gesture-context.md).

## Validation

- Manual: on the `json` example, Alt+click selects the precise enclosing element
  at every depth (`.entries[7].value.entries[1].value`,
  `.entries[6].value.elements[1]`, …); a plain click is a character cursor.
- Suites green: `TreeNavigation` 16/16, `SyntaxTreeSelection` 29/29,
  `ClickRoundtrips` 10/10, `MouseClicks` 10/10, the `SyntaxToText`
  collapse/marker/flat-position suites, and `TextToGraphics`.

## Follow-ups

- **Master plan split:** the built whole-element feature — including this
  gesture-in-reader interaction — is recorded in
  [`syntax-tree-selection.md`](syntax-tree-selection.md); the deferred
  range/multi-element and `ListNode`-highlight slices stay in
  [`../pending/syntax-tree-selection.md`](../pending/syntax-tree-selection.md).
- **Unblocks** Phase 3 of [`event-case-migration.md`](../pending/event-case-migration.md):
  the now-stable `TextToGraphics` / `SyntaxToText` readers can migrate to
  `@event_case`.
- **(Future)** Lisp-style selection modes (text vs syntax, `Ctrl+Space`; plain
  arrows navigate the tree in syntax mode) — a larger separate effort, noted in the
  master plan, deliberately not scoped here.
