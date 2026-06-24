# Graph Domain

> **AUDIT (2026-06-23):** All v1 phases are implemented and verified against the
> current codebase (paths now under `package/<subpackage>/src/...`). The graph
> domain, layout documents, fallback engine, both projections, the new graphics
> primitives + all three backend renderers, the example, and the tests all exist.
> Per-step status is annotated inline below.
>
> **UPDATE (2026-06-24):** The native `AdaptagramsEngine` is now implemented — as
> its own package `package/adaptagrams/` (`ProjecturedAdaptagrams`), kept separate
> from `ProjecturedDomain` because it carries an external native dependency. It
> binds libcola (placement) + libavoid (routing) through a vendored `extern "C"`
> shim (`deps/adaptagrams_shim.cpp`) compiled by `deps/build.jl` and called via
> `ccall`. Verified end-to-end against a system Adaptagrams install in `/usr/local`.
> `FallbackLayoutEngine` remains the default; nothing in core depends on the native
> engine.

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

1. **✅ DONE (verified):** **Vertices + edges.** A graph is vertices and edges; an edge connects two
   vertices (held by identity). — `package/domain/src/document/Graph.jl` (`GraphGraph`, `GraphVertex`, `GraphEdge`).
2. **✅ DONE (verified):** **A vertex can be anything.** `GraphVertex.content::Document` accepts any
   domain — table, XML, JSON, … — rendered via the shared recursion. — `Graph.jl:55` `content::Document`; example mixes WidgetTable/Json/Xml.
3. **✅ DONE (verified):** **Layout documents with constraints.** First-class `GraphLayout`,
   `VertexLayout`, `EdgeLayout` documents (mirroring `Layout.jl` /
   `LayoutConstraint`) hold positions, sizes, edge routes, and layout constraints. — `package/domain/src/document/GraphLayout.jl` (also `GraphConstraint`).
4. **✅ DONE (verified):** **Graph → Graphics projection.** Nodes render as finite-size boxes; edges as
   splines or polylines (with arrowheads). — `GraphLayoutToGraphics.jl` (GraphicsRect boxes + GraphicsPolyline with `end_arrow`).
5. **✅ DONE (verified):** **External layout engine.** Adaptagrams via FFI — libcola places nodes,
   libavoid routes edges — behind a swappable `GraphLayoutEngine` interface. — Interface + `FallbackLayoutEngine` in `GraphLayoutEngine.jl`; native `AdaptagramsEngine` in its own package `package/adaptagrams/` (`ProjecturedAdaptagrams`), binding libcola/libavoid through a C shim via `ccall`.

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

**✅ DONE (verified):** `GraphicsPolyline` + `GraphicsSpline` exist in
`package/domain/src/document/Graphics.jl` (lines 197/232) with `tessellate_spline`,
`polyline_arrowhead`, `point_near_polyline` helpers (exported lines 28). Hit-testing
for both primitives at `Graphics.jl:594-598`; bounds at `Graphics.jl:674-679`.
Backend renderers: SDL `package/sdl/src/ProjecturedSdl.jl:811-866`, PDF native
vector path `package/domain/src/backend/Pdf.jl:418-458`, Web draw-list op
`package/web/src/ProjecturedWeb.jl:223-233` + `package/web/assets/client.js:193,268`.

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

**✅ DONE (verified):** `package/domain/src/document/Graph.jl` defines
`GraphDocument`, `GraphInsertion`, `GraphVertex` (`content::Document`),
`GraphEdge` (`source`/`target`/`directed`/`label`), `GraphGraph`
(`vertices`/`edges`/`selection`) exactly as specified. Registered in
`package/domain/src/ProjecturedDomain.jl:85`.

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

**✅ DONE (verified):** `package/domain/src/document/GraphLayout.jl` defines
`VertexLayout` (`vertex,x,y,w,h,pinned`), `EdgeLayout` (`edge,route,source_port,
target_port`), `GraphLayout` (`vertex_layouts,edge_layouts,direction,node_sep,
rank_sep`), and `GraphConstraint` (`target,kind,payload`). Registered in
`ProjecturedDomain.jl:86`.

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

**✅ DONE (verified):** Interface + `FallbackLayoutEngine` in
`package/domain/src/layout/GraphLayoutEngine.jl` (abstract `GraphLayoutEngine`,
`layout_graph`, grid placement + border-to-border routing, registered
`ProjecturedDomain.jl:87`). Native `AdaptagramsEngine` implemented in the separate
`ProjecturedAdaptagrams` package (`package/adaptagrams/`) — see "Engine packaging"
below. The domain keeps a comment where the stub used to be, pointing at the
package, so core never depends on Adaptagrams.

### Engine packaging — `ProjecturedAdaptagrams` (separate package)

Chosen over option (1)/(2) below: **option (2), a vendored `extern "C"` C shim**,
housed in **its own Julia package** so the external native dependency stays out of
`ProjecturedDomain`. Layout:

- `package/adaptagrams/Project.toml` — `name = "ProjecturedAdaptagrams"`, depends
  on `ProjecturedDomain` + `Libdl`. (No `[sources]` entry: the root project's
  `[sources]` supplies `ProjecturedDomain`; a `[sources]` here makes
  `Pkg.build` resolve `../domain` against the wrong dir in the monorepo.)
- `deps/adaptagrams_shim.h` / `.cpp` — a flat C ABI over libcola
  (`ConstrainedFDLayout`, `setAvoidNodeOverlaps`) + libavoid (`Router`, `ShapeRef`
  obstacles, `ConnRef` centre-to-centre connectors, `displayRoute`). Opaque
  two-phase handle (run → query node boxes + variable-length routes → free) so the
  FFI needs no callbacks and no pre-sized route buffers.
- `deps/build.jl` — finds Adaptagrams via pkg-config (`libcola libavoid libvpsc`)
  or `$ADAPTAGRAMS_DIR` (a checkout's `cola/` dir), compiles
  `libadaptagrams_shim.so` (baking `-rpath` for the lib dirs), and writes
  `deps/deps.jl`. Never throws — if Adaptagrams is absent it warns and marks the
  shim unavailable, so the package still loads and `FallbackLayoutEngine` is
  unaffected.
- `src/ProjecturedAdaptagrams.jl` — `AdaptagramsEngine(; ideal_length,
  avoid_overlaps, orthogonal) <: GraphLayoutEngine` and the `layout_graph` method:
  maps vertices/edges to 0-based shim indices, `ccall`s the shim, returns the same
  `(positions::Dict{objectid→(x,y,w,h)}, routes::Dict{objectid→Vector{(x,y)}})`
  shape as `FallbackLayoutEngine`. `isavailable()` `dlopen`s the shim to confirm
  it (and its native deps) actually load before use; otherwise errors with build
  guidance.

Wired into the root `Project.toml` (`[deps]` + `[sources] = package/adaptagrams`).
**Verified end-to-end** against a system Adaptagrams install in `/usr/local`:
shim compiles clean against the real headers, `Pkg.build` succeeds, and
`layout_graph(AdaptagramsEngine(), …)` places nodes disjoint (overlap-avoiding)
with correct sizes and routes edges as ≥2-point polylines.

> **API drift:** the libcola/libvpsc/libavoid calls flagged `VERIFY` in
> `adaptagrams_shim.cpp` are the ones that have shifted spelling across
> Adaptagrams revisions; against the installed version here they compiled
> unchanged. Constraints (`GraphConstraint`) are accepted but ignored by the
> native engine in v1 (placement honours `avoid_overlaps` only) — same scope as
> `FallbackLayoutEngine`.

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

**✅ DONE (verified):** `package/domain/src/projection/primitive/GraphToGraphLayout.jl`
(`GraphGraphToGraphLayout`): recurses vertex content to measure w/h, memoizes the
engine call in a reactive cell keyed on sizes/topology, builds `GraphLayout`, and
maps `vertices[i].rest…` ↔ `vertex_layouts[i].vertex.rest…` forward/backward.
Registered `ProjecturedDomain.jl:123`.

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

**✅ DONE (verified):**
`package/domain/src/projection/primitive/GraphLayoutToGraphics.jl`
(`GraphLayoutToGraphicsCanvas`): edges drawn first as `GraphicsPolyline`
(`end_arrow=edge.directed`), then node `GraphicsRect` boxes with recursed content
canvases on top; `ChildrenIoMap`-style child iomaps; forward mapper routes
`vertex_layouts[i].vertex.content.rest…`. Registered `ProjecturedDomain.jl:124`.

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

**✅ DONE (verified):** Forward/backward mappers in Phases 5–6 descend
`graph → vertices[i] → content`; mouse click-to-select routes into node content via
`_route_click`/`_forward_to_selected` in `GraphLayoutToGraphics.jl:147-193`,
emitting a `ReplaceSelectionOperation` rooted at `vertex_layouts[i].vertex.content`.

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

**✅ DONE (verified):** `package/example/src/document/Graph.jl`
(`make_graph_document_example` — WidgetTable + JsonObject + XmlElement vertices,
directed/undirected edges) and `package/example/src/projection/Graph.jl`
(`make_graph_projection_example` — `GraphGraphToGraphLayout`+`GraphLayoutToGraphicsCanvas`
under a `NestingProjection`, default `FallbackLayoutEngine`). Registered as
`graph_example` in `package/example/src/Examples.jl:82` and exported from
`ProjecturedExample.jl:144,191`.

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

**✅ DONE (verified):** `package/test/src/projection/GraphTest.jl` (`test_graph`)
covers all listed cases: edge primitives (construct/tessellate/hit-test/arrowhead),
`FallbackLayoutEngine` (disjoint placement, route endpoints), `GraphToGraphLayout`
sizing + reactivity, `GraphLayoutToGraphics` printer (boxes/content/directed-edge
arrow), and selection descending into vertex content.

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

1. **✅ DONE** Phase 1 graphics primitives + backend renderers + hit-tests.
2. **✅ DONE** Phase 2 graph domain types.
3. **✅ DONE** Phase 3 graph-layout documents + constraints.
4. **✅ DONE** Phase 4 engine interface + `FallbackLayoutEngine` (Adaptagrams FFI can land in
   parallel / later behind the same interface).
5. **✅ DONE** Phase 5 GraphToGraphLayout (sizing + engine call).
6. **✅ DONE** Phase 6 GraphLayoutToGraphics.
7. **✅ DONE** Phase 7 read path (selection into vertex content).
8. **✅ DONE** Phases 8–9 example + tests.
9. **✅ DONE** Adaptagrams build (C shim) + `AdaptagramsEngine` — shipped as the
   separate `ProjecturedAdaptagrams` package (see Phase 4 "Engine packaging").

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
