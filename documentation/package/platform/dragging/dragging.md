# Dragging

> **Kind:** design · **Status:** current · **Stands on:** [higher-order-projections.md](../projection/higher-order-projections.md), [dragtracking.md](../dragtracking/dragtracking.md)

The dragging slice of `ProjecturedPlatform` adds reorder by drag and drop to any document: a wrapper document, a projection that reads the press and the drop, and the operation that moves elements between collections. The [DraggingProjection section](../projection/higher-order-projections.md#draggingprojection) of the higher-order guide describes the reader step by step; this document says why it is built this way and how to use it.

## How it works

`DraggingState` wraps a `content` document and a `threshold` in pixels, and holds `press`, a view-state field: `(x, y, source, started)` while a press may become a drag, or `nothing`. `DraggingProjection` has no field of its own; it prints the content and returns its output, so the wrapper adds nothing to the view.

A left `MouseDown` with no press yet keeps one, with `source` the path that the mouse target of the content names, or the selection when the content names no target. A move past `threshold` pixels starts the drag: the state answers `StartDragOperation(EmptyReference(), press.source)` beside its write of `press`, so the dragtracking slice ([dragtracking.md](../dragtracking/dragtracking.md)) keeps the path of the state and sends it `DragEnd` and `DragCancel` from then on, wherever the pointer is. A release before that move is a plain click, which the gesture tracker makes of it, and clears the press. Every event, the moves included, still goes on to the content, so the mouse target of the content follows the pointer also during a drag; the reader adds the `content` step to the operation the content answers.

`DragEnd` reads the drop at the mouse target of the content, at the release — the same field the moves already kept up to date — through `find_drop_zone(state::DraggingState, dragged, point)`, and clears the press. `DragCancel` clears the press and moves nothing.

`MoveRangeOperation` holds the source `CellVector`, the range, the destination `CellVector` and the index. It moves the cells themselves, so a moved element keeps its identity and its IO map. Its inverse moves the block back.

## How it fits

The dragging slice depends on the kernel, on the collection and projection slices, and on the dragtracking slice, which sends `DragEnd` and `DragCancel` to the state by its own path once a drag starts. The pane slice uses `MoveRangeOperation` to move a tab; it does not use `DraggingProjection`, because the split pane and the tabs have their own drag readers, described in [pane.md](../pane/pane.md) and in [dragtracking.md](../dragtracking/dragtracking.md). It registers nothing.

## Design decisions

- **The drag state is a view-state field of the document, not of the projection.** `StartDragOperation` names a path, and the dragtracking slice sends the gestures of the drag to that path; a state kept only inside the projection instance could not be reached that way. The split pane divider and the slider keep their own drag state in document fields for the same reason.
- **A drag finds its points from the mouse target, not a synthetic click.** The content already keeps its mouse target up to date on every move, whether or not a drag is on; reading that field at the press and at the release needs no event made for the purpose, and no graphics reader resolves one twice.
- **The operation holds the collections, not paths.** A path from the root would have to be rooted again through every projection above the drag.

## Usage

```julia
array      = JsonArray(JsonString("apple"), JsonString("banana"), JsonString("cherry"))
document   = make_dragging_document(array; threshold = 5)
projection = make_dragging_projection(make_json_projection_example())
run_example(document, projection; name = "drag")
```

- Example: `dragging_example`, which wraps a JSON array.
- Test: `test_dragging()` in `test/projectured/projection/DraggingProjectionTest.jl`.

## Limits

- One drag at a time for each `DraggingState`.
- A drop where the mouse target of the content names no collection element makes no operation.
