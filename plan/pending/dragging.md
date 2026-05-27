# Add Drag-and-Drop Support

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

Add a `DraggingDocument` (state holder) and a `Dragging` projection (gesture interpreter) that enables drag-and-drop of document elements within a content document.

## Design Summary

**Drag gesture**: Mouse down → pending → mouse move while held (past threshold) → dragging active → mouse up = drop.  
If the mouse is released before exceeding the movement threshold, no drag occurs (falls through as normal click).

**State machine** (stored in `DraggingState`):
- `idle` + mouse down (`MouseDown`) → store press coords + resolve source selection → `pending`
- `pending` + mouse move while held (`MouseMove`) → if distance from press exceeds threshold → `dragging`
- `pending` + mouse up (`MouseUp`) → reset to `idle`, delegate original click to inner projection as `MousePress` (normal selection)
- `dragging` + mouse move while held (`MouseMove`) → update current destination coords
- `dragging` + mouse up (`MouseUp`) → resolve destination via inner iomap, produce `OperationDraggingMove`, reset to `idle`

## Files to Create

### 1. `program/src/document/Dragging.jl` — `DraggingModule`

- `abstract type DraggingDocument <: Document end`
- `@document struct DraggingState <: DraggingDocument` with fields:
  - `content::Document` — the wrapped document where dragging applies
  - `phase::Symbol` — `:idle`, `:pending`, or `:dragging`
  - `source::ReferencePath` — selection at drag start (what's being dragged)
  - `start_x::Int`, `start_y::Int` — pixel coords of initial mouse press
  - `current_x::Int`, `current_y::Int` — current mouse pixel coords during drag
  - `threshold::Int` — pixel distance before pending → dragging (default 5)
  - `selection::Reference`
- Convenience constructor: `DraggingState(content; threshold=5)`

### 2. `program/src/device/Mouse.jl` — *(already done by mouse-events plan)*

`MouseDown`, `MouseUp`, `MousePress`, `MouseMove`, and `MouseScroll` are all
implemented. `MouseRelease` is superseded by `MouseUp`.

### 3. `program/src/backend/Sdl.jl` — *(already done by mouse-events plan)*

`SDL_MOUSEBUTTONUP` → `MouseUp`, `SDL_MOUSEMOTION` (while button held) →
`MouseMove` are both forwarded. No further changes needed here.

### 4. `program/src/projection/primitive/Dragging.jl` — `DraggingProjectionModule`

- `struct DraggingProjection <: Projection` (no extra fields needed)
- `projection_print`: recurse into `DraggingState.content` via the recursion argument, return `ContentIoMap`
- `projection_read`: the gesture state machine:
  - **idle + `MouseDown`**: store press coords + resolve source selection via inner iomap, set phase to `:pending`, absorb event (return `nothing`)
  - **pending + `MouseMove`**: check distance from press coords; if past threshold → set `:dragging`, absorb
  - **pending + `MouseUp`**: reset to `:idle`, re-emit as `MousePress` to inner projection so normal selection fires
  - **dragging + `MouseMove`**: update current destination coords in `DraggingState`, absorb
  - **dragging + `MouseUp`**: resolve destination via inner iomap, produce `MoveRangeOperation` (or `nothing` if unresolvable), reset to `:idle`
  - **all other events**: delegate to inner projection read
- `MoveRangeOperation <: Operation` with:
  - `source_collection` — the source CellVector
  - `source_range` — start/stop indices of elements to move
  - `destination_collection` — the destination CellVector
  - `destination_position` — insertion index in destination
- `evaluate_operation(::MoveRangeOperation, document)`: remove elements from source collection range, insert them at destination position in destination collection
- Result of a completed drag is either a `MoveRangeOperation` or `nothing` (if source/destination can't be resolved to collections)

### 5. `program/src/Projectured.jl` — Wire everything up

- Add `include("document/Dragging.jl")` in the document section
- Add `include("projection/primitive/Dragging.jl")` in the primitive projections section
- Add `using` and `export` lines for the new types

## Steps

1. ~~Add `MouseRelease` to `Mouse.jl`~~ — done; `MouseUp` serves this role.
2. ~~Update `Sdl.jl`~~ — done; `MouseUp` and `MouseMove` are already forwarded.
3. Create `document/Dragging.jl`
4. Create `projection/primitive/Dragging.jl`
5. Wire into `Projectured.jl` (includes, using, exports)
