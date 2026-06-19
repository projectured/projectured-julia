# Add Drag-and-Drop Support

> **Status: DONE** on branch `worktree-dragging`. Document + operation +
> projection + tests, verified **end-to-end through the real json → syntax →
> text → graphics pipeline** (`test_dragging`, 22 assertions): a drag from one
> array element to another emits a `MoveRangeOperation` and reorders the
> collection, with cell identity preserved. The drop/grab references are
> resolved by the projection itself synthesising a `MousePress` at the
> press/release point and delegating it to the inner chain's existing hit-test —
> so **no graphics-layer change was needed** (see "Grab/drop resolution"). The
> original version of this file was an AI brainstorming artifact; it has been
> rewritten against the actual codebase architecture.

Add a `DraggingState` wrapper document and a `DraggingProjection` (a
transparent, stateful gesture interpreter, modelled on
[`TooltipDecoratorProjection`](../../program/src/projection/higherorder/TooltipDecorator.jl))
that turns a press-drag-release on a selected element into a `MoveRangeOperation`
that reorders elements inside the wrapped content document.

## How reading actually works here (the constraint that shapes the design)

Mouse events are **pixel coordinates**. They only become document *references*
at the graphics layer:

- The backend ([`Sdl.jl`](../../program/src/backend/Sdl.jl)) emits `MouseDown`
  on button-down, `MouseUp` on button-up, `MouseMove` (carrying the held button)
  while dragging, and synthesises a `MousePress` **only** when the up lands
  within ~5 px / 300 ms of the down (a click, not a drag).
- The graphics readers (e.g.
  [`TextToGraphics`](../../program/src/projection/primitive/TextToGraphics.jl#L194))
  hit-test **`MousePress`** into a `ReplaceSelectionOperation` carrying the
  reference of the clicked element. `MouseDown` / `MouseUp` / `MouseMove`
  currently produce **no** reference-bearing operation — they fall through.
- A read flows **top→bottom**: the screen layer unwraps the `EventEnvelope` to
  the raw event, the graphics layer hit-tests it, and each lower projection maps
  the resulting operation's reference down toward the domain via
  `map_reference_backward`. A projection sees both the raw gesture
  (`change.gesture`) **and** the operation produced so far (`change.operation`).

Consequence: a content-level projection cannot itself turn `(x, y)` into a
reference — it must read the reference out of the operation the graphics layer
already produced. Today that only happens for `MousePress`. **So for a real
drag (no `MousePress`), neither the grab point nor the drop point would be
resolved into a reference by the usual flow.**

### Grab/drop resolution (the mechanism that made this work)

Rather than add `MouseUp`/`MouseDown` hit-testing to every graphics reader (a
broad change that would also double-fire selection on normal clicks), the
`DraggingProjection` resolves both endpoints itself: on the grabbing `MouseDown`
and the dropping `MouseUp` it **synthesises a left `MousePress` at that pixel and
delegates it to the inner chain** — the exact path a real click takes down
through the graphics layer to the content domain. The returned
`ReplaceSelectionOperation`'s path is the reference under the point. The
synthetic press is only *read*, never applied, so it has no side effects (a drop
onto a collapse marker yields a `ToggleCollapseOperation`, which the projection
ignores → no move, no toggle). This needs **zero changes outside
`DraggingProjection`** and works in the live editor today.

## Where `DraggingProjection` sits

`DraggingState` wraps a content sub-tree. The projection dispatches on
`DraggingState` (type-dispatched, like `TooltipDecoratorProjection` on
`TooltipSource`):

- **Print** is transparent: recurse into `content` through `recursion`
  (`projection_printer_recurse`) and return its output, wrapped in a
  `DraggingProjectionIoMap` holding the inner iomap (so it is reachable for the
  reader's hit-test delegation and reference mapping).
- **Read** runs the gesture state machine, delegating to the inner reader for
  normal events and only overriding on a completed drag.

Reference mapping mirrors `TooltipDecorator`: forward strips a leading
`FieldReference("content")` then delegates to the inner iomap; backward delegates
then prepends `FieldReference("content")`.

## State machine

State is **transient gesture state**, kept on the projection instance (a single
drag at a time) — mirroring how `TooltipDecorator` keeps its arm/open state on
the projection, not on the document. (The split-pane drag chose the other
option — cells on the document mutated by explicit operations; either is
idiomatic. Projection-instance state is simpler here because no intermediate
phase needs to survive a reprint.)

- `:idle` + `MouseDown(:left)` → record press `(x, y)`; resolve the **source**
  reference by hit-testing `(x, y)` (synthetic `MousePress`, see above), falling
  back to `content.selection` if the point hits nothing → `:pending`. Absorb.
- `:pending` + `MouseMove` while held → if `hypot(x-x0, y-y0) ≥ threshold`
  (default 5 px, from `DraggingState.threshold`) → `:dragging`. Absorb.
- `:pending` + `MouseUp` → back to `:idle`, emit nothing — the backend's
  synthesised `MousePress` handles the click selection separately.
- `:dragging` + `MouseMove` → absorb.
- `:dragging` + `MouseUp` → resolve the **destination** reference by hit-testing
  the release point; if source and destination both resolve to a collection +
  index, emit `MoveRangeOperation`; reset to `:idle`.
- Any other gesture → delegate to the inner reader unchanged.

## `MoveRangeOperation`

```
MoveRangeOperation(source::CellVector, source_start, source_stop, destination::CellVector, destination_index)
```

- The reader resolves the grab/drop *references* to **`(CellVector, index)`**
  pairs (via `_locate_collection_index`) and stores the `CellVector`s **directly**
  in the operation — not as `editor.document`-rooted paths. This mirrors how the
  split-pane operations carry the `WidgetSplitPane` itself and sidesteps
  re-rooting the reference up through the projections above `DraggingProjection`.
- `evaluate_operation(editor, ::MoveRangeOperation)` lifts the raw `Cell`s for
  `source_start:source_stop` out of `source` (preserving cell identity), removes
  them, and `insert!`s them at `destination_index` in `destination` (with index
  fix-up when moving within one collection and the removal shifts the target). It
  ignores `editor` entirely — the `CellVector`s are reactive cells shared with the
  document, so mutating them updates it in place.

Resolution helper `_locate_collection_index(content, path)`: split `path` at its
last element `RangeReference`; the prefix resolves (via `evaluate_reference`) to
the owning `CellVector`; the index is that step's element index. Returns
`(cellvector, index)` or `nothing` when the prefix is not a `CellVector`. Real
example: a click on a json array element resolves to `.elements[i].value{0}`,
whose last element `RangeReference` is the `[i]`, so the prefix `.elements`
resolves to the array's `CellVector` at index `i`.

## Files

1. **`program/src/document/Dragging.jl`** — `DraggingDocumentModule`:
   `abstract type DraggingDocument <: Document`, `@document struct DraggingState`
   with `content::Document`, `threshold::Int`, `selection::Reference`; keyword
   constructor `DraggingState(content; threshold=5)`. Included after the other
   wrapper documents in [`Projectured.jl`](../../program/src/Projectured.jl).

2. **`program/src/projection/higherorder/Dragging.jl`** —
   `DraggingProjectionModule`: `DraggingProjection` (holds a mutable `_DragState`),
   `DraggingProjectionIoMap`, transparent `projection_print`, the 4-arg
   `projection_read` state machine (+ 3-arg shim) with the synthetic-`MousePress`
   hit-test helper `_locate_point`, `map_reference_forward` /
   `map_reference_backward`, and the `MoveRangeOperation` + its
   `evaluate_operation`. (Placed with the other higher-order *decorator*
   projections, next to `TooltipDecorator.jl`.)

3. **`program/src/Projectured.jl`** — `include`s, `using`, and re-exports for
   `DraggingState`, `DraggingProjection`, `MoveRangeOperation`.

4. **`test/src/projection/DraggingTest.jl`** — `test_dragging`, wired into
   `ProjecturedTest.jl` (22 assertions).

## Testing (`test_dragging`)

Three unit tests drive the state machine with a stub inner projection that maps a
synthetic `MousePress`'s x coordinate to a content reference (playing the
graphics hit-test), plus one **real-pipeline** integration test:

1. *press → drag → drop reorders the collection*: `MouseDown` (grab resolves via
   hit-test) → `:pending`/no op; `MouseMove` past threshold → `:dragging`/no op;
   `MouseUp` (drop resolves) → `MoveRangeOperation`; `evaluate_operation` reorders
   the `CellVector` and preserves cell identity.
2. *sub-threshold press-release is a click, not a drag*: release within the
   threshold emits no op (the backend's synthesised `MousePress` selects).
3. *drop on an unresolvable target yields no move*.
4. *real pipeline*: wrap a `JsonArray` and project it through
   `make_json_projection_example()` (json → syntax → text → graphics); feed real
   pixel `MouseDown`/`MouseMove`/`MouseUp` on the rendered element rows and assert
   the emitted `MoveRangeOperation` reorders `[10,20,30]` → `[20,10,30]`. This
   exercises the synthetic-`MousePress` hit-test through the actual graphics layer.

Run the narrow scope (`test_dragging()`); do **not** run `test_all`.

## Possible follow-ups (not needed for the core feature)

- Accept drops in **widget / layout** containers (`WidgetToGraphics`,
  `LayoutToGraphics`) — the synthetic-`MousePress` resolution is domain-agnostic,
  so this is mostly about those readers already hit-testing `MousePress` (they
  do) and the dragged collection being a `CellVector` the helper can resolve.
- Multi-element (range) drags: `MoveRangeOperation` already takes
  `source_start:source_stop`; only the reader currently fills a single element.

## Out of scope

- Drag *cursor* / ghost feedback during the drag (backend cursor support).
- Cross-document drags, multi-select drags, copy-vs-move modifiers.
- Persisting/serialising transient drag state.
</content>
