# Fix selection tests — Ctrl+Home unreachable for 7 examples

## Background

`test_selections` runs `explore_selections` on every example except `widget` and
`workbench`.  It BFS-walks all reachable selection states by pressing navigation
keys, starting from the state reached by Ctrl+Home.  7 examples currently fail
with "Ctrl+Home returned no selection".

All failures are pre-existing (present in the initial commit); they were not
exposed by the original test because the original `ReaderTest` only probed 24
key events and the original `SelectionTest` used the older `KeyPress` API.

Root causes and fixes fall into three groups.

---

## Group 1: `collection`, `reversing`, `filtering`, `sorting`

### Root cause

Chain for `collection`: `SequentialProjection([NestingProjection, RecursiveProjection, TextToGraphics])`.

Ctrl+Home → `TextToGraphics` returns `ReplaceSelectionOperation(.open{0})` (text
domain) → `RecursiveProjection` backward-translates to `ReplaceSelectionOperation(.open{0})`
(syntax domain) → `NestingProjection` passes to its element[1], which is
`CollectionCellVectorToSyntax`.

`CollectionCellVectorToSyntax` has **no `projection_read` method at all**, so
Julia returns `nothing` → "Ctrl+Home returned no selection".

`reversing`, `filtering`, `sorting` all use the same `CollectionToSyntax`
projection as an inner step, so they share the same failure.

### Fix

**File:** `program/src/projection/primitive/CollectionToSyntax.jl`

1. Import `SyntaxNodeToText` and `_syntax_to_flat` from `SyntaxToTextModule`.  
   Import `ProjectionReference`, `PositionReference`, `RangeReference`,
   `ConcreteReferencePath` from `ReferenceModule`.  
   Import `ReplaceSelectionOperation` from `OperationModule`.

2. Add a path-translation helper:

   ```julia
   # Maps a SyntaxNode path (children[i].rest) back to the CellVector domain.
   # Returns ConcreteReferencePath(ElementReference(child_i), rest) or nothing.
   function _translate_collection_path(cv::CellVector, path::ReferencePath)
       path isa ConcreteReferencePath || return nothing
       h = path.head
       h isa FieldReference && h.name == "children" || return nothing
       rest0 = path.tail
       rest0 isa ConcreteReferencePath || return nothing
       h2 = rest0.head
       h2 isa RangeReference || return nothing
       child_i = h2.start + 1
       1 <= child_i <= length(cv) || return nothing
       ConcreteReferencePath(ElementReference(child_i), rest0.tail)
   end
   ```

3. Add the `projection_read` method (same pattern as `JsonArrayToSyntaxNode`):

   ```julia
   function projection_read(p::CollectionCellVectorToSyntax,
                             iomap::ChildrenIoMap,
                             op::ReplaceSelectionOperation)
       result = _translate_collection_path(iomap.input, op.path)
       result !== nothing && return ReplaceSelectionOperation(result)
       flat = _syntax_to_flat(iomap.output::SyntaxNode, op.path, SyntaxNodeToText(), 0)
       flat < 0 && return nothing
       return ReplaceSelectionOperation(
           ConcreteReferencePath(ProjectionReference(p, ConcreteReferencePath(PositionReference(flat)))))
   end
   ```

4. **(Optional, for full navigation)** Add a `sel` cell in `projection_print`
   that maps `cv.selection` forward to the SyntaxNode domain — same shape as
   the one in `JsonArrayToSyntaxNode.projection_print`.  Without this, the
   cursor is never rendered inside a collection child, but `test_selections`
   only requires state_count > 0, so it passes without it.

No changes needed to `ReversingProjection`, `FilteringProjection`, or
`SortingProjection` — they sit *outside* the `NestingProjection` step and are
only reached in the final backward pass after the NestingProjection has already
mapped the op to the `CellVector` domain.

---

## Group 2: `widget_tabbed_pane`

### Root cause

Chain: `SequentialProjection([RecursiveProjection(WidgetToGraphics(...))])`.

There is no `TextToGraphics` step.  `WidgetToGraphics` maps widgets directly to
`GraphicsCanvas` and its readers handle mouse events and widget-specific
interactions, but not keyboard cursor navigation (Ctrl+Home etc.).

The test skips `widget` and `workbench` for exactly this reason; `widget_tabbed_pane`
should be treated the same way.

### Fix

**File:** `test/src/editor/SelectionTest.jl`

Extend the skip list:

```julia
example.name in ("widget", "widget_tabbed_pane", "workbench") && continue
```

**Alternative (if tab navigation is desired):**  
Add Ctrl+Home/End handling to `WidgetShellToGraphicsCanvas.projection_read` and
`WidgetTabbedPaneToGraphicsCanvas.projection_read` that return a
`ReplaceSelectionOperation` selecting the first/last tab's content.  This is
more work and should be a separate plan item.

---

## Group 3: `table`, `math_table`

### Root cause

Top-level projection: `NestingProjection(TableToGraphics(); recursion=content_projection)`.

`TableToGraphics` has **no `projection_read` method**.  After our fix to
`NestingProjection.projection_read` (which removed the dead `inner` variable),
it now correctly dispatches to `np.elements[1]` — but `TableToGraphics` drops
every event.

`content_projection` (which has `TextToGraphics`) is stored as `np.recursion`,
and the `NestingProjection.projection_read` (elements non-empty branch) never
consults `np.recursion`.

### Fix

**File:** `program/src/projection/primitive/TableToGraphics.jl`

Add a `projection_read` that delegates to the `recursion` stored in the
`NestingProjectionIoMap`:

```julia
import ..ProjectionApiModule: projection_read
import ..NestingProjectionModule: NestingProjectionIoMap

function projection_read(::TableToGraphics, iomap::NestingProjectionIoMap, event)
    iomap.projection.recursion === nothing && return nothing
    projection_read(iomap.projection.recursion, iomap.child_iomap, event)
end
```

This lets Ctrl+Home tunnel through `TableToGraphics` into the cell's
`content_projection`, which reaches `TextToGraphics` and returns a valid
`ReplaceSelectionOperation`.

> **Note:** The iomap available to `TableToGraphics.projection_read` is the
> `NestingProjectionIoMap` created by `NestingProjection.projection_print`.
> `iomap.child_iomap` is the iomap produced by `projection_print(TableToGraphics, ...)`,
> which is where the recursion cells live.  Verify the iomap type matches
> before landing this.

**Alternative:** Add `table` and `math_table` to the skip list while table
navigation is not yet designed.

---

## Implementation order

1. Group 1 (Collection): highest impact — fixes 4 examples with one method.
2. Group 3 (Table): fix or skip depending on whether TableToGraphics reader is easy to wire.
3. Group 2 (Widget tabbed pane): add to skip list unless tab navigation is planned.

## Verification

After each group's fix:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy julia --project=. \
  -e 'using Projectured, ProjecturedExample, ProjecturedTest; test_selections()'
```

Target: 46 Pass, 0 Fail.
