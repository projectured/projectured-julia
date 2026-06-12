# Collapsing / expanding syntax nodes — foundation (Syntax layer)

The Syntax-layer collapse/expand foundation **shipped**. The remaining
domain hookups and follow-ups are tracked in
[`../pending/collapse-expand-syntax-nodes.md`](../pending/collapse-expand-syntax-nodes.md).

What landed (verified in the code, not by running):

## Operation + resolution

- `ToggleCollapseOperation([target])` in
  [`program/src/common/Operation.jl`](../../program/src/common/Operation.jl) —
  flips the `collapsed` cell of a single collapsible node. A `nothing` target is
  resolved to the **innermost** collapsible node by the projection layer that
  owns the collapse state (`SyntaxNodeToText`); a concrete target is carried by
  click gestures. `evaluate_operation(editor, ::ToggleCollapseOperation)` is
  implemented. Exported from `Projectured.jl`.

## Syntax → Text printer

- `SyntaxNodeToText` honours `node.collapsed`: collapsed nodes render as
  `<marker?><open><ellipsis><close>` with **no** child layout; expanded nodes
  render the children as before.
- Configurable projection fields: `expanded_marker`, `collapsed_marker`
  (both default empty = off), `marker_eligible`, and `ellipsis_text`
  (default `"…"`, muted). `_active_marker` decides which glyph to emit and
  suppresses the marker for empty nodes.
- IoMap carries a `marker_index` cell so the reader can recognise marker /
  ellipsis hits; the flat/offset helpers account for the marker in both states
  and the ellipsis in the collapsed state.
- Reactivity prunes the collapsed subtree (children cells aren't read while
  collapsed).

## Reader (click + keyboard)

- `SyntaxNodeToText.projection_read` translates a click on the inline marker
  (either state) or on the collapsed ellipsis into a `ToggleCollapseOperation`
  carrying the clicked node.
- `TextToGraphics.projection_read` maps the `Ctrl+.` chord to a
  `ToggleCollapseOperation()` (no target → resolved upstream).

## Selection while collapsed

- Decision **(a)** shipped: the syntax-domain selection is authoritative;
  collapsing only affects rendering. A selection pointing inside a collapsed
  subtree simply stops drawing a cursor until the node is expanded.

## Test

- [`test/src/editor/CollapseRoundtripTest.jl`](../../test/src/editor/CollapseRoundtripTest.jl)
  (`test_collapse_roundtrip`) drives the **syntax** example end-to-end through
  `make_syntax_projection_example()`.

## Decisions preserved

- `SyntaxCollapsible` stays in place (plan §9) for the future case of adding a
  fold gesture to a domain type that lacks its own `collapsed` field.
- `SyntaxLeaf.collapsed` is left unused (leaf folding deferred — see the pending
  follow-up).
