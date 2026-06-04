# Anchored Layout

Extend the layout system with a new `AnchoredLayout` document type that positions children relative to target elements' graphics coordinates, with smart collision-aware placement and stacking.

## Context

The existing layout system (`HorizontalLayout`, `VerticalLayout`, `GridLayout`, `FlowLayout`) positions children sequentially. There is no mechanism to position a child element *relative to another element's screen position*. `AnchoredLayout` fills this gap as a first-class layout document type, following the same patterns as the existing layouts.

Use cases include:
- **Annotations**: sidebar markers or inline comments anchored to document elements
- **Floating labels**: labels anchored to chart data points or diagram nodes
- **Context menus / popovers**: UI elements anchored to a clicked or hovered element
- **Callouts**: explanatory content anchored to specific locations in a canvas
- **Tooltips**: alternative tooltip positioning strategy using layout-level anchoring

## Phase 1: AnchoredLayout Document Type

### File: `program/src/document/Layout.jl`

Add new types to the existing `LayoutModule`:

**`AnchoredEntry`** — pairs a positioned child with its anchor target:
```julia
@document struct AnchoredEntry <: Document
    child::Document                  # the positioned child content
    target_document::Any             # direct Cell reference to the target element (or nothing)
    target_reference::ReferencePath  # reference path into the document tree (or EmptyReferencePath)
    placement::Symbol                # preferred side: :above, :below, :left, :right
    offset_x::Int                    # additional pixel offset from computed position
    offset_y::Int                    # additional pixel offset from computed position
    selection::Reference
end
```

Two anchor modes (both can coexist; `target_document` takes priority when non-nothing):
- **Direct**: `target_document` holds a `Cell` pointing at the target `GraphicsCanvas`/element — its `x`/`y` cells are read directly
- **Reference-based**: `target_reference` is a `ReferencePath` resolved via `map_reference_forward` through the projection chain to obtain graphics coordinates

**`AnchoredLayout`** — the layout container:
```julia
@document struct AnchoredLayout <: LayoutDocument
    children::CellVector             # of AnchoredEntry
    content::Document                # the base content document whose elements serve as anchor targets
    bounding_width::Int              # viewport/bounding region width for collision avoidance
    bounding_height::Int             # viewport/bounding region height for collision avoidance
    stacking_gap::Int                # pixel gap between stacked children anchored to the same target
    selection::Reference
end
```

**Design rationale:**
- `AnchoredEntry` follows the pattern of `LayoutConstraint` — a generic wrapper that attaches positioning policy to a child without polluting the child's type
- `content` is the base document whose elements serve as anchor targets; the layout composites anchored entries *on top of* the projected content
- Bounding dimensions enable collision-aware smart placement
- `stacking_gap` controls vertical spacing when multiple anchored children cluster on the same target

## Phase 2: Smart Placement Algorithm

### File: `program/src/document/Layout.jl` (helper functions)

A pure algorithm (no reactive cells), analogous to `allocate_axis`:

**`compute_anchored_positions(entries, target_positions, bounding_w, bounding_h, stacking_gap)`**

Input per entry:
- `entry_w`, `entry_h` — child intrinsic size
- `target_x`, `target_y`, `target_w`, `target_h` — target's bounding rect in graphics coords
- `placement` — preferred side (`:above`, `:below`, `:left`, `:right`)
- `offset_x`, `offset_y` — user-specified offsets

Algorithm:
1. For each entry, compute candidate position at the preferred side of the target rect
2. Check if the candidate overflows the bounding region (`bounding_w × bounding_h`)
3. If overflow, try the opposite side, then the two perpendicular sides
4. Clamp to bounding region as a last resort
5. Apply `offset_x`/`offset_y` after placement
6. **Stacking pass**: detect overlapping entries (same or nearby targets). Group overlapping entries and re-layout each group as a vertical stack with `stacking_gap` spacing. The first entry in the group keeps its computed position; subsequent entries shift downward. Optionally use the existing `allocate_axis` for distributing within the stack.

Returns: `Vector{Tuple{Int,Int}}` — one `(x, y)` per entry.

## Phase 3: AnchoredLayout → GraphicsCanvas Projection

### File: `program/src/projection/primitive/LayoutToGraphics.jl`

Add `AnchoredLayoutToGraphicsCanvas <: Projection` alongside the existing layout projections.

**`projection_print`:**
1. Recurse into `content` to get the base `GraphicsCanvas` and its iomap
2. For each `AnchoredEntry`:
   - Resolve target position:
     - If `target_document` is a `GraphicsCanvas`, read its `x`/`y`/`w`/`h` cells
     - Otherwise, use `map_reference_forward` with `target_reference` through the content iomap to obtain a `PointReference` with graphics coordinates
   - Recurse into `entry.child` to get the child's `GraphicsCanvas`
3. Build reactive `Cell`s that call `compute_anchored_positions` with the resolved targets and child sizes
4. Wrap each child canvas at its computed `(x, y)` via `_wrap_child`
5. Composite: create an outer `GraphicsCanvas` containing both the base content canvas and all positioned child canvases (anchored children rendered on top / after content)
6. Return a `ChildrenIoMap` with entries for both content and anchored children

**`projection_read`:**
- Hit-test anchored entries first (top layer), then fall through to content
- Route events to the appropriate child iomap using `_route_to_children` pattern

**`map_reference_forward` / `map_reference_backward`:**
- Forward: route `children[i]` references to the i-th anchored entry's child iomap; route `content` references to the content iomap
- Backward: reverse of forward

**Wire into `LayoutToGraphics` factory:**
- Add `AnchoredLayout => AnchoredLayoutToGraphicsCanvas()` to the `TypeDispatchingProjection`

## Phase 4: Target Position Resolution Helpers

### File: `program/src/projection/primitive/LayoutToGraphics.jl` (helpers)

**`resolve_target_position(entry, content_iomap)`** — unified helper:
1. If `entry.target_document` is a `GraphicsCanvas`, return `(x, y, w, h)` from its cells
2. Else if `entry.target_reference` is not `EmptyReferencePath`, call `map_reference_forward` on the content iomap's projection chain; if the result is a `PointReference`, use `(x, y, 0, 0)`; if it maps to a `GraphicsCanvas`, read its position/size cells
3. Return `nothing` if unresolvable (child hidden or target orphaned)

This helper returns reactive `Cell`s so position changes propagate without re-projection.

## Phase 5: Integration

### File: `program/src/Projectured.jl`

- Add exports for `AnchoredLayout`, `AnchoredEntry`, `IAnchoredLayout`, `IAnchoredEntry`
- The `LayoutToGraphics` factory already picks up new entries; no separate registration needed

### File: `program/src/document/Layout.jl`

- Add `AnchoredLayout`, `AnchoredEntry` to the module's `export` list
- Import `ReferencePath`, `EmptyReferencePath` from `ReferenceModule`

## Phase 6: Line Leaders (Visual Connectors)

After placement, anchored children may be offset from their targets. Add optional line-leader rendering:

- Each `AnchoredEntry` gets an optional `show_leader::Bool` field (default `true`)
- The projection emits a `GraphicsRect` (1–2 px wide) connecting the child edge to the target center, drawn before the child canvas so it appears behind it
- Color and thickness configurable via fields on `AnchoredLayout` (e.g. `leader_color`, `leader_thickness`)

## Implementation Steps

1. Add `AnchoredEntry` and `AnchoredLayout` document types to `Layout.jl`
2. Implement `compute_anchored_positions` pure algorithm in `Layout.jl`
3. Add `AnchoredLayoutToGraphicsCanvas` projection to `LayoutToGraphics.jl`
4. Add target resolution helpers
5. Wire into `LayoutToGraphics` factory and `Projectured.jl` exports
6. Add line-leader rendering
7. Add tests

## Examples

**Annotation sidebar** (primary use case from the annotation feature plan):
```julia
# Annotations anchored to document elements, placed to the right
AnchoredLayout(
    [AnchoredEntry(annotation_widget, target_element, EmptyReferencePath(), :right, 10, 0)],
    document_canvas, 800, 600, 4
)
```

**Floating labels on a chart**:
```julia
# Labels anchored above data points
AnchoredLayout(
    [AnchoredEntry(label, data_point, EmptyReferencePath(), :above, 0, -4) for (label, data_point) in pairs],
    chart_canvas, chart_width, chart_height, 2
)
```

**Context menu anchored to a clicked element**:
```julia
AnchoredLayout(
    [AnchoredEntry(menu_widget, clicked_element, EmptyReferencePath(), :below, 0, 2)],
    editor_canvas, viewport_w, viewport_h, 0
)
```

## Future Extensions

- **Grouping strategies**: cluster anchored children by region and show as expandable groups
- **Animation**: smooth transitions when children reposition after edits
- **Z-ordering**: explicit z-index per entry for controlling layer order
- **Anchor stability**: integrate with annotation plan's anchor-survival-across-edits mechanism
