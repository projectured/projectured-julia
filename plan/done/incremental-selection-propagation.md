# Incremental selection propagation

## Why

With partial (dirty-rectangle) rendering, a caret move should repaint only the
caret. After decoupling the caret from the text spans in `TextToGraphics` and
`SyntaxToText`, this holds for **standalone** json/syntax/text pipelines (the
caret move repaints only the old∪new caret slivers).

It does **not** hold for a document nested in widgets — e.g. the json editor
inside `workbench_example`. There a caret move repaints a large region: the
tabbed pane's tab strip `(302,5,1041,40)` and the active-tab content wrapper
`(307,45,773,423)`.

### Root cause

Selection is a single path on the root document, written top-to-bottom on every
change:

```julia
# program/src/common/Operation.jl
function evaluate_operation(editor, op::ReplaceSelectionOperation)
    clear_selection!(editor.document)        # writes `nothing` to every node's selection cell along the OLD path
    set_selection!(editor.document, op.path) # writes the remaining suffix to every node's selection cell along the NEW path
end
```

`set_selection!(document, path)` stores, at each node, the **full remaining
suffix** of the path (`node.selection = suffix-from-here-down`). So when the
caret moves one character, the deep `RangeReference` changes, and therefore the
suffix stored at **every** ancestor node changes too (each suffix contains the
deep caret). Every selection cell on the path is invalidated (twice: cleared,
then set).

The reactive engine uses **eager invalidation with no value-equality
short-circuit**, so every cell that reads one of these selections recomputes —
even when the part it cares about is unchanged. Concretely, the tabbed pane
([WidgetToGraphics.jl] `WidgetTabbedPaneToGraphicsCanvas`) does
`active = _tab_index_from_selection(sel_cell[])` to highlight the active tab and
to pick the active content; `_active_idx` reads only the **head** of the
selection (which tab), but the read makes `selector_cv` and `content_cv` depend
on the whole selection cell, so a deep caret move regenerates both `CellVector`s
(and the dirty walk then correctly repaints their whole bounds).

This is not a dirty-walk problem — the walk faithfully reports the regenerated
canvases. (A leaf-level retained-diff in the dirty walk was considered and
**rejected**: it would descend through regenerating wrappers, but the proper fix
is to stop the spurious invalidation at the source.)

## The fix

Make selection propagation **incremental**:

1. **Do not `clear_selection!` on every change.** The leftover stale selection
   in off-path branches does not matter: each split/dispatch point
   (`_tab_index_from_selection`, `TypeDispatchingProjection`, composite/ split
   routers, …) takes precedence based on the **actual remaining selection path**,
   so a stale selection in a branch that is no longer on the active path is never
   consulted.

2. **Only write a node's selection where its local step actually changes.** A
   node should depend only on the part of the selection relevant to it (its local
   step — which child / which field), not on the full deep suffix. A caret move
   deep in the tree should write only the cells from the divergence point down,
   leaving the unchanged ancestors' selection cells untouched — so cells like the
   tabbed pane's `_active_idx` (which key off an unchanged local step) are not
   invalidated and the widget chrome does not regenerate.

Likely shape of the change (to be designed):

- Store/propagate selection so each node holds its **local step** (plus a link to
  the child's selection), rather than the full suffix; or
- Keep the full-suffix representation but make `set_selection!` a **diff**: walk
  the new path against the currently-stored selection and write a node's cell
  only when its stored value differs, descending no further once the suffixes
  match. Drop the separate `clear_selection!` pass entirely (let the new write
  overwrite the changed nodes; off-path leftovers are harmless per (1)).

## Acceptance

- In `workbench_example`, moving the caret inside the embedded json repaints only
  the old∪new caret slivers (measure via the same harness used during the
  TextToGraphics/SyntaxToText work: print, render once to validate cells, drive a
  click + arrow through the projection, `SdlBackendModule._compute_dirty_rect`).
- No regression in selection/click/navigation suites (`test_readers`,
  `test_text_navigations`, `test_click_roundtrips`, `test_tree_navigations`,
  `test_repls`).

## Context / related

- Done already (prerequisites): caret decoupled from spans in `TextToGraphics`
  and `SyntaxToText`; dirty-rectangle partial rendering in the SDL backend.
- Code: `evaluate_operation(::ReplaceSelectionOperation)`, `clear_selection!`,
  `set_selection!` in `program/src/common/Operation.jl`;
  `_tab_index_from_selection` / `selector_cv` / `content_cv` in
  `program/src/projection/primitive/WidgetToGraphics.jl`.
