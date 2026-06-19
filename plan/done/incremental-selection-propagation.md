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

## The fix — DONE

Two changes, both about *how a selection is written* (readers untouched — each
level still holds the **whole remaining reference**, as before).

### 1. In-place incremental write (`program/src/common/Operation.jl`)

The selection is already a **shared chain**: `set_selection!` stores
`child.selection === parent.selection.tail` (the *same* path objects), and
`ConcreteReferencePath`'s `head`/`tail` — and `RangeReference`'s `start`/`stop` —
are themselves `Cell`s. So the new `update_selection!` (used only by
`evaluate_operation(::ReplaceSelectionOperation)`) walks old-vs-new in lockstep
and mutates the chain **in place**:

- A caret move within a leaf differs only in the terminal cursor step's
  `start`/`stop` → mutate those two cells; **no `selection` cell on the path is
  rewritten**, so unchanged routing ancestors are not invalidated.
- At a structural divergence, clear just the old divergent branch and
  `set_selection!` the new suffix from the divergence point down, then fix the
  parent's `.tail` cell in place to keep the chain shared — so cells *above* the
  divergence stay untouched too.
- The separate `clear_selection!` pass is dropped for replace-selection (the
  divergence handling clears exactly the stale branch).

Measured: a caret move in the embedded json went from **28 cell writes → 2**
(just the cursor `start`/`stop`).

### 2. Tabbed-pane selection decoupling (`WorkbenchToWidget.jl`)

(1) alone did *not* shrink the repaint: the dirty walk attributes dirtiness at
canvas granularity, and the tabbed pane's `selector_cv`/`content_cv` read
`sel_cell` (the forward-projected widget selection), which `map_reference_forward`
recomputes on *every* caret move because it **walks the whole shared chain down
to the mutated cursor cells** — i.e. the output cells still depended on the end of
the chain.

Every consumer of a tabbed pane's selection (`_tab_index_from_selection`,
`_route_active_tab`) reads only the **head** (which tab); the caret inside the
active tab is carried by that tab content's *own* forward-projected selection. So
`WorkbenchPageToWidgetTabbedPane`'s `tabbed.selection` now forwards only the
**head step** (`elements[i] → selector_element_pairs[i]`). That cell then depends
only on the page-selection head (untouched by a caret move, thanks to (1)), so
the tab strip and active-content wrapper no longer regenerate.

This is the narrow, "tabbed pane only" instance of the general principle (the
plan's point 2): a routing node should depend only on its local step. Whether to
generalise the same head/tail decoupling to *all* selection forward-maps (so
every routing projection stops depending on the chain end) is left as a
follow-up.

## Acceptance — MET

- `workbench_example`, visible caret move
  `.editing_page.elements[1].content.title{3}→{4}`, 1366×768, via
  `SdlBackendModule._compute_dirty_rect`:
  - **before:** `(313, 3, 853, 465)` — the whole tab strip + content wrapper.
  - **after:** `(390, 67, 396, 95)` — a 6×28px caret sliver.
  - A deeper, *scrolled-out* caret yields `nothing` after the fix (correct,
    nothing visible to repaint) vs. the same large spurious rect before.
  - At the cell level a caret move now leaves **0** canvases/`CellVector`s stale;
    only the caret `GraphicsRect`'s `x/y/w/h` mutate in place.
- No new regressions. `test_readers`, `test_repls`, `test_tree_navigations`,
  `test_split_pane_drag`, `test_object_to_widget`, `test_widget_text_editing`,
  `test_dirty_rect` pass; the failures in `test_text_navigations` (5),
  `test_click_roundtrips` (3) and `test_mouse_clicks` (1) are **pre-existing on
  the base commit** (verified by stashing) — the `searching`/`dbcatalog`/
  `sql_syntax`/widget-wrapped examples.

### Design notes (why the originally-listed options don't work as written)

- **Store the local step only:** breaks readers that legitimately walk the full
  suffix at one node (e.g. `_leaf_cursor` needs `.value[k]` together), and the
  constraint was to keep readers untouched.
- **Full-suffix diff:** the suffix stored at *every* ancestor contains the deep
  caret, so it differs on every caret move — "write only when the stored value
  differs" still rewrites every ancestor. The reactive engine has no
  value-equality short-circuit (`Reactive.jl`), so equal-value writes still
  invalidate. The working answer is **in-place mutation of the shared chain's
  cells**, which changes neither the stored representation nor the readers.

## Context / related

- Done already (prerequisites): caret decoupled from spans in `TextToGraphics`
  and `SyntaxToText`; dirty-rectangle partial rendering in the SDL backend.
- Code: `evaluate_operation(::ReplaceSelectionOperation)`, `clear_selection!`,
  `set_selection!` in `program/src/common/Operation.jl`;
  `_tab_index_from_selection` / `selector_cv` / `content_cv` in
  `program/src/projection/primitive/WidgetToGraphics.jl`.
