# Dragging

> **Kind:** design · **Status:** current · **Stands on:** [higher-order-projections.md](../projection/higher-order-projections.md), [operation.md](../../kernel/operation.md)

The dragging slice of `ProjecturedPlatform` adds reorder by drag and drop to any document: a wrapper document, a projection that reads the press, the drag and the drop, and the operation that moves elements between collections. The [DraggingProjection section](../projection/higher-order-projections.md#draggingprojection) of the higher-order guide describes the reader step by step; this document says why it is built this way and how to use it.

## How it works

`DraggingState` wraps a `content` document and a `threshold` in pixels. `DraggingProjection` prints the content and returns its output, so the wrapper adds nothing to the view. The reader is a state machine: a left `MouseDown` starts it, a move past the threshold makes it a drag, and the `MouseUp` of a drag makes a `MoveRangeOperation`. A `MouseUp` before the threshold is a click, and the click path of the backend handles it. Any other event goes to the content, and the reader adds the `content` step to the operation that comes back.

A mouse event becomes a reference only at the graphics stage, and only for a `MouseClick`. So the reader makes a `MouseClick` at the point of the grab and of the drop, gives it to the content chain, and reads the path of the `ReplaceSelectionOperation` that comes back. It does not apply that operation.

`MoveRangeOperation` holds the source `CellVector`, the range, the destination `CellVector` and the index. It moves the cells themselves, so a moved element keeps its identity and its IO map. Its inverse moves the block back.

## How it fits

The dragging slice depends on the kernel and on the collection and projection slices. The pane slice uses `MoveRangeOperation` to move a tab; it does not use `DraggingProjection`, because the split pane and the tabs have their own drag readers. It registers nothing.

## Design decisions

- **The drag state is on the projection, not in the document.** No phase of a drag must survive a new print, so the state need not be data. The split pane keeps its drag in document cells instead, because its divider position is data. See [plan/done/dragging.md](../../../../plan/done/dragging.md).
- **A drag finds its points with a synthetic press.** Every graphics reader already resolves a `MouseClick`. Teaching them all to resolve `MouseUp` would be a wide change, and a real click would then select twice.
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

- One drag at a time for each `DraggingProjection` instance.
- A drop at a point where the content resolves no reference, or no collection element, makes no operation.
