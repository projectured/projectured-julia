# Graph Domain

A domain for **graphs** — vertices and edges — where a vertex's content is an
arbitrary `Document` (a table, an XML tree, JSON, even another graph) and an edge
connects two vertices. Graphs are laid out by an external constraint-based engine
(Adaptagrams: **libcola** for node placement, **libavoid** for edge routing) into
a separate, editable **graph-layout document** carrying geometry and constraints,
which is then projected to graphics with finite-size node boxes and spline/polyline
edges.

This follows the existing split between the `Table` semantic domain, the `Layout`
geometry layer ([Layout.jl](../../program/src/document/Layout.jl)), and the
`…ToGraphics` projections — generalised to two-dimensional, non-sequential
placement.

## Goals (from the brainstorm)

1. **Vertices + edges.** A graph is vertices and edges; an edge connects two
   vertices (held by identity).
2. **A vertex can be anything.** `GraphVertex.content::Document` accepts any
   domain — table, XML, JSON, … — rendered via the shared recursion.
3. **Layout documents with constraints.** First-class `GraphLayout`,
   `VertexLayout`, `EdgeLayout` documents (mirroring `Layout.jl` /
   `LayoutConstraint`) hold positions, sizes, edge routes, and layout constraints.
4. **Graph → Graphics projection.** Nodes render as finite-size boxes; edges as
   splines or polylines (with arrowheads).
5. **External layout engine.** Adaptagrams via FFI — libcola places nodes,
   libavoid routes edges — behind a swappable `GraphLayoutEngine` interface.

## Scope of v1

**Display + selection only.** Render graphs and navigate/select into vertex
content. *No* mouse drag-to-reposition and *no* structural add/remove of
vertices/edges yet — both are called out in Future Work. This keeps v1 to: new
graphics primitives, the three document layers, the engine binding, two
projections, and a read path that descends into vertex content.

## Decisions (locked in the brainstorm)

- **Engine: Adaptagrams FFI.** libcola for placement, libavoid for connector
  routing. Wrapped behind a `GraphLayoutEngine` interface so the native binding is
  one swappable seam (see Phase 4 + the FFI risk note).
- **Edges: a new first-class graphics primitive** (`GraphicsPolyline` /
  `GraphicsSpline` + arrowheads), with renderers in all three backends — not a
  chain of `GraphicsLine`s. Gives clean vector PDF output and native arrowheads.
- **v1 = display + selection only** (above).

## Pipeline

```
GraphGraph                 vertices + edges; vertex content = any domain
   │  GraphToGraphLayout    size each vertex (recurse content → measure w/h),
   ▼                        run the engine → node positions + edge routes
GraphLayout                 VertexLayout{x,y,w,h}, EdgeLayout{route}, constraints
   │  GraphLayoutToGraphics  boxes + spline/polyline edges + arrowheads;
   ▼                         recurse vertex content into each box
GraphicsCanvas ──▶ SDL / Web / PDF
```

The **layout document is a real intermediate**, not a transient: it persists
positions so manual edits (a later phase) survive, makes geometry inspectable and
testable, and is itself projectional. Reactivity keeps it incremental — the engine
re-runs only when topology or a vertex size actually changes.

---

## Phase 1 — Graphics primitives for edges

### File: `program/src/document/Graphics.jl`

Add reactive primitives alongside `GraphicsLine` / `GraphicsCircle`:

- `GraphicsPolyline` — `points::Vector{Point2D}` (or a `CellVector` of points),
  `r,g,b,a`, `width`, optional `start_arrow::Bool`, `end_arrow::Bool`,
  `arrow_size`. Renders connected straight segments; the canonical libavoid
  polyline route.
- `GraphicsSpline` — control/through points + a `kind` (`:bezier` | `:catmullrom`).
  Backends tessellate to a polyline at render time (shared tessellation helper, so
  curve quality is one knob). Arrowhead flags as above.

Arrowheads render as a small filled triangle oriented along the last segment
(shared helper `_arrowhead(points, size)` returning triangle vertices).

### Files: `backend/Sdl.jl`, `backend/Web.jl`, `backend/Pdf.jl`

- **SDL** (`Sdl.jl`): draw polyline as anti-aliased segments (extend the existing
  diagonal-`GraphicsLine` path); splines via tessellation; arrowhead as a filled
  triangle.
- **Web** (`Web.jl`): emit a draw-list op (`{op:"polyline", points, …}` /
  `{op:"spline", …}`); add the matching path in the browser renderer
  ([program/web/](../../program/web/)) using `canvas.lineTo` / `bezierCurveTo`.
- **PDF** (`Pdf.jl`): native vector path (`m`/`l`/`c` operators) — this is the
  payoff of a real primitive over line-chains.

### Hit-testing: `Graphics.jl`

Add `_*_hit` for the new primitives (point-near-segment within `width`/tolerance),
so edges are selectable later. v1 only needs vertex hit-testing for selection, but
add edge hit-testing here while the primitive is fresh.

---

## Phase 2 — Graph domain types

### File: `program/src/document/Graph.jl` (`GraphModule`)

```
GraphDocument (abstract)
├── GraphInsertion   — type-in entry point
├── GraphVertex      — content::Document (any domain) + identity
├── GraphEdge        — source/target vertices (by identity) + directed flag + label
└── GraphGraph       — vertices + edges + selection
```

- `GraphVertex <: GraphDocument`
  - `content::Document` — arbitrary domain (table/xml/json/…); rendered via the
    shared recursion, exactly like `TableCell.content`.
  - `selection::Reference`
  - Identity is the document object itself (its `Cell` reference), so edges can
    point at it — same identity model as the formula reference and
    `AnchoredEntry.target_document`.

- `GraphEdge <: GraphDocument`
  - `source::Document` — the source `GraphVertex` (held by identity).
  - `target::Document` — the target `GraphVertex`.
  - `directed::Bool` — draw an end arrowhead when true.
  - `label::Document` — optional edge label (`nothing` or a small content doc).
  - `selection::Reference`

- `GraphGraph <: GraphDocument`
  - `vertices::CellVector` — of `GraphVertex`.
  - `edges::CellVector` — of `GraphEdge`.
  - `selection::Reference`

Field names (`content`, `source`, `target`, `vertices`, `edges`) are the public
reference vocabulary per the `Document` contract. Because `GraphGraph` is a
`Document` and `content` is arbitrary, a vertex may itself hold a `GraphGraph`
(nested graphs) for free via type-dispatch.

Register in `Projectured.jl` (include / using / export), per the
[tutorial](../tutorial-new-domain.md) Step 2.

---

## Phase 3 — Graph-layout documents + constraints

### File: `program/src/document/GraphLayout.jl` (`GraphLayoutModule`)

Geometry layer mirroring `Layout.jl` / `LayoutConstraint`:

- `VertexLayout <: Document`
  - `vertex::Document` — the `GraphVertex` this positions (by identity).
  - `x, y, w, h::Int` — placed rect (w/h seeded from the vertex's projected size).
  - `pinned::Bool` — if true, the engine treats position as fixed (foundation for
    later drag-to-move; in v1 always engine-driven).
  - `selection::Reference`

- `EdgeLayout <: Document`
  - `edge::Document` — the `GraphEdge` (by identity).
  - `route::CellVector` (or `Vector{Point2D}`) — waypoints from libavoid (a
    polyline; or spline control points).
  - `source_port`, `target_port::Symbol` — anchor side on each box (`:auto`,
    `:top`, …).
  - `selection::Reference`

- `GraphLayout <: Document`
  - `vertex_layouts::CellVector`, `edge_layouts::CellVector`.
  - `direction::Symbol` — rank direction hint (`:tb`, `:lr`, `:none`).
  - `node_sep, rank_sep::Int` — spacing knobs fed to the engine.
  - `selection::Reference`

- `GraphConstraint <: Document` — per-vertex/edge policy wrapper, analogous to
  `LayoutConstraint`: `kind::Symbol` (`:pin`, `:same_rank`, `:align`,
  `:fixed_size`, `:min_separation`, `:cluster`), plus payload fields. Constraint
  readers translate these into Adaptagrams constraint objects in Phase 4. v1 may
  ship just `:pin` + `:fixed_size`; the rest are scaffolding.

---

## Phase 4 — GraphLayoutEngine interface + Adaptagrams FFI

### File: `program/src/layout/GraphLayoutEngine.jl`

A pure-ish interface so the native binding is swappable and memoizable:

```julia
abstract type GraphLayoutEngine end
# returns (positions::Dict{vertex => (x,y,w,h)}, routes::Dict{edge => Vector{Point2D}})
layout_graph(engine, graph, sizes, constraints) -> (positions, routes)
```

- `FallbackLayoutEngine` — pure Julia: simple grid or basic force placement +
  straight/orthogonal edge routes. **No native dependency** — keeps every phase
  testable and unblocks development while the Adaptagrams build is sorted.
- `AdaptagramsEngine` — FFI:
  - **libcola** → node positions honouring constraints (rank, alignment,
    separation, pins).
  - **libavoid** → poly-line / orthogonal connector routes that avoid node
    obstacles, given the placed boxes.
  - Bridged via `ccall` (the established pattern in `Sdl.jl`).

### FFI / build risk (call out explicitly)

There is no ready Adaptagrams JLL. Options, in order of preference:

1. Build an `Adaptagrams_jll` via BinaryBuilder and add it to `Project.toml`
   (alongside `SDL2_jll`).
2. A small C shim exposing a flat `extern "C"` API (graph in → positions+routes
   out), vendored and `ccall`ed — simplest stable ABI for FFI.

Until either lands, `FallbackLayoutEngine` is the default so nothing downstream is
blocked. The engine call is **memoized and keyed on topology + sizes + constraints**,
kept out of frequently-rerun reactive thunks (native calls are not free and not
purely functional); it re-runs only when that key changes.

---

## Phase 5 — GraphToGraphLayout projection

### File: `program/src/projection/primitive/GraphToGraphLayout.jl`

The chicken-and-egg step: **sizing precedes placement.**

`projection_print(GraphGraphToGraphLayout, recursion, graph, ctx)`:
1. For each `GraphVertex`, recurse `vertex.content` through `recursion` to a
   `GraphicsCanvas` and read its `w`/`h` cells → the vertex's intrinsic size
   (reactive: a size change invalidates the layout).
2. Collect constraints from any `GraphConstraint` wrappers.
3. Call `layout_graph(engine, graph, sizes, constraints)` (memoized).
4. Build a `GraphLayout` whose `VertexLayout`/`EdgeLayout` cells hold the engine's
   positions and routes.
5. Return an `IoMap` (`ChildrenIoMap`) recording the vertex/edge correspondence so
   selection can cross this projection (peel-and-delegate, tutorial School A).

Mappers route `vertices[i]` ↔ the i-th `VertexLayout.vertex`, so a selection into
vertex content round-trips.

---

## Phase 6 — GraphLayoutToGraphics projection

### File: `program/src/projection/primitive/GraphLayoutToGraphics.jl`

`projection_print(GraphLayoutToGraphicsCanvas, recursion, layout, ctx)`:
1. For each `VertexLayout`: a node box = a `GraphicsRect` (rounded outline) at
   `(x,y,w,h)`, with the vertex's projected content canvas placed inside (recurse
   `vertex.content`, offset to the box origin — the `_wrap_child` pattern from
   `LayoutToGraphics.jl`).
2. For each `EdgeLayout`: a `GraphicsPolyline`/`GraphicsSpline` along `route`,
   `end_arrow = edge.directed`; optional label canvas at the route midpoint.
3. Composite into one outer `GraphicsCanvas` (edges drawn first, nodes on top).
4. `ChildrenIoMap`; mappers route `vertex_layouts[i]` references to the i-th node's
   child iomap. Edges are decorations in v1 (selectable later via Phase 1 hit-tests).

Convenience: `GraphToGraphics()` =
`SequentialProjection(RecursiveProjection(GraphToGraphLayout()),
RecursiveProjection(GraphLayoutToGraphics()))` (then `TextToGraphics` is not
needed — these go straight to a `GraphicsCanvas`, like `TableToGraphics`).

---

## Phase 7 — Selection / navigation (read path, v1)

- Forward/backward mappers in Phases 5–6 already let the selection descend
  `graph → vertices[i] → content → …` into a vertex's own domain, where that
  domain's existing readers take over (cursor movement, char edit within a table
  cell, etc.).
- Mouse click-to-select hit-tests node boxes (Phase 1 helpers) and routes into the
  vertex content, reusing the existing click-roundtrip machinery.
- **Out of scope for v1:** dragging a node (would write `VertexLayout.x/y` + set
  `pinned`), and add/remove operations — see Future Work.

---

## Phase 8 — Example

- `example/src/document/Graph.jl` — `make_graph_document_example()`: a small graph
  whose vertices are *different domains* (one `TableTable`, one `JsonObject`, one
  `XmlElement`) with a few directed edges, to show "a vertex can be anything."
- `example/src/projection/Graph.jl` — `make_graph_projection_example()` building
  `GraphToGraphics()` (defaulting to `FallbackLayoutEngine`, switchable to
  `AdaptagramsEngine`).
- Register in `ProjecturedExample.jl` + `Examples.jl` (`graph_example`) so
  `run_example("graph")` works.

---

## Phase 9 — Tests

Targeted helpers per [testing.md](../testing.md) / CLAUDE.md (not `test_all`):

- Graphics primitive tests — `GraphicsPolyline`/`GraphicsSpline` construct,
  tessellate, and hit-test (point-near-segment); arrowhead geometry.
- `FallbackLayoutEngine` unit tests — positions are disjoint, routes connect the
  right boxes (deterministic, no native dep).
- `test_graph_to_graph_layout()` — vertex sizes feed placement; a content-size
  change invalidates and re-lays-out (reactive).
- `GraphLayoutToGraphics` printer — node boxes contain projected content; directed
  edges carry an end arrow.
- `test_printer` / `test_text_navigation` on `graph_example` — selection descends
  into vertex content.

---

## Implementation order

1. Phase 1 graphics primitives + backend renderers + hit-tests.
2. Phase 2 graph domain types.
3. Phase 3 graph-layout documents + constraints.
4. Phase 4 engine interface + `FallbackLayoutEngine` (Adaptagrams FFI can land in
   parallel / later behind the same interface).
5. Phase 5 GraphToGraphLayout (sizing + engine call).
6. Phase 6 GraphLayoutToGraphics.
7. Phase 7 read path (selection into vertex content).
8. Phases 8–9 example + tests.
9. Adaptagrams build (`Adaptagrams_jll` or C shim) + `AdaptagramsEngine`.

## Dependencies / prerequisites

- `Graphics` domain + the three backends (present) — extended in Phase 1.
- `Layout.jl` / `LayoutConstraint` patterns (present) — mirrored in Phase 3.
- Recursive type-dispatch projection pattern (present) for arbitrary vertex content.
- **New native dependency:** Adaptagrams (libcola + libavoid) via JLL or C shim —
  the one external build item; `FallbackLayoutEngine` removes it from the critical
  path.

## Future work

- **Drag-to-move** a vertex → write `VertexLayout.x/y`, set `pinned`, re-route only
  affected edges (reuse the dragging/hit-test precedent).
- **Structural editing** — add/remove vertices and edges (operations + readers).
- **Edge selection / editing** — waypoints draggable; labels editable.
- **Orthogonal routing & clustering** — expose more libavoid/libcola constraint
  kinds through `GraphConstraint` (`:same_rank`, `:cluster`, ports).
- **Nested graphs** — a vertex whose content is a `GraphGraph` (works structurally
  already; needs layout nesting/sizing polish).
- **Incremental layout** — feed previous positions as warm-start so the graph does
  not jump on small edits.
</content>
