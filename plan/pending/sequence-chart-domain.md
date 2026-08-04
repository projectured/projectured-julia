# Plan: a generic sequence chart domain (`sequencechart` slice)

A new **slice of the domain package** (`package/domain/main/sequencechart/`) providing a
generic, reusable, composable sequence chart: lanes ("axes") carrying point occurrences
("events") and piecewise-constant state ("bands"), with directed arrows between events,
a tick gutter, a pluggable timeline mapping, and horizontal or vertical flow.

It is **not** OMNeT++-specific. It is the *target* language of the projectional pipeline:
simulation-specific domains (an eventlog domain, a protocol-trace domain, a UML
interaction domain, …) sit **upstream** and print into it. Everything that requires
domain semantics — module hierarchies, expand/collapse of lanes, filtering, message
taxonomies — lives in those upstream domains; this domain only knows lanes, events,
bands, arrows, kinds, and time.

Grounding: a full read of the OMNeT++ IDE's `SequenceChart.java` (6488 lines) +
`SequenceChartFacade` + eventlog model + the userguide chapter, and of ProjecturEd's
`chart` domain, which is the architectural template this slice copies. The draft was
adversarially reviewed from four lenses (requirements, architecture compliance,
OMNeT++ expressibility, reactive/performance design); the fixes are folded in below.

## 1. Scope: what is in the domain, what is upstream, what is the editor's

The OMNeT++ sequence chart decomposes into four dispositions. This table is the
contract of the new domain — a feature listed "upstream" must be expressible by an
upstream domain *without changing this slice*; a feature listed "deferred" is an
honest future change to this slice, scoped in §8.

| Concern | Where it lives |
| --- | --- |
| Lanes, their labels, display order | **this domain** (`SequenceChartAxis`, `axis_order`) |
| Events on lanes (time, ordinal, kind, label) | **this domain** (`SequenceChartEvents` columns) |
| State along a lane (colored value strip) | **this domain** (`SequenceChartBandSeries`) |
| Arrows between events, kind-styled (solid/dashed/dotted, arrowheads, arc, "elided" zigzag marker), per-endpoint lane overrides | **this domain** (`SequenceChartArrows` + `SequenceChartArrowKind`) |
| Timeline mapping (linear time / ordinal / step / nonlinear-compressed) | **this domain** (`SequenceChartTimeline` + pure geometry) |
| Gutter: ticks, hairlines, cursor time readout, visible-range readout, zero-time shading | **this domain** |
| Horizontal vs vertical flow | **this domain** (`orientation`) |
| Zoom window, pan, follow-end, hover, in-progress drag | **presentation document** (`SequenceChartPlot`), never serialized |
| Module/actor hierarchy, expand/collapse of lanes, "open axes", prefix-merged header trees | **upstream domain** — folding is a reprint that produces a different flat lane list |
| Filtering, virtual "elided chain" arrow synthesis (FilteredEventLog's bounded BFS) | **upstream domain** — it emits arrows whose kind has `elided=true`; original event numbers go in the `ordinals` column so `:ordinal` spacing keeps its gaps |
| Message/send/reuse/method-call *naming, coloring, dash styling* | **upstream domain** — mapped onto kind tables and labels |
| Call/return bracket arrows with activation regions; transmission-duration parallelograms | **deferred** — need extra anchor columns on the arrow table, see §8 |
| Windowing gigabyte logs, lazy file loading, live *data* updates | **upstream domain** — it prints a bounded chart document; a live source reassigns column cells (the view-side "follow the end" is `follow_end` on the plot) |
| Scrolling surface, tooltips, bookmarks, per-file persistence, SVG export, log/statistics info boxes | **editor machinery / upstream chrome**, not this slice |

The OMNeT++ IDE's own `ISequenceChartStyleProvider`/`ISequenceChartLabelProvider` seam
confirms this split: everything those interfaces parameterize (colors/fonts/line styles
per lane, event, arrow kind, tick; label strings) becomes *document data* here — the kind
tables — instead of code callbacks. An upstream domain "styles" the chart by the data it
prints.

## 2. Semantic document model (`SequenceChart.jl`)

`@domain SequenceChart` (generates `SequenceChartDocument`, `SequenceChartNothing`,
`SequenceChartInsertion`, insertion traits). All structs `@document`; collections are
`CellVector`; bulk data is **whole column vectors, one reactive cell per column**,
exactly like `Chart` series columns — a column is bulk leaf data, not navigable
structure, and reassigning a column is what repaints. (All-default `@document` structs
are legal; `ChartStyle` is the precedent.)

```julia
@document struct SequenceChartAxis <: SequenceChartDocument
    label::String
    bands::CellVector = CellVector()   # SequenceChartBandSeries, usually 0 or 1
    color::Any = nothing               # lane line color; nothing = theme default
    visible::Bool = true
end

# One chart-wide event table, parallel columns. Row index = event identity.
# Rows must ascend by time (ties broken by row order) — this *is* the total order
# the step/nonlinear timeline modes walk.
@document struct SequenceChartEvents <: SequenceChartDocument
    times::Any = Float64[]     # AbstractVector{<:Real}
    axes::Any = Int[]          # index into chart.axes (identity order, not display order)
    kinds::Any = Int[]         # index into chart.event_kinds; 0/empty = default kind
    labels::Any = nothing      # optional AbstractVector{String}
    ordinals::Any = nothing    # optional; nothing = row index. Two uses: an upstream
                               # filter keeps original event numbers so :ordinal mode
                               # keeps its gaps; equal ordinals share one timeline
                               # coordinate (zero-width duplicates, e.g. an
                               # initialization event fanned out over several lanes)
end

@document struct SequenceChartArrows <: SequenceChartDocument
    sources::Any = Int[]       # event row index
    targets::Any = Int[]       # event row index
    kinds::Any = Int[]         # index into chart.arrow_kinds; 0/empty = default kind
    labels::Any = nothing      # optional AbstractVector{String}
    source_axes::Any = nothing # optional per-endpoint lane override; 0/nothing = the
    target_axes::Any = nothing # event's own axis. This is OMNeT++'s "endpoint on the
                               # send entry's context-module axis" as plain data.
end

# Piecewise-constant state along one axis: sample-and-hold, value i paints
# [times[i], times[i+1]). `events` optionally anchors edges to event rows so band
# boundaries land exactly in step/nonlinear modes (the OMNeT++
# "vector-record-eventnumbers" lesson — a raw time is ambiguous inside a
# zero-time region).
@document struct SequenceChartBandSeries <: SequenceChartDocument
    times::Any
    values::Any                # AbstractVector{<:Integer} state indices, or reals
    events::Any = nothing      # optional event row indices for precise anchoring
    states::Any = nothing      # optional Vector{String}: value -> display name
    colors::Any = nothing      # optional value -> StyleColor; nothing = palette cycle
end

@document struct SequenceChartEventKind <: SequenceChartDocument
    name::String
    symbol::Symbol = :circle   # chart marker vocabulary (marker_polygon shapes)
    color::Any = nothing
    visible::Bool = true
end

@document struct SequenceChartArrowKind <: SequenceChartDocument
    name::String
    color::Any = nothing
    line_style::Symbol = :solid    # :solid | :dashed | :dotted
    arrowhead::Bool = true
    elided::Bool = false           # draw the double-zigzag "something was filtered out" marker
    route::Symbol = :auto          # :auto (arc when same lane, else direct) | :direct | :arc
    visible::Bool = true
end

@document struct SequenceChartTimeline <: SequenceChartDocument
    mode::Symbol = :time           # :time | :ordinal | :step | :nonlinear
    nonlinear_focus::Any = nothing # nothing = auto: (t_last - t_first) / n / 10
    nonlinear_minimum::Float64 = 0.1
end

@document struct SequenceChartGutter <: SequenceChartDocument
    visible::Bool = true
    hairlines::Bool = true
    cursor_readout::Bool = true
    range_readout::Bool = true     # window start + span, shown at the gutter's end
end

@document struct SequenceChartStyle <: SequenceChartDocument
    background::Any = nothing
    axis_color::Any = nothing
    axis_label_font::Any = nothing
    label_font::Any = nothing
    gutter_background::Any = nothing
    tick_color::Any = nothing
    color_cycle::Any = default_color_cycle()   # kind/band color fallback (chart's cycle)
    event_radius::Int = 3
    arrow_width::Int = 1
    arrowhead_size::Int = 8
    arc_min_height::Int = 15
    arc_height_buckets::Int = 4        # deterministic de-overlap of same-lane arcs
    split_horizon_viewports::Int = 3   # ×viewport width before an arrow splits
    split_stub_px::Int = 80
    axis_spacing::Any = nothing        # nothing = auto (divide available cross space)
    zero_time_shading::Bool = true
    event_labels::Bool = false
    arrow_labels::Bool = true
    band_labels::Bool = true
end

@document struct SequenceChart <: SequenceChartDocument
    title::String = ""
    axes::CellVector = CellVector()
    events::Any = SequenceChartEvents()
    arrows::Any = SequenceChartArrows()
    event_kinds::CellVector = CellVector()
    arrow_kinds::CellVector = CellVector()
    axis_order::Any = nothing          # nothing = as listed; else display permutation
    orientation::Symbol = :horizontal  # :horizontal (time →, lanes stacked) | :vertical (time ↓, UML-style)
    timeline::Any = SequenceChartTimeline()
    gutter::Any = SequenceChartGutter()
    style::Any = SequenceChartStyle()
end
```

Design decisions, with rationale:

- **Events are one chart-wide table, not per-axis children.** The step/nonlinear
  timeline modes are cumulative walks over the *global* time-ordered event sequence
  (SequenceChartFacade does exactly this), and arrows anchor to events on *different*
  axes — a global row index is the natural shared identity. Per-axis views are derived
  in geometry.
- **Arrows connect events, not raw (axis, time) points.** In non-time modes a raw time
  maps to a coordinate *range* (zero-time regions), so only an event pins an endpoint
  unambiguously. This matches both OMNeT++ (cause event → consequence event) and UML
  (message ends are occurrence specifications). The optional `source_axes`/`target_axes`
  overrides cover the cases where the *lane* of an endpoint differs from the event's own
  lane (OMNeT++'s context-module endpoints; an initialization event fanned out over the
  lanes it sent to — one event row with a shared ordinal, N arrows leaving it on
  overridden lanes).
- **Kind tables reify the style-provider seam.** Rows store a small-int kind index;
  the kind document carries the visual treatment and a `visible` toggle. One boolean
  per kind covers most of OMNeT++'s `show*` flag zoo (hiding "message reuses" is
  `arrow_kinds[i].visible = false`); the rest are style/gutter booleans
  (`event_labels`, `arrow_labels`, `zero_time_shading`, `hairlines`,
  `cursor_readout`, `range_readout`), and the log/statistics info boxes are upstream
  or editor chrome, not this domain.
- **`axes` order is identity, `axis_order` is display.** Event rows index axes by
  identity, so reordering lanes is an edit to the permutation and never touches the
  event table — the same split as OMNeT++'s `axisModulePositions`. Ordering
  *algorithms* (crossing minimization) are upstream or a later geometry helper that
  proposes a permutation; the domain only stores the result.
- **Editing helpers own index consistency.** Domain functions returning compound
  operations: `insert_events`/`delete_events` remap arrow endpoint rows, band `events`
  anchors, and the plot's view anchor; `delete_axis` deletes the axis's events
  (cascading to their arrows), renumbers `events.axes` and the endpoint-override
  columns above the deleted index, and rewrites `axis_order` to a valid permutation
  over the remaining axes; `move_axis` edits only the permutation. Hand edits go
  through these (the way `move_series` on `Chart` pairs delete+insert).
- **Bounded documents.** The slice assumes the event table fits in memory (the chart
  domain's scale posture: 1M samples fine, unbounded no). Gigabyte logs are windowed
  or filtered upstream before printing into this domain.
- Times are `Real` columns read as `Float64` in geometry. OMNeT++'s BigDecimal
  precision is an upstream concern; if an eventlog domain needs exact tick labels it
  can provide label strings. (Recorded as a known limitation.)

### Reactivity on input

Every field above is a reactive cell; columns are one cell each. Two ways input drives
the chart, both free:

1. **A live producer reassigns column cells** (append = reassign `events.times` etc.);
   the geometry cell below invalidates and the picture repaints. This is how a running
   simulation (its state `@document`-shadowed for free, per the non-invasive shadow
   design) feeds a live chart. Pull-based invalidation coalesces many appends between
   frames into one recompute; a chunked/appendable column type is noted in §8 if
   profiling ever shows the O(n) reassign matters.
2. **An upstream projection prints a `SequenceChart` whose cells are `ComputedCell`s**
   over the upstream document — structural changes propagate reactively without
   dropping the editor's iomap (the reactive-composition property already relied on by
   other pipelines). Structural edits (adding an axis or kind) invalidate too:
   `CellVector` mutators reassign the reactive elements field.

## 3. Presentation document (`SequenceChartPlot.jl`)

Same split as `Chart`/`ChartPlot`: the semantic chart serializes; *looking at it* does
not. Identity is kept across reprints so the view survives data changes.

```julia
# The live view window, denominated in TIMELINE COORDINATES anchored to an event —
# not in time, and not in pixels. Inside a zero-time burst (N events at one t) the
# coordinate span is real (each gap gets ≥ the nonlinear minimum), so zooming and
# panning *within* the burst — the defining scenario of the non-time modes — stays
# representable, which a (t_min, t_max) window cannot do. The anchor row keeps the
# window stable when data is appended behind it. This is OMNeT++'s
# (origin event, fix point) design as a value.
struct SequenceChartView            # plain immutable value, not a document
    anchor::Int                     # event row the window is anchored to
    offset::Float64                 # window start, in timeline coords relative to the anchor's coordinate
    span::Float64                   # window width in timeline coordinates
end

@document struct SequenceChartPlot <: SequenceChartDocument
    chart::Any
    view::Any = nothing           # nothing = fit all events
    follow_end::Bool = false      # pin the window's end to the last event at the current span
    cross_offset::Int = 0         # scroll along the lane-stacking direction when lanes overflow
    cursor::Any = nothing         # pointer position; drives the gutter readout
    hovered::Any = nothing        # Reference to the hovered event/arrow/axis
    drag_anchor::Any = nothing    # pixel state while a rubber-band zoom or pan drags
    drag_rect::Any = nothing
end
```

Zoom and pan operate in coordinate space (where zero-time regions have real extent) and
re-derive ticks/decimation — never a pixel transform (`WidgetTransformPane` is
explicitly the wrong tool). A **timeline-mode switch** converts the old window to a time
range (with the `upper`/lower edge disambiguation) and re-anchors it in the new mode's
coordinates — reproducing OMNeT++'s mode-switch behavior, where the *time range* is the
carrier only at the switch, not the live state. A degenerate (all-one-time) window
re-anchors to the enclosing zero-time gap's coordinate span.

## 4. Pure geometry (`SequenceChartGeometry.jl`)

No cells, no document types — pure functions over plain numbers/vectors, callable
headless and memoizable by the renderer's cells (the `ChartGeometry`/`GraphLayoutEngine`
rule). The slice declares a DAG edge **`sequencechart → chart`** (covering
`ChartGeometryModule` for `AxisScale`/`to_pixel`/`to_data`, `nice_ticks`,
`format_tick`, `visible_range`, `nearest_sample`; `ChartModule` for
`default_color_cycle`; `ChartPlotToGraphicsModule` for `marker_polygon`) rather than
duplicating them. Cross-slice edges are precedented (`formula → julia`,
`dbcatalog → sql`, `tabular → json`).

The heart is the **three-stage coordinate pipeline** lifted from the facade:

```
time ──(timeline mapping, per mode)──▶ timeline coordinate ──(AxisScale over the view window)──▶ flow pixel
```

- `timeline_coordinates(times, ordinals, mode; focus, minimum) -> Vector{Float64}` —
  one cumulative pass. `:time`: `t - t₀`. `:ordinal`: `ordinal - ordinal₀` (defaults to
  row index; preserved upstream event numbers keep filtered gaps). `:step`: each
  consecutive *distinct-ordinal* pair 1 apart. `:nonlinear`: per-gap
  `Δ = c + (1 − c) · atan(Δt / focus) / (π/2)` with `c = nonlinear_minimum` — the
  bounded monotone compression that keeps microsecond bursts and long silences both
  visible (the defining insight of the OMNeT++ tool). Equal-ordinal rows share one
  coordinate in every mode. `default_nonlinear_focus(times)` = span/n/10.
- `time_to_coordinate(times, coords, t; upper) / coordinate_to_time(...)` — piecewise-
  linear between adjacent events, `upper` disambiguating zero-duration gaps. Used for
  tick labeling and for carrying the view across a mode switch (§3) — not as the live
  view state.
- `visible_event_range(coords, c_lo, c_hi)` — binary search, ±1.
- `visible_arrows(coords, sources, targets, c_lo, c_hi, horizon)` — an arrow is a
  candidate iff the interval spanned by its two endpoint coordinates **overlaps** the
  window widened by the split horizon (endpoint-in-window is not enough: an arrow may
  cross the window with both endpoints outside it, and OMNeT++ draws exactly those via
  its 3×-viewport enumeration). v1 is an O(#arrows) scan per layout recompute —
  bounded-document posture, budgeted in the scale test; a per-event incidence-list
  refinement is noted in §8.
- `flow_ticks(...)` — `:time` mode: the 1-2-5 ladder (`nice_ticks`). Other modes: ticks
  every ~100 flow px, each labeled by `honest_tick_label(t, t_neighborhood)` — round to
  the fewest digits that stays within the tick's pixel neighborhood (the "shortest
  honest decimal" algorithm), plus `tick_common_prefix(labels)` so the gutter shows the
  shared prefix once and ticks show `+suffix`.
- `zero_time_spans(times, coords, window)` — coordinate spans where time does not
  advance, for the grey shading that explains a nonlinear timeline.
- `axis_cross_positions(order, band_heights, available, spacing)` — auto spacing =
  divide available cross space (min: font height), manual override; returns per-lane
  center + band strip extents.
- `arc_geometry(c1, c2, spacing; min_height, buckets)` — same-lane arc: half-ellipse
  approximated by a cubic bezier; height picked deterministically from
  `(target_row - source_row) % buckets` so overlapping self-arrows de-overlap
  (OMNeT++'s pseudo-random bucket trick).
- `split_arrow(c1, c2, horizon, stub)` — when endpoints are farther apart than the
  horizon, replace the far half with a fixed-width stub; returns the two half-geometries
  (the solid anchored end and the dotted continuation end).
- `decimate_events(coords, axes, order, px)` — per-lane per-pixel run collapse (the
  per-axis "last drawn x" dedup): output bounded by lane count × flow pixels.
- `arrow_coverage_dedup(...)` — the VLineBuffer idea generalized: for candidate arrows
  whose flow extent rounds to ≤ 1 px (the dominant population when zoomed out), track
  per-flow-pixel covered cross-intervals and drop arrows that add no new pixels — a
  true pixel bound for that population. Wider arrows draw as-is; the honest total bound
  is `min(#candidate arrows, coverage bound + #wide candidates)`, and the scale test
  asserts it against adversarially spread data, not just clustered bursts.
- `decimate_bands(...)`, `band_visible_range(...)` — sample-and-hold intervals clipped
  to the window, sub-pixel intervals merged.
- **Orientation is a geometry-level frame, not renderer branching**: all of the above
  work in abstract `(flow, cross)` coordinates; a tiny `FlowFrame(orientation, rect)`
  maps `(flow, cross) -> (x, y)` (a coordinate swap — safe because backends only do
  axis-aligned transforms). The renderer is written once against the frame.
  Horizontal: flow → right, lanes stacked top-to-bottom, gutters top+bottom, lane
  labels in a left strip. Vertical: flow → down, lanes side by side, gutters
  left+right, lane labels in a top header strip — which makes the vertical form read
  exactly like a UML sequence diagram.

Tests: `test_sequencechart_geometry()` — pure, headless, includes property checks
(monotonicity of every mode, equal-ordinal coordinate sharing, mode-switch window
re-anchoring incl. the degenerate all-one-time window, honest-label bounds,
arrow-candidacy interval overlap, coverage-dedup bound, split/arc invariants).

## 5. Projections

### `SequenceChartToSequenceChartPlot.jl` — thin stage 1

Copy of `ChartToChartPlot`: stateless projection, `@iomap {projection, input, output}`,
builds the plot once with explicit cells (selection as the knot-tied `ComputedCell`
forward-map), accepts `Union{SequenceChart, SequenceChartNothing, SequenceChartInsertion}`
roots. Mappers are the School A one-step peel:
`anything… ↔ chart.anything…` with the chart step's node type from
`get_reference_node_type(iomap.input)`.

### `SequenceChartPlotToGraphics.jl` — the renderer

Hand-written `print_document` on a **plain struct** `SequenceChartPlotToGraphicsCanvas`
holding `measure::Function` + fallback `width`/`height` (not `@projection` — a
`Function` in a reactive field becomes a thunk). `@projection_template` does not apply:
it targets syntax-backed domains; canvas renderers follow `ChartPlotToGraphics`.

Reactive structure — **three-level cells**. Two deliberate improvements over the chart:
the O(n) timeline pass is isolated from layout, and the per-pointer-move values
(`hovered`, `selection`, `cursor`) are kept **out of the layout cell** entirely, so
pointer movement re-renders only the overlay, never re-runs decimation (the chart pays
a full `_layout` per hover change; its own `cursor` handling shows the cheap pattern).

1. `timeline = ComputedCell` reading *only* `events.times`/`events.ordinals` +
   `chart.timeline` fields → the cumulative coordinate array. View/hover/size changes
   do **not** re-run it.
2. `geometry = ComputedCell` reading `timeline[]`, the other columns, axes, kinds,
   `view`/`follow_end`, and `ctx.available_width/height` → the frame layout as a
   NamedTuple: `FlowFrame`, `AxisScale` over the view window, lane cross positions,
   visible event range, candidate arrows, decimated per-lane event runs, arrow
   geometries (direct / arc / split, endpoints pulled off marks by `event_radius`,
   endpoint lanes honoring the override columns), band intervals, ticks + measured
   labels + common prefix, label placements, hit rects. Per-layout memo `Dict`s live
   inside the NamedTuple (the chart's `point_cache` pattern — the cache's lifetime *is*
   the layout's). **Not** read here: `hovered`, `selection`, `cursor`, `cross_offset`.
3. `elements = ComputedCellVector` over `geometry[]` **plus** `hovered`/`selection`/
   `cursor` for the overlay (halos, re-stroked hovered arrow, cursor readout) —
   pointer-move cost is bounded by the overlay. `cross_offset` is applied as the
   body viewport's translation (translate is exactly what backends honour), so a
   cross-scroll tick repaints without re-running any layout; `read_intent` offsets
   pointer coordinates by it before hit-testing. Canvas `w/h` are `ComputedCell`s over
   `_canvas_size` so a parent resize reflows the same canvas object.

The iomap carries the shared cells (`@iomap {projection, input, output,
timeline::Cell, geometry::Cell}`) so printer and reader use one laid-out frame.

Element composition (all existing primitives — **no new backend work needed**):

| Chart part | Primitive |
| --- | --- |
| Lane line | `GraphicsLine` (solid; per-axis color) |
| Band interval | `GraphicsRect` + `GraphicsText` value label when it fits |
| Event mark | `GraphicsCircle` / `marker_polygon` shapes per kind |
| Direct arrow | 2-point `GraphicsPolyline` with `end_arrow`, kind dash |
| Same-lane arc | `GraphicsSpline :bezier` with `end_arrow`, kind dash |
| Split arrow | solid half `GraphicsPolyline` + dotted stub; continuation head hollow (composed from two short lines) |
| Elided marker | short zigzag `GraphicsPolyline` perpendicular at the midpoint |
| Event/arrow label | `GraphicsText` at the midpoint with a fixed offset (collision avoidance deferred, §8) |
| Gutter | `GraphicsRect` strips outside the viewport + tick `GraphicsText` + hairline `GraphicsLine dash` through the body + cursor/range readout texts |
| Zero-time span | translucent `GraphicsRect` behind the lanes |
| Selection/hover | halo ring `GraphicsCircle` (transparent fill) / re-stroked thick arrow — overlay elements |

The scrolling body sits inside a `GraphicsViewport`; gutters, lane-label strip and
title are drawn outside it in the outer canvas (the chart's sticky-frame idiom).
**Tolerance rule** (chart's family-mismatch precedent): an unknown kind index, an
out-of-range endpoint row, or a not-yet-implemented kind feature renders as a
diagnostic skip, never a crash — this also lets the registered example carry content
for features that land in later phases.
Known primitive limitations, accepted for v1: no rotated text (all labels horizontal —
fine in both orientations; OMNeT++'s rotated method names have no counterpart), arcs
are bezier approximations, dash-dot patterns unavailable.

**Scale posture**: element count bounded by
`min(#candidate arrows, coverage bound + #wide candidates)` for arrows plus
lane × pixel bounds for events/bands, enforced by `test_sequencechart_scale()`
mirroring `test_chart_scale` (e.g. 200k events / 100k arrows / 10 lanes → asserted
element bounds with both clustered and adversarially spread arrows, timing budget for
the O(#arrows) candidacy scan, zoomed-in exactness).

### References, selection, reader

- `SequenceChartRowReferenceStep.jl` — one `:structural` step `row(k)` addressing a row
  of an opaque columnar table (model: `ChartSampleReferenceStep`, own `Val(:row)` DSL
  registration — no existing `Val` vocabulary collides). Evaluation lives in the
  domain: an event row evaluates to `(time, axis, kind, label)`, an arrow row to
  `(source, target, kind, label)`, a band row to `(t_lo, t_hi, value)`.
- Selection vocabulary: whole chart, title, an axis (`::SequenceChart.axes[i]`), an
  event (`::SequenceChart.events.row(k)`), an arrow (`::SequenceChart.arrows.row(k)`),
  a band sample (`::SequenceChart.axes[i].bands[j].row(k)`). Kind selection is
  deferred with the kind legend that would make it reachable (§8); until then kind
  `visible` is edited through the inspector or by the upstream producer.
- Stage-2 mappers **decline** (chart precedent): a chart part is not a cursor position;
  selection is expressed by what the reader selects and the overlay highlights.
- `read_intent` (reader): click hit-tests against the memoized geometry with OMNeT++'s
  priority order — event > arrow > band > lane label > title; hover sets `hovered` +
  the gutter cursor readout; wheel zooms the coordinate window about the cursor,
  Shift+wheel / drag pans flow, wheel over the lane-label strip scrolls
  `cross_offset`; rubber-band drag zooms to the dragged flow range (min 6 px, the
  chart's threshold); double-click resets the view; `End` with nothing selected
  toggles `follow_end`; Escape/MouseLeave cancels drags. Pass-through rule respected:
  only `Operation`s returned, raw gestures declined.
- `@gestures SequenceChart` (document-level, keyboard):
  - part stepping and Alt-tree walk copied from `Chart` (parts: title, each axis, the
    event table, the arrow table);
  - with an event selected: `Left`/`Right` = previous/next event in time order,
    `Shift+Left/Right` = previous/next **on the same lane**, `Ctrl+Left` = follow an
    incoming arrow to its source (cause), `Ctrl+Right` = follow the first outgoing
    arrow (consequence), `Home`/`End` = first/last event — the "chart as traversable
    causality graph" feature, which is pure arrow-table lookup here;
  - `Ctrl+Shift+Up/Down` on a selected axis edits the `axis_order` permutation.

## 6. Registration, examples, docs, tests (the slice checklist)

- **Includes** in `package/domain/main/ProjecturedDomain.jl`, DAG position after the
  whole `chart/` slice (edge `sequencechart → chart`): geometry → reference step →
  `SequenceChart.jl` → `SequenceChartPlot.jl` in the document group **after chart's
  document includes**; the two projection files **after chart's two projection
  includes** (the renderer imports `ChartPlotToGraphicsModule.marker_polygon`, so
  "next to" is not enough — the layering guard checks topological include order).
  Add the slice + edge to `package/domain/doc/architecture.md` (slice list and DAG
  section).
- **Examples** (`package/domain/example/`): create `document/SequenceChart.jl` —
  `make_sequencechart_document_example()`: a deterministic client/server/database
  request flow that (once all phases land) exercises every feature: three lanes, a
  state band on the server lane, request/response arrows, a same-lane timer arc, a
  dotted "reuse"-style kind, an elided arrow, an endpoint-override arrow, nonlinear
  timeline. Content is added phase by phase; the renderer's tolerance rule keeps the
  sweeps green in between. Also `make_sequencechart_vertical_document_example()`
  (same flow, `:vertical`) and `make_sequencechart_inspector_document_example()`
  (`WidgetSplitPane` of chart + selected-element property view) — registered as
  **full `Example`s** like `chart_line_example`/`chart_inspector_example`; the
  atomic-document catalog does not apply to canvas-only domains (chart and graph are
  absent from it too). Create `projection/SequenceChart.jl` —
  `ChainingProjection(SequenceChartToSequenceChartPlot(), SequenceChartPlotToGraphicsCanvas(...))`
  plus the one `NaturalToGraphics(...; extra=[SequenceChart => pipeline])` dispatch
  entry that makes it embeddable in any recursing document and the workbench.
  Register: both `include` lines **and** the explicit `export` lines in
  `ProjecturedDomainExample.jl` (that file does not re-export by reflection);
  `const sequencechart_example = Example(...)` + `domain_examples` in `Examples.jl`;
  the umbrella re-export **and** the umbrella `examples` vector in
  `package/projectured/example/Examples.jl`; a
  `"package/domain/doc/sequencechart.md" => "sequencechart"` entry in
  `_DOMAIN_GUIDE_EXAMPLE` so the guide embeds the screenshot.
- **Docs**: `package/domain/doc/sequencechart.md` — overview, types table,
  content-vs-presentation note, the upstream-domain contract (the §1 table), examples.
- **Tests** (`package/domain/test/`): `projection/SequenceChartGeometryTest.jl`
  (`test_sequencechart_geometry()`), `projection/SequenceChartTest.jl`
  (`test_sequencechart()`: frame composition, both orientations, all arrow routes,
  endpoint overrides, reactivity — column reassign repaints, view survives data
  change, hover does not re-run layout —, selection round-trips through both stages,
  click/hover/zoom intents, causality navigation; `test_sequencechart_scale()`).
  Register in `ProjecturedDomainTest.jl` / `test_domain()`. Per-example sweeps come
  free from example registration (`test_printer(sequencechart_example)` first, then
  the loops). Verify live in the editor's real order (print → select → click → type),
  not only headless probes.

## 7. Implementation phases

Work in a dedicated worktree; one commit per phase; check boxes and record decisions
here as they land.

- [x] **Phase 0 — documents + geometry. DONE.** Slice folder, `@domain`, all document
  structs and constructors, editing helpers (`insert_events`/`delete_events`/
  `delete_axis`/`move_axis` with the full index fix-up story of §2);
  `SequenceChartGeometry.jl` with timeline modes (incl. ordinals), time↔coordinate
  conversion, ticks (incl. honest labels + common prefix), zero-time spans, axis
  positions, arrow candidacy, arc/split, event/band decimation, coverage dedup;
  `test_sequencechart_geometry()` green (111 assertions), layering guard green (6/6).

  Decisions made while implementing:
  - `band_intervals` takes **both** the band's sample times and the *event* times:
    converting a band timestamp into a coordinate needs the event timeline, since
    the band's own samples say nothing about where the axis was stretched. The
    first draft passed only the band times and silently placed unanchored band
    edges on the wrong coordinate — caught by the geometry tests.
  - `arc_height` lives in geometry beside `arc_geometry` (the plan named only the
    latter); its bucket cycling is keyed on the row delta so repaints stay stable.
  - The column helpers re-narrow to a concrete element type, because the renderer
    reads columns a row at a time in inner loops and an `Any` column would box
    every value.
  - `axis_display_order` ignores a stale permutation (wrong length, or a repeated
    lane) rather than obeying it, so a half-finished edit degrades to the listed
    order instead of dropping lanes off the picture.
- [x] **Phase 1 — pipeline, horizontal. DONE (and more).** `SequenceChartPlot`,
  stage-1 projection, renderer, three-level cell structure, tolerance rule; the
  three examples registered end to end (both example packages, both `Examples.jl`,
  the umbrella vector and the guide-screenshot map); `test_printer` green on all
  three (888/821/786), geometry and layering still green.

  **The renderer landed further than the phase asked**, because the geometry was
  already there and splitting the drawing code would have been artificial: arcs,
  split arrows, the elided zigzag, state bands and the `:vertical` orientation
  all render now. Phases 3 and 4 keep only what is genuinely left — selection of
  those parts, the scale suite, and the guide.

  Decisions made while implementing:
  - **The body frame is local, not absolute.** Body elements are drawn inside a
    `GraphicsViewport` at `(body_x, body_y)`, which adds that origin back, so
    computing them in absolute coordinates offsets everything twice. Caught by
    rendering an image: lane labels sat ~45 px above their own lines. The frame
    is now `FlowFrame(orientation, 0, 0, body_w, body_h)` and the chrome outside
    the viewport adds the origin itself.
  - `axis_cross_positions` divides the room by the number of **gaps**, not of
    lanes; dividing by the lane count leaves a whole lane's worth of space unused
    at the far end (visible as an empty strip below the last lane).
  - Tick labels are drawn in **both** gutters, as OMNeT++ does: following an
    arrow across the chart should not mean travelling back to one edge to find
    out when it happened.
  - Arrow labels are clamped into the body. An arrow can sit against an edge
    while its label does not fit there, and the viewport would otherwise cut the
    text in half.
  - `GraphicsSpline`/`GraphicsPolyline` take their styling by **keyword**; the
    positional forms in the first draft threw a `MethodError` that only the
    printer test surfaced, since nothing in the smoke test drew an arc.
  - `SequenceChartPlot` must import `Reference` — the `@document` macro's
    injected `selection` field names it at the call site.
- [ ] **Phase 2 — selection + reader.** `SequenceChartRowReferenceStep`, part/row
  references, stage-1 mappers, hit-testing, click/hover/zoom/pan/rubber-band/
  follow-end reader, cursor + range readouts, event/arrow label rendering,
  `@gestures` navigation incl. cause/consequence; `test_reader` /
  `test_position_navigation` / `test_repl` for the example; live-editor verification.
- [ ] **Phase 3 — full arrow vocabulary + vertical.** Same-lane arcs, split arrows,
  elided zigzag marker, endpoint-override lanes, kind visibility; extend the example
  with this content; `FlowFrame`-driven `:vertical` orientation + vertical example;
  zero-time shading.
- [ ] **Phase 4 — bands + scale + doc.** `SequenceChartBandSeries` rendering with
  event-anchored edges and value labels, band selection; extend the example with the
  band; inspector example; `test_sequencechart_scale()`;
  `package/domain/doc/sequencechart.md`; move this plan to `plan/done/`.

## 8. Deferred / future work (recorded, deliberately out of v1)

- **Upstream domains** that print into this one: an OMNeT++ eventlog domain (module
  tree with open-set → flat axes; send/reuse/call → arrow kinds; filtering → elided
  arrows + preserved `ordinals`; `.vec` state vectors → bands; windowing huge logs)
  and a UML-interaction flavor. Each is its own plan.
- Event *extent* (an event spanning a coordinate range because its sub-entries occupy
  ordinal slots — OMNeT++'s `separateEventLogEntries`) and arrows anchoring at
  sub-entry positions.
- Call/return "bracket" arrows with activation regions, and transmission-duration
  parallelograms. Honestly scoped: both need **additional anchor columns** on the
  arrow table (a second event pair / duration extents at each end), not merely new
  `route` values.
- A kind legend (reusing chart's `legend_layout`/`anchor_offset`) giving kinds a
  rendered, hit-testable surface — which is what makes kind *selection* and
  click-to-toggle visibility reachable interactively.
- Time-point selection and a time-difference overlay between selected items.
- Arrow-label collision avoidance (candidate-row scoring with a placement cache);
  v1 places labels at the midpoint with a fixed offset.
- Per-event arrow incidence lists (plus a long-arrow index) if the O(#arrows)
  candidacy scan ever shows up in profiles; likewise chunked/appendable columns for
  live feeds.
- Crossing-minimizing axis ordering as a geometry helper proposing an `axis_order`.
- Rotated text (needs a `GraphicsText` angle + backend support), true arc primitives,
  dash-dot patterns.
