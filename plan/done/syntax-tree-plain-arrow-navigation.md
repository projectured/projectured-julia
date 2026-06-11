# Syntax Tree — plain-arrow navigation in structural mode

**Status: implemented.** `SyntaxToText.jl` (`_is_tree_selection`,
`_promote_to_structural`, `_descend_to_text_cursor`, relaxed arrow gate +
`Ctrl+Space` branch) and `TextToGraphics.jl` (`_is_structural_selection`
decline). Covered by the "SyntaxToText plain-arrow navigation & Ctrl+Space
toggle" testset. One deviation from the draft below: the structural decline in
`TextToGraphics` covers only the four arrow keys, **not** `:home` — `Ctrl+Home`
keeps its "jump to text start" meaning even while a whole element is selected.

Once a whole element (a leaf or an internal node) is **already selected**,
unmodified arrow keys drive tree navigation — no `Alt` needed. `Alt` stays
required only to *enter* structural mode from a character cursor. `Ctrl+Space`
toggles between structural mode and text (character-cursor) mode in both
directions.

This brings the syntax tree in line with the table navigation shipped in
443ebc5, whose grid arrows already gate on `evt.modifiers.alt || shape !== nothing`
([`TableToGraphics.jl:566`](../../program/src/projection/primitive/TableToGraphics.jl#L566)):
*Alt only to enter; once a whole cell/row/column is selected, plain arrows
continue.*

## Background — how tree nav is wired today

Tree-navigation keys are recognised in **two** layers, both gated purely on
`Alt`:

1. **`TextToGraphics`** declines `Alt + (arrows|home)` so the raw event falls
   through to the syntax layer
   ([`TextToGraphics.jl:213`](../../program/src/projection/primitive/TextToGraphics.jl#L213)).
   It owns only flat character/line cursor motion.
2. **`SyntaxNodeToText`** resolves `Alt + arrows` against the live tree via
   `_tree_navigate`, and `Ctrl+Alt+Home` → root
   ([`SyntaxToText.jl:269`](../../program/src/projection/primitive/SyntaxToText.jl#L269)).

A whole-element selection is a syntax-domain path ending in `∅`
(`EmptyReferencePath`), e.g. `.children[i].children[j]…∅`. On the **text** side
the printer projects it to a `TextRectangularReference` carrying the element's
flat range
([`SyntaxToText.jl:196-208`](../../program/src/projection/primitive/SyntaxToText.jl#L196-L208)) —
this is the text-layer signal that the selection is structural, the analogue of
the table's `shape`.

## Decisions (resolved)

- **Plain `down` on a leaf** behaves exactly like the current `Alt+down`:
  descend in the structure (to `.children[1]`); on a leaf with no children it
  is a no-op. There is **no** "descend into text" on a plain arrow — that is what
  `Ctrl+Space` is for.
- **`Ctrl+Space`** toggles structural ⇄ text in both directions.
- **Edges no-op.** `up` at the root, and `left`/`right` with no sibling, do
  nothing (matching the table, which returns `nothing` at edges —
  [`TableToGraphics.jl:576,587`](../../program/src/projection/primitive/TableToGraphics.jl#L576)).
  The plain arrow was already declined by `TextToGraphics`, so an unresolved
  arrow simply stops; it must **not** fall back to character motion.

## Phase 1 — plain arrows continue structural navigation

### `SyntaxToText.jl` — drop the `Alt` requirement when already structural

In `projection_read(p::SyntaxNodeToText, iomap, evt::KeyDown)`
([`SyntaxToText.jl:269-278`](../../program/src/projection/primitive/SyntaxToText.jl#L269)),
the current gate is:

```julia
evt.modifiers.alt && evt.key in (:up, :down, :left, :right) || return nothing
```

Change so a plain arrow is also accepted **when the current selection is a tree
selection**. `_tree_navigate` already returns `nothing` for any non-tree
selection, so the cleanest form is to attempt navigation and consume only on a
hit:

```julia
evt.key in (:up, :down, :left, :right) || return nothing
sel = iomap.input.selection
# Plain arrows drive the tree only when already in structural mode; Alt enters
# from a character cursor. _is_tree_selection ≡ sel is ∅ or ends in ∅.
(evt.modifiers.alt || _is_tree_selection(sel)) || return nothing
new_path = _tree_navigate(iomap.input, sel, evt.key)
new_path === nothing && return nothing
ReplaceSelectionOperation(new_path)
```

`_is_tree_selection(sel)` = `sel isa EmptyReferencePath`, or a
`ConcreteReferencePath` whose final tail is `EmptyReferencePath` (walk to the
end). Keep `_tree_navigate` unchanged — the edge cases (`up` at root, `left`/
`right` clamping, `down` on a leaf staying) already match the decisions above.

### `TextToGraphics.jl` — decline plain arrows when the selection is structural

The arrows must reach the syntax layer. Today only `Alt + arrows` is declined
([`TextToGraphics.jl:213`](../../program/src/projection/primitive/TextToGraphics.jl#L213)).
Extend the decline to also cover plain arrows when the selection is a
**whole-element (rectangular) reference** — the text-layer mirror of "structural
mode", exactly analogous to the table's `shape !== nothing`:

```julia
is_structural = _is_rectangular_selection(iomap.input.selection)
if (evt.modifiers.alt || is_structural) && evt.key in (:up, :down, :left, :right, :home)
    return nothing
end
```

`_is_rectangular_selection` tests for a `TextRectangularReference` terminal in
the text-domain selection (the shape the printer emits at
[`SyntaxToText.jl:196-208`](../../program/src/projection/primitive/SyntaxToText.jl#L196-L208)).
With no structural selection present, plain arrows keep doing character/line
motion unchanged.

## Phase 2 — `Ctrl+Space` toggles structural ⇄ text

Recognised in **`SyntaxNodeToText`**, where the tree and both selection shapes
are in hand. This is pure syntax-domain path surgery — no flat-text math, no
courier op — and stays School-A (operate on the selection path, don't re-walk
document types):

- **Text → structural.** Selection is a character cursor inside a leaf, i.e. a
  path like `.children[i].value@pos` (a `PositionReference`/value tail). Drop the
  value/position tail to the enclosing element → `.children[i]…∅`. Reuse the
  promotion target logic already used by `Alt+click`/`_resolve_collapsible`
  ([`SyntaxToText.jl:230-232`](../../program/src/projection/primitive/SyntaxToText.jl#L230),
  [`:255`](../../program/src/projection/primitive/SyntaxToText.jl#L255)): promote
  to the **innermost enclosing node** of the cursor.
- **Structural → text.** Selection is `.children[i]…∅`. Descend to the **first
  leaf** under the selected node and place a character cursor at its value start
  → `…value@0`. (Stateless: round-tripping returns to the node's start, not the
  exact prior character. Acceptable; matches the selection-driven, stateless
  architecture.)

Add a `KeyDown` branch in
`projection_read(p::SyntaxNodeToText, iomap, evt::KeyDown)`:

```julia
if evt.key === :space && evt.modifiers.ctrl
    sel = iomap.input.selection
    new = _is_tree_selection(sel) ? _descend_to_text_cursor(iomap.input, sel) :
                                    _promote_to_structural(iomap.input, sel)
    new === nothing && return nothing
    return ReplaceSelectionOperation(new)
end
```

### Routing check for `Ctrl+Space`

The event must reach `SyntaxNodeToText`. Confirm the lower layers do **not**
consume `Ctrl+Space`:

- `TextToGraphics` `KeyDown` reader — ensure it declines (`return nothing`) for
  `:space` with `ctrl`, so it falls through (it already special-cases other
  chords like `Ctrl+.` at
  [`TextToGraphics.jl:206`](../../program/src/projection/primitive/TextToGraphics.jl#L206)).
- Any type-in / character-insert path must not swallow `Ctrl+Space` as a space
  character. Verify in `TextToGraphics`/`TextToString` and add a guard if needed.

The table reuses `Shift/Ctrl+Space` for *widen-to-row/column*
([`TableToGraphics.jl:548`](../../program/src/projection/primitive/TableToGraphics.jl#L548)).
The tree's `Ctrl+Space` = mode toggle is a deliberately different (domain-local)
meaning; note the divergence so the two aren't later "unified" by mistake.

## Edge / interaction notes

- `Alt+arrows` keeps working in both modes (table parity: enter-and-move from a
  text cursor; continue in structural mode).
- `Ctrl+Alt+Home` → root is unchanged.
- An unresolved plain arrow in structural mode (edge) must dead-end, not revert
  to character motion — guaranteed because `TextToGraphics` already declined it
  and `SyntaxNodeToText` returns `nothing`.
- `down` into a **collapsed** node: keep current behaviour (the collapsed-node
  layout already governs descent); no new rule here.

## Testing

- `test_selection(<a syntax/json/xml example>)` and `test_repl(<…>)` — the
  selection-walk and REPL-loop layers exercise keyboard navigation.
- Targeted: `test_syntax_to_text()` for the routing + `_tree_navigate`/toggle
  paths; `test_json_to_syntax()` if a JSON example is used end-to-end.
- New cases to assert:
  1. From a whole-leaf selection, plain `up`/`down`/`left`/`right` move exactly
     like the `Alt` versions.
  2. Plain arrows at edges no-op (root `up`; first/last sibling `left`/`right`).
  3. Plain arrows with a **character cursor** still do character motion
     (unchanged).
  4. `Ctrl+Space` text→structural selects the innermost enclosing node;
     `Ctrl+Space` structural→text drops a cursor at the first leaf's value start;
     the two round-trip.

## Related

- Table analogue (already implements the "plain arrows once structural" rule):
  [`TableToGraphics.jl:559-606`](../../program/src/projection/primitive/TableToGraphics.jl#L559).
- Foundation & prior nav work:
  [`../done/syntax-tree-selection.md`](../done/syntax-tree-selection.md),
  [`../done/finish-syntax-tree-navigation.md`](../done/finish-syntax-tree-navigation.md).
- Remaining selection slices: [`syntax-tree-selection.md`](syntax-tree-selection.md).
