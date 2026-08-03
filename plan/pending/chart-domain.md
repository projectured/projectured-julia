# Chart domain — native OMNeT++-style charts as a ProjecturEd domain

Re-implement the native (non-matplotlib) charts of the OMNeT++ IDE — **bar, line,
histogram, and scatter charts** — as a new first-class domain slice in
projectured-julia. Charts are ordinary documents rendered by a bidirectional
projection straight to `Graphics` primitives: highly customizable (every visual
property is a document field), interactive (zoom, pan, hover, legend toggling,
selection, reordering), scalable (bounded rendering cost independent of dataset
size, folding the graphics when too much data is visible), and reactive
(whole-chunk granularity — replacing a data column repaints the chart).

**Independence requirement:** the chart domain must not depend on omnetpp-julia or
inet-julia. Data enters as plain Julia column vectors (any `AbstractVector{<:Real}`,
so DataFrame columns work directly without a DataFrames dependency). Histogram
field naming follows omnetpp-julia's vocabulary (`binedges`/`binvalues`/
`underflows`/`overflows`) but uses the standard n+1-edges / n-values shape; a
future omnetpp-julia adapter is a small reshaping (omnetpp's `StatisticItem`
stores same-length edge/value arrays with under/overflow as the first/last
elements — the adapter peels those out and synthesizes the top edge). That
adapter is out of scope here.

## Requirements

- [ ] Four chart types: line, bar, histogram, scatter — each a real document type
      rendering natively from `Graphics` primitives (no plotting library, no raster).
- [ ] Highly customizable: title, axes (range/log/grid/labels), legend
      (position/anchor/border/visibility), per-series style (color, line style/width,
      draw style, markers), series ordering, style cycles — all as document fields,
      editable projectionally with a working edit surface (not just selectable).
- [ ] Interactive: wheel/rubber-band/keyboard zoom, pan, zoom-to-fit, per-axis zoom,
      hover crosshair with value readout, legend click to hide/show series,
      click-to-select chart parts and series, series reordering.
- [ ] Scalable: rendering cost bounded by *pixels*, not points — binary-search
      viewport clipping + per-pixel min/max decimation for lines; density folding for
      large scatter sets; bin folding for dense bars/histograms; label decimation
      for dense category axes.
- [ ] Reactive: replacing a series' data column (one cell write) repaints the chart;
      stable output-object identity so only computed geometry cells re-derive.
- [ ] Registered as a full domain slice: examples, tests, docs, layering guard clean.

## Where the code goes

New slice `package/domain/main/chart/` joining the domain package's source-slice
layer; its cross-slice edges (none planned) must keep the slice DAG acyclic
(statically verified by the layering guard). No sealed files are touched — the
sealed inventory covers only `package/kernel/main/`, and everything the domain
extends (operations, reference steps, gestures) is an open seam
(`PointReferenceStep` in the visual package is the precedent that new reference
steps need no kernel edit).

Five files, mirroring the graph slice's five-file shape
(`package/domain/main/graph/`):

```
chart/Chart.jl               module ChartModule            — semantic documents ONLY (data, style,
                                                             axes, legend — pure content, serializable)
chart/ChartPlot.jl           module ChartPlotModule        — presentation-side plot-state document
                                                             (view window, hover, drag — projection
                                                             output, never serialized)
chart/ChartGeometry.jl       module ChartGeometryModule    — PURE functions: scales, nice ticks,
                                                             data↔pixel mapping, decimation, binning,
                                                             folding. No cells, no deps.
chart/ChartToChartPlot.jl    module ChartToChartPlotModule — projection stage 1: Chart → ChartPlot
                                                             (thin: stable plot-state wrapper,
                                                             School-A reference peeling)
chart/ChartPlotToGraphics.jl module ChartPlotToGraphicsModule — projection stage 2: ChartPlot →
                                                             GraphicsCanvas (all rendering) + the
                                                             interaction reader
```

Five `include(...)` lines in `package/domain/main/ProjecturedDomain.jl`,
positioned topologically (document/geometry files with the other document
includes — as `graph/GraphLayoutEngine.jl` is — projections with the projection
includes); `test_domain_layering()` statically enforces this.

The pure-function geometry module follows the `GraphLayoutEngine` precedent: keep
algorithms cell-free so they are unit-testable headless and memoizable by callers.
No third-party dependency anywhere (consistent with every existing domain; if a
heavy numeric need ever appears, it goes in a separate opt-in package like
`package/adaptagrams/`).

## Design decisions

### D1 — Graphics-direct, not via Syntax

Charts render straight to `GraphicsCanvas` like the graph slice, not through the
Syntax/Text pipeline. Chart visuals (axes, plot area, data geometry) do not map
onto a text tree, and "native" scalable rendering needs direct control of the
element list. Consequence accepted: no free text-caret machinery; selection and
gestures are hand-written in the projection (see D8 for the known risk).

### D2 — One `Chart` root; series-typed content; two axis models

There is one root document type `Chart` (title, series list, axes, legend, style)
and per-series document types. This differs deliberately from OMNeT++'s three
widget classes (`LinePlot`/`BarPlot`/`HistogramPlot`, where scatter is a LinePlot
configuration): in a projectional editor the series *list* is the natural unit of
composition and editing, and scatter is promoted to a first-class series type as
requested.

- **XY family** (numeric x-axis): `ChartLineSeries`, `ChartScatterSeries`,
  `ChartHistogramSeries` — may be mixed on one chart.
- **Category family** (categorical x-axis): `ChartBarSeries` — a chart whose
  x_axis is a `ChartCategoryAxis` holds only bar series.

The printer validates the family/axis combination and renders a diagnostic
placeholder for mismatches rather than erroring (asserted in `test_chart()`).

The insertion kit comes from `@domain Chart` (one line, as in `json/Json.jl` —
generates the `ChartDocument` abstract root, `ChartNothing`, `ChartInsertion`
and the insertion traits), per AR-DOMAIN-OWNS-EDITS. The type-to-replace
completion UX is wired through the Syntax pipeline and will not light up in the
graphics-direct projection; the chart printer renders `ChartNothing`/
`ChartInsertion` as an empty-chart placeholder instead. (Graph hand-rolls a bare
`GraphInsertion`; the macro form is preferred — if it turns out to drag
syntax-side requirements into the slice, fall back to graph's hand-rolled shape
and record why here.)

### D3 — Bulk data: one plain vector per column, one cell each

A series' data is stored as whole column vectors (`x::Any # AbstractVector{<:Real}`,
`y::Any`) — **one cell per column, zero per-point cells**. This is a deliberate,
named exception to AR-FINEST-GRANULARITY (which prescribes `CellVector` for
finite indexed collections): bulk numeric leaf data follows the
`GraphicsPolyline.points` precedent and the recorded analysis in
`plan/pending/cheap-reactive-cells.md` (reactive CellVector at 1M elements
≈ 88 B/elem and 47 ms to build; its conclusion: window over plain stores rather
than make million-element reactive collections). The shipped precedents
(omnetpp-julia's `PlotSeries.x/.y`, `VectorResult.samples`) store whole vectors
in single cells for the same reason. Reactive granularity is the whole column:
reassigning it invalidates the chart's geometry cells — exactly the "not
necessarily fine-grained" reactivity asked for.

DataFrame interop for free: `df.time` is an `AbstractVector`, so
`ChartLineSeries("rtt", df.time, df.value)` works with no DataFrames dependency.

Rejected: per-point `@document` nodes (cost, no navigational payoff — same
rationale recorded in omnetpp-julia's vector-result plan); a DataFrames/Tables
dependency in domain/main (no existing domain has any third-party dep).

### D4 — Two-stage pipeline; view state lives on the presentation document

The pipeline is `Chart → ChartPlot → GraphicsCanvas`, composed as a
`ChainingProjection` exactly like graph's
`GraphToGraphLayout ∘ GraphLayoutToGraphics`:

- **`Chart` stays pure semantic content** (AR-WIDGETS-ARE-PRESENTATION: transient
  UI state is not document content). It serializes cleanly.
- **`ChartPlot`** is a presentation-side document produced by stage 1 — a stable
  wrapper holding the chart (by identity) plus all transient interaction state:
  `view`, `cursor`, `hovered`, `drag_anchor`, `drag_rect`. As projection output
  it is excluded from serialization *by construction* (AR-PERSISTENCE-BY-VALUE),
  the same way `GraphLayout` holds geometry outside the semantic `GraphGraph`
  and `SyntaxNode.collapsed` lives on the projected syntax tree. Stage 1's
  printer preserves the `ChartPlot`'s identity across recomputes so the state
  survives reprints.

Zoom/pan state is `view::Any = nothing` where `nothing` = auto-fit and otherwise
a plain immutable `ChartView(x_min, x_max, y_min, y_max)` in **data
coordinates**. For category charts, view-x is a continuous range over category
*index* space (1..n): `pixel_to_data` maps through index positions and per-axis
x-zoom narrows the visible index range.

Rejected: reusing `WidgetTransformPane` / `GraphicsViewport.transform`
pixel-space affine zoom. A chart zoom is not a picture zoom: ticks, gridlines,
decimation and label formatting must all re-derive from the visible data window
(zooming in must reveal *more* detail, not bigger pixels). The plot area still
uses a `GraphicsViewport` — but only for clipping; the data→pixel mapping is
computed by `ChartGeometry` from `view` + plot rect.

### D5 — Scalability: decimate to pixels, fold when overplotted

Ported from the OMNeT++ native plotters (`LinePlotter`/`LinearLinePlotter`) plus
folding steps for scatter and category labels:

1. **Visible-range clipping**: line series columns sorted by x get
   `searchsorted`-based index-range extraction for the current view window
   (O(log n + visible)). A constructor-time `sorted::Bool` flag records whether x
   is ascending; unsorted data falls back to a full scan (still decimated).
2. **Per-pixel-column min/max decimation** (lines, pins, steps): consecutive
   samples mapping to the same pixel column collapse to one vertical
   min/max segment — *exact* (pixel-identical), not statistical; output is
   ≤ ~4 points per pixel column, so a `GraphicsPolyline` never exceeds a few
   thousand points regardless of dataset size.
3. **Marker suppression**: symbols draw only when visible point count is under
   `ChartStyle.marker_limit` (VectorPlot.jl precedent), else at decimated
   positions with per-pixel dedup.
4. **Scatter folding**: above `ChartStyle.scatter_fold_threshold` visible points,
   fold to a density grid — the geometry layer bins visible points into an s×s
   pixel grid and the printer draws one alpha-scaled `GraphicsRect` per occupied
   bin instead of thousands of circles. This is the "fold the graphics when too
   much data" requirement.
5. **Bar/bin folding**: when bar/bin pixel width falls below
   `ChartStyle.bin_fold_px` (~2px), adjacent bins/bars fold into min/max envelope
   rectangles.
6. **Category-label decimation**: a dense `ChartCategoryAxis` renders every k-th
   label, k derived from measured label width vs per-category pixel width
   (matching the bar-fold threshold) — a 10k-category bar chart draws a bounded
   number of `GraphicsText` elements, not 10k.

All folding lives in `ChartGeometry` as pure functions from
(columns, view, plot-rect-size) → bounded geometry, called from computed cells.

Hit-testing cost: hover/click never search raw columns linearly. Sorted series
use `searchsorted`; scatter (generally unsorted) snaps against the
already-bounded *rendered* geometry (decimated points or density bins), so the
search space is O(pixels) by construction. If per-sample precision on huge
unsorted columns is ever needed, add a cached sort-permutation index as a
`ComputedCell` over the column — noted, not scheduled. (`hit_element_at` has no
spatial index — the discipline is to never create huge element lists in the
first place, and every overlay element added later must follow the same rule.)

Deferred (not needed once geometry is pixel-bounded): draw-time budgets, and
bitmap-caching a rendered subtree — `GraphicsCanvasToGraphicsImage`
(`GraphicsCaching.jl`) is a real, wired-in identity-stable caching wrapper, but
its actual rasterization is not implemented yet (checkerboard placeholder), and
whole-canvas bitmaps don't compose with per-series reactive decimation anyway.

### D6 — Reactivity shape: stable identity, computed geometry

The printers follow the printer-locality contract: stable output documents
(`ChartPlot`, the `GraphicsCanvas`) whose element cells are `ComputedCell`s
deriving from (series columns, view, style, size). Replacing a column → the
polyline's points cell recomputes lazily on next read; the projection is not
re-run and output identity is preserved. The editor re-reads cells every frame,
and cell propagation has no equality check — if profiling shows decimation being
recomputed on unrelated writes, adopt the content-hash-gated
cache-inside-a-ComputedCell pattern from omnetpp-julia's
`OmnetppLegacyPlot._raster_key` (note it in ChartGeometry now, wire only if
needed).

Gotcha guarded: **no bare `Function` in any `@document`/`@projection` field**
(auto-wrap turns it into a called thunk — AR-NO-NESTED-CELL; the
`cell-computed-marker` migration is not finished). Formatters/predicates are
represented as data (Symbols/format specs); a genuine callable field must be
spelled `Cell(f; as_value=true)` (precedent: `ObjectToSyntax.jl`'s `filter`) or
`ComputedCell(f)` when a thunk is really intended.

### D7 — Interaction: gestures → operations on document fields

All interaction state is document fields written via operations (projections hold
no mutable state). **No new view operation type**: every view/hover/drag write is
a self-contained `ReplaceReferencedValueOperation(chart_plot, field, value)` —
the exact mechanism `WidgetTransformPane` uses for zoom (AR-PREFER-REPLACE-VALUE;
zero registration burden, well-defined inverse). Multi-field transitions
(rubber-band commit = set `view` + clear `drag_*`) compose as a
`CompoundOperation` of single-field writes. Content edits (series visibility,
reordering, property values) target the *semantic* documents; the domain's
structural operations (insert/delete/move series — from the `@domain` kit plus a
list-move helper) carry references and therefore get `reroot_operation` methods
AND default-`read_intent` registration (both sides of the invariant —
AR-REGISTER-NEW-OPERATION; an operation missing from either is silently
swallowed).

| Gesture | Effect |
|---|---|
| wheel over plot | zoom both axes about cursor (factor 1.1^notches) |
| wheel over x/y axis strip | zoom that axis only |
| Shift+wheel | pan (horizontal / vertical) |
| drag in plot | rubber-band zoom: MouseDown anchors, MouseMove updates transient `drag_rect`, MouseUp commits the view write (mirror the split-pane drag lifecycle — no rubber-band precedent exists, this is new; test the cancel path: Escape/MouseLeave mid-drag) |
| Shift+drag | pan |
| double-click / `0` | zoom to fit (view := nothing) |
| arrows, `+`/`-` | pan / zoom via `@gestures` — plot-rect-free data-space math (the handler may call `ChartGeometry.auto_range` to materialize `view === nothing` first) |
| MouseMove | update transient `cursor` field (data coords); printer draws dashed crosshair + nearest-point snap (against bounded rendered geometry, D5) + value readout box |
| click legend item | toggle that series' `visible` (semantic content edit) |
| hover legend item | transient `hovered` reference; printer veils other series |
| click series / axis / title / legend | `ReplaceSelectionOperation` selecting that document (whole-element selection, empty-path convention) |
| Alt+Up / Alt+Down on selected series | move the series within `Chart.series` (list-move operation) — delivers the "ordering" requirement with the same gesture vocabulary as table row moves |

Decisions on the two boolean-state questions: series `visible` is **content**
(persisted, like OMNeT++'s `Line.Display` property); `hovered`, `cursor`,
`drag_*` are **transient, on `ChartPlot`** (reference-valued `hovered` copies
the `WidgetTable.hovered::Union{Nothing,Reference}` pattern). Hover value
readout is drawn in-canvas in v1 (a positioned box in the overlay elements) —
the window-popup tooltip route (`TooltipDecorator`/`OpenWindowOperation`) is
noted as the upgrade path if in-canvas proves limiting.

Point-level selection (a reference addressing sample *i* inside a column that is
not itself a document) is deferred to Phase 7 — v1 selects at series/part
granularity, hover reads out point values.

### D8 — Selection mapping: budget for the introduced-token gap

Nearly every rendered element (axes, ticks, gridlines, legend chrome) is
projection-introduced. The graph slice — same architecture — is `@test_broken` in
the umbrella reader/repl/tree-nav sweeps for exactly this ("under-typed
@reference" on projection-introduced carets). The mitigation pattern is known
(introduced-token caret round-trip: `ProjectionReference` handling in the forward
map, backward map, and tree-navigate — the fix that took julia-domain nav from
2 states to 69), and chart references must type every step (`::CellVector` before
index, node type before field). Target: printer/click-roundtrip/selection tests
green; if reader/repl sweep gaps remain they get explicit `@test_broken` markers
with the graph-style root-cause comment, never silent failures.

### D9 — Customization surface (OMNeT++ parity map)

Every OMNeT++ `PlotProperty` maps to a typed document field (no string-keyed
property bag — projectional editing is the property UI). The working edit
surface is **`ObjectToWidget`** (the repo's editable inspector — its
`read_intent` maps field edits back via `ReplaceReferencedValueOperation`;
`ObjectToSyntax` is print-only and would need a reader written for it): P6
ships a split pane of chart + inspector with a field-edit round-trip test.
Coverage summary:

| OMNeT++ property group | Chart domain home |
|---|---|
| Plot.Title(.Font/.Color) | `Chart.title`, `ChartStyle.title_font/title_color` |
| X/Y.Axis.Title/Min/Max/Log, Labels.Show, Title.Show | `ChartAxis` fields (`nothing` min/max = auto) |
| Axes.Grid (None/Major/All), GridColor, background/insets colors | `ChartAxis.grid`, `ChartStyle` |
| Legend.Display/Border/Font/Position/Anchoring | `ChartLegend` (5 positions × 8 anchors, per OMNeT++) |
| Line.DrawStyle (None/Linear/Pins/StepsPost/Pre/Mid) | `ChartLineSeries.draw_style::Symbol` |
| Line.Style/Width/Color, Symbols.Type/Size | `ChartLineSeries` fields; `color = nothing` ⇒ style-cycle |
| Bar.Placement (Aligned/Overlap/InFront/Stacked), Baseline(+Color) | `Chart.bar_placement/bar_baseline/bar_baseline_color` |
| Hist.Bar (Solid/Outline), Cumulative, Density, ShowOverflowCell | `ChartHistogramSeries` fields |
| X.Label.RotateBy/Wrap (category axis) | `ChartCategoryAxis` — **rotation deferred**: SDL/PDF backends drop affine rotation; v1 wraps/staggers + decimates labels instead |
| color/symbol cycles, cycle seed | `ChartStyle.color_cycle`/`symbol_cycle` (defaults from the Solarized palette in `style/Color.jl`; no cycling helper exists yet — new) |
| series ordering | order of `Chart.series`; reorder via Alt+Up/Down list-move (D7); `ChartLegend.sort::Bool` for alphanumeric legend sort |

Marker shapes v1: `:circle`, `:dot`, `:square`, `:plus`, `:cross`, `:hline`,
`:vline` (drawable with existing `GraphicsCircle`/`Rect`/`Line`). Diamond /
triangle / pentagon / star need a **filled-polygon primitive that does not
exist** — and composing fakes from segments is explicitly against house rules —
so they are deferred behind optional Phase 8 (a real cross-backend
`GraphicsPolygon`). Fonts: tick/legend text uses the `measure(text, font)`
callback (`truetype_measure_text` is the SDL-free measurer — the `pdf_measure_text`
named in graphics.md does not exist); glyphs outside basic Latin (µ, ±, ▾) must
use DejaVu fonts (no SDL font fallback).

## Document model (sketch)

Semantic documents (`Chart.jl`) — pure content, no interaction state:

```julia
@domain Chart   # generates ChartDocument (abstract root), ChartNothing, ChartInsertion + traits
abstract type ChartSeries <: ChartDocument end

@document struct Chart <: ChartDocument
    title::String
    series::CellVector = CellVector()            # ChartSeries elements; order = draw/legend order
    x_axis::Any = ChartAxis()                    # ChartAxis | ChartCategoryAxis
    y_axis::Any = ChartAxis()
    legend::Any = ChartLegend()
    style::Any = ChartStyle()
    bar_placement::Symbol = :aligned             # :aligned/:overlap/:infront/:stacked
    bar_baseline::Float64 = 0.0
    bar_baseline_color::Any = nothing            # nothing = grid color
end

@document struct ChartAxis <: ChartDocument
    title::String = ""
    min::Any = nothing;  max::Any = nothing      # nothing = auto-range (with margin heuristics)
    log::Bool = false
    grid::Symbol = :major                        # :none/:major/:all
    show_title::Bool = true;  show_labels::Bool = true
end

@document struct ChartCategoryAxis <: ChartDocument
    title::String = ""
    categories::Any = String[]                   # AbstractVector{String}
    wrap_labels::Bool = true
    show_title::Bool = true;  show_labels::Bool = true
end

@document struct ChartLegend <: ChartDocument
    visible::Bool = true
    position::Symbol = :inside                   # :inside/:above/:below/:left/:right
    anchor::Symbol = :north                      # 8 compass points
    border::Bool = false
    sort::Bool = false                           # false = series order, true = dictionary sort
end

@document struct ChartLineSeries <: ChartSeries
    label::String
    x::Any;  y::Any                              # AbstractVector{<:Real}, one cell each (D3)
    sorted::Bool = true                          # x ascending → binary-search clipping
    draw_style::Symbol = :linear                 # :none/:linear/:pins/:steps_post/:steps_pre/:steps_mid
    line_style::Symbol = :solid                  # :solid/:dotted/:dashed/:dashdot
    line_width::Int = 1
    symbol::Symbol = :none;  symbol_size::Int = 4
    color::Any = nothing                         # nothing = take next from style.color_cycle
    visible::Bool = true                         # content, not transient (D7)
end

@document struct ChartScatterSeries <: ChartSeries
    label::String
    x::Any;  y::Any
    symbol::Symbol = :circle;  symbol_size::Int = 4
    color::Any = nothing
    visible::Bool = true
end

@document struct ChartBarSeries <: ChartSeries
    label::String
    values::Any                                  # one value per category of the chart's ChartCategoryAxis
    color::Any = nothing
    visible::Bool = true
end

@document struct ChartHistogramSeries <: ChartSeries
    label::String
    binedges::Any                                # n+1 ascending edges
    binvalues::Any                               # n per-bin values
    underflows::Float64 = 0.0;  overflows::Float64 = 0.0
    draw::Symbol = :solid                        # :solid/:outline
    cumulative::Bool = false;  density::Bool = false
    show_overflow::Bool = false
    color::Any = nothing
    visible::Bool = true
end

# Every field defaulted (all-optional keyword ctor ⇒ ChartStyle() constructs).
# Exact constant names to be taken from style/Color.jl and style/Font.jl.
@document struct ChartStyle <: ChartDocument
    background::Any = nothing                    # nothing = theme background
    plot_background::Any = nothing
    grid_color::Any = nothing                    # nothing = muted content color
    title_font::Any = nothing                    # nothing = default UI font
    axis_font::Any = nothing
    legend_font::Any = nothing
    color_cycle::Any = default_color_cycle()     # Solarized accents: blue/red/green/orange/violet/cyan/magenta/yellow
    symbol_cycle::Any = default_symbol_cycle()   # [:circle, :square, :plus, :cross, :dot, ...]
    marker_limit::Int = 64                       # D5.3
    scatter_fold_threshold::Int = 10_000         # D5.4
    bin_fold_px::Int = 2                         # D5.5
end
```

Presentation document (`ChartPlot.jl`) — projection output, never serialized (D4):

```julia
@document struct ChartPlot <: ChartDocument
    chart::Any                                   # the semantic Chart, held by identity
    view::Any = nothing                          # nothing = auto-fit | ChartView (data-space window)
    cursor::Any = nothing                        # (x,y) data coords under pointer, or nothing
    hovered::Any = nothing                       # Reference to hovered series/legend item, or nothing
    drag_anchor::Any = nothing                   # pixel anchor while rubber-banding / panning
    drag_rect::Any = nothing                     # current rubber-band rect (pixels), or nothing
end
```

`ChartView` is a plain immutable struct (not `@document`) held as a cell value.
Hand outer constructors only where Rule Y/C genuinely don't apply — note
`ChartLineSeries(label, x, y)` and `ChartPlot(chart)` come free from Rule Y
(req ≥ 1 positional ctors; hand-writing them would collide with the generated
methods — a known fatal-precompile hazard). Genuinely hand-written:
`ChartHistogramSeries(label, values::AbstractVector; nbins)` (bins raw values via
`ChartGeometry`) and `Chart(series::Vector; kw...)`.

## ChartGeometry (pure functions)

- `nice_ticks(lo, hi, target)::Vector{Float64}` — Heckbert nice numbers (port
  from omnetpp-julia `VectorPlot.jl`'s `_nice_num`/`_nice_ticks`, which is the
  algorithm template to generalize, not code to import); `log_ticks(lo, hi)` —
  1/2/5 decade sequence.
- `auto_range(series, axis)::(lo, hi)` — data bounds + margin heuristics
  (1% x / 10% y padding, extend-to-zero with reduced margin, per OMNeT++ `Lines.calculatePlotArea`).
- `data_to_pixel` / `pixel_to_data` mappings from (view, plot rect, log flags);
  log transform applied before pixel mapping so ticks/decimation see linear
  space; category axes map through index space (D4).
- `visible_range(x, x0, x1)` — `searchsorted` clipping, ±1 index for continuity.
- `decimate_minmax(x, y, view, width_px)` — per-pixel-column min/max envelope;
  `step_points(...)` for the three step modes and pins.
- `fold_scatter(x, y, view, rect, cell_px)` — density grid bins + counts.
- `fold_bins(edges, values, min_px)` — adjacent-bin envelope folding.
- `decimate_category_labels(categories, per_category_px, measure)` — every k-th
  label so rendered label count is bounded by pixels (D5.6).
- `bin_values(values, nbins)` and the four histogram value transforms
  (raw / density / cumulative / CDF — the OMNeT++ `ICellValueTransform` cross-product).
- `legend_layout(items, position, anchor, rect, measure)` — multi-column packing
  with "… and N more" overflow.
- Axis-margin computation from measured tick labels (replaces OMNeT++'s two-pass
  layout: with a `measure` callback and reactive cells, margins are just a
  computed cell over view + font — no second pass needed).

Unit-tested directly (fast, headless): tick niceness, decimation exactness
(decimated polyline pixel-identical to full render at given width), fold counts,
histogram transforms, clipping indices, category-label decimation bounds.

## Printer / reader outline

Stage 1 (`ChartToChartPlot.jl`): prints a `Chart` to a stable `ChartPlot`
(identity preserved across recomputes so transient state survives); reference
maps peel exactly the `chart` step (School A) so selections ride through.

Stage 2 (`ChartPlotToGraphics.jl`), hand-written like graph —
`@projection_template` targets syntax-shaped output and does not apply:

- Stable outer `GraphicsCanvas`: title `GraphicsText`, axis titles, tick labels,
  axis `GraphicsLine`s, grid (dashed `GraphicsLine`s), legend sub-canvas, and the
  plot area as a `GraphicsViewport` (clip only, identity transform — D4) whose
  content canvas holds per-series geometry + overlay (crosshair, readout box,
  rubber-band rect, selection/hover highlights).
- Per-series computed cells: line/steps/pins → `GraphicsPolyline`s; scatter →
  `GraphicsCircle`s / small rect-line markers, or density `GraphicsRect`s when
  folded; bars → `GraphicsRect`s per placement mode (aligned/overlap/infront/
  stacked, reverse-order draw for overlap); histogram solid → `GraphicsRect`s +
  outline, outline mode → step `GraphicsPolyline`.
- **Series are own-domain leaf data rendered inline** — nothing is delegated
  through `recursion`, so there is no children-iomap (explicit position on
  AR-DELEGATE-ONE-LEVEL; precedent: `GraphLayoutToGraphics` renders
  `VertexLayout` boxes and edge polylines inline and recurses only *foreign*
  vertex content, which charts don't have). If a later feature embeds foreign
  documents (e.g. rich annotations), that feature adds `print_child` +
  `ChildrenIoMap` per AR-SHARED-CHILDREN-IOMAP.
- The deferred-iomap trick (projection-system.md) for the output selection cell.

Reader (stage 2): `@event_case` dispatch implementing the D7 table; hit regions
computed from the same geometry cells (plot rect / axis strips / legend items /
series proximity via bounded rendered geometry + `point_near_polyline`), never a
scan of raw columns. `@gestures Chart` block for the keyboard bindings
(pan/zoom/fit/reorder). Reference maps: `@reference_case` peeling `series[i]` /
`x_axis`/`y_axis`/`legend` steps, every step fully typed (D8).

## Examples, tests, registration, docs

**Examples** (four small + one composite):
`chart_line_example` (two series, mixed draw styles, markers),
`chart_bar_example` (three series × four categories, cycling placements in tests),
`chart_histogram_example` (two overlaid histograms, solid + outline),
`chart_scatter_example` (two clusters), and `chart_example` (a 2×2
`WidgetSplitPane`/table composite of the four — the workbench/screenshot demo).
Registration in all the hand-maintained lists: `package/domain/example/document/Chart.jl`
+ `projection/Chart.jl` (projection = `ChainingProjection` of the two stages, as
graph's example does), `domain_examples` in `package/domain/example/Examples.jl`,
the export list in `ProjecturedDomainExample.jl`, and the umbrella
`const examples` in `package/projectured/example/Examples.jl` (missing the last
means no sweep coverage). Auto-catalog (`Catalog.jl` BRIDGES): opt out like graph.

**Tests** (`package/domain/test/projection/ChartTest.jl`, wired into
`test_domain()`):
- `test_chart_geometry()` — the pure-function unit tests above.
- `test_chart()` — construct each chart type, `print_document`, assert canvas
  structure (counts/kinds of primitives per series/axis/grid/legend); the
  family/axis mismatch placeholder; reactivity (reassign a column → polyline
  points cell recomputes; toggle `visible` → series elements disappear; set
  `view` on the plot → decimation window changes); selection round-trip via
  `map_reference_forward`/`backward` for series/axis/legend refs through both
  stages.
- Reader tests: synthesized `MouseScroll`/drag sequences → expected view writes
  (zoom-about-cursor math, per-axis strips, rubber-band lifecycle incl. the
  Escape/MouseLeave cancel path); legend click → `visible` flip; Alt+Up/Down →
  series list order change; hover → `cursor`/`hovered` writes.
- Scale test `test_chart_scale()`: 1M-point line and scatter series and a
  10k-category bar chart each print with bounded element count (assert a
  concrete ceiling, e.g. < 20k graphics elements) in bounded time; a zoomed-in
  window renders exact (non-decimated) points.
- Inspector round-trip (P6): edit a series color / chart title / axis min via
  the `ObjectToWidget` inspector in the split pane; assert the chart canvas
  repaints with the new value.
- Umbrella sweeps: printer/click-roundtrip green; reader/repl/tree-nav marked
  `@test_broken` with root-cause comments if the D8 gap materializes.
- Live-editor verification per house practice: probe in the editor's real order
  (print → refresh → select → click → type) — headless-only checks miss wiring
  bugs.

**Docs**: `package/domain/doc/chart.md` (adapting json.md's structure to a
Graphics-direct domain: types, examples, reference paths, selection, interaction
table, scalability section); add to the per-slice guide list in
`package/domain/doc/architecture.md`; add
`"package/domain/doc/chart.md" => "chart"` to `_DOMAIN_GUIDE_EXAMPLE` for the
auto-screenshot.

## Phases

Implement in a dedicated worktree; one commit per phase; keep this plan updated
(check boxes, record decisions) as work lands.

- [x] **P0 — skeleton + documents + geometry.** DONE. Slice files, `@domain Chart` kit,
      `@document` types (semantic + `ChartPlot`), `ChartGeometry` with unit
      tests, the `ProjecturedDomain.jl` includes, layering guard green.
      Exit: `test_domain_layering()` (6/6) + `test_chart_geometry()` (81/81) pass.

      Decisions made while implementing:
      - `ChartGeometry.jl` is included **before** `Chart.jl` (Chart's
        `ChartHistogramSeries(label, values; nbins)` ctor calls `bin_values`).
      - `AxisScale(lo, hi, p0, p1; log)` needs no flip flag: a y axis passes the
        plot bottom as `p0` and the top as `p1`.
      - Geometry takes plain vectors, never documents, so it stays
        document-free and headless-testable; the projection assembles ranges.
      - `ChartPlot.jl` must `import ..ReferenceModule: Reference` — `@document`
        injects `selection::Union{Nothing,Reference}` and the name must resolve
        in the defining module.
      - Confirmed free from Rule Y, so NOT hand-written:
        `ChartLineSeries(label, x, y)`, `ChartPlot(chart)`, `Chart(title)`.
        Rule C additionally gives `Chart(title, series::AbstractVector)`; the
        planned `Chart(series::Vector; kw...)` is therefore dropped as redundant
        (and would have shadowed the generated method).
      - `ChartStyle` grew `title_color`; every field defaults, so `ChartStyle()`
        constructs as the sketch intended.
      - `series_symbol` treats `:cycle` (not `nothing`) as "take the cycle",
        since `symbol` is a `Symbol` field.
- [x] **P1 — line chart pipeline.** DONE (example registration moves to P2 with
      the other three types). Both projection stages; axes/ticks/grid/title,
      plot viewport, polyline + steps/pins draw styles, markers, color cycle.
      Exit: `test_chart()` 77/77 and `test_chart_scale()` 5/5 green; rendered to
      PDF and visually verified.

      Decisions and discoveries:
      - `nice_ticks` does NOT use Heckbert's rounded-up span. Heckbert expands
        the axis out to whole ticks; we clip ticks to the range instead, and
        combining the two left a [-1.08, 1.08] axis with three ticks. The
        interval now comes straight from `(hi-lo)/(target-1)`.
      - Series types needed **hand-written mixed positional+keyword
        constructors** (`ChartLineSeries(label, x, y; symbol=…)`, and the same
        for the other three plus `Chart(title, series; …)`). The macro emits
        all-positional or all-keyword, never the mix, so `label`/`x`/`y` would
        otherwise have had to be passed as keywords. Typed arguments keep them
        strictly more specific than the generated arity-3 form (the `GraphEdge`
        precedent).
      - **Every node of a reference must name its type, terminal included** —
        `@reference ::Chart.title` is under-typed, `::Chart.title::String` is
        not. Stage 1's forward map types the `chart` step from
        `get_reference_node_type(iomap.input)` rather than a literal `::Chart`,
        so a `ChartNothing` root maps correctly too. This is D8's risk showing
        up on the first selection test; typing the step fixed it there and
        should be applied the same way in stage 2.
      - `ChainingProjectionIoMap`'s field is `step_iomaps::Vector{Cell}` — reach
        a stage's iomap with `iomap.step_iomaps[i][]`.
      - The renderer is a plain `struct … <: Projection` with a
        `measure::Function` field, not `@projection`: a `Function` in a reactive
        field is read as a thunk (`TextToGraphics` is the precedent).
      - Canvas w/h are `ComputedCell`s over `ctx.available_width/height`, so a
        resize reflows the same canvas object instead of replacing it.
      - **Gap found:** `GraphicsPolyline` has no `dash` field (only
        `GraphicsLine` does), so `line_style` cannot yet reach a series line.
        Gridlines are dashed; series lines are solid. Faking dashes out of many
        short polylines is against house rules, so this is scheduled as P1b —
        add real `dash` support to `GraphicsPolyline` across the three backends.
- [ ] **P1b — `GraphicsPolyline` dash support.** Add a `dash` field to
      `GraphicsPolyline` (phase-continuous across segments) plus SDL, PDF and
      web draw paths, then wire `ChartLineSeries.line_style`. Touches
      `package/visual` + backends; benefits the graph domain too.
- [x] **P2 — scatter, bar, histogram printers.** DONE (example registration
      deferred to P3 so all the examples land with the legend that makes them
      readable). All four placements, histogram transforms + overflow cells,
      mismatch handling. Exit: `test_chart()` 102/102; all four types rendered
      to PDF and visually verified, including both folding paths.

      Decisions and discoveries:
      - A category axis carries **no vertical grid** (`_axis_grid` returns
        `:none` for it) — gridlines would just outline the slots the bars fill.
      - Its range is exactly `(0.5, n+0.5)` with **no padding**: padding a
        category axis pushes half an empty slot in at each end.
      - Bar series are rendered **as a group**, not one at a time, because bar
        width and slot offset both depend on how many bar series there are.
        `:overlap`/`:infront` draw in reverse order so earlier series end up in
        front.
      - Histogram y bounds must be taken **after** the value transform (a CDF
        tops out at 1, raw counts at the tallest bin), and the normalizing total
        includes under/overflow weight so a CDF really reaches 1.
      - Scatter has two regimes: below `scatter_fold_threshold` one marker per
        point, deduplicated per pixel; above it a density grid with
        **square-root** alpha shading (a linear ramp leaves everything but the
        densest handful invisible once a cell holds thousands).
      - Verified folding end to end: a 10 000-category bar chart renders 248
        series elements and 13 tick labels; a 200 000-point scatter renders
        6 801 density cells.
- [ ] **P3 — legend, selection, structural edits.** Legend layout (positions/
      anchors/multi-column/overflow), legend click-to-toggle + hover-veil
      wiring, series/axis/legend/title selection with typed reference maps,
      series insert/delete/reorder operations + Alt+Up/Down gesture (with
      reroot_operation AND default-read_intent registration). Exit: selection
      round-trip + legend toggle + reorder tests green.
- [ ] **P4 — view interaction.** Wheel/per-axis/keyboard zoom, pan, rubber-band
      drag (incl. cancel), zoom-to-fit, crosshair + readout — all as
      `ReplaceReferencedValueOperation` writes on `ChartPlot`. Exit: reader
      tests green; interactions verified live in the SDL editor.
- [ ] **P5 — scalability.** Decimation/folding wired for all types (incl.
      category-label decimation), thresholds as `ChartStyle` fields
      (`marker_limit`/`scatter_fold_threshold`/`bin_fold_px`). Exit:
      `test_chart_scale()` green — 1M-point line/scatter and 10k-category bar
      each under the element ceiling and time bound; zoom-in exactness holds.
- [ ] **P6 — property editing + docs.** `ObjectToWidget` inspector split-pane
      demo with the field-edit round-trip test; `chart.md`; screenshot dict.
      Exit: inspector round-trip test green; zero unmarked Fail/Error in the
      four umbrella sweeps (remaining gaps carry `@test_broken` + root-cause
      comments).
- [ ] **P7 (stretch) — point-level selection.** Reference-step design for
      addressing sample *i* inside a column. Constraint to satisfy or amend
      with sign-off: AR-EVERY-DOCUMENT-HAS-SELECTION (a bare vector is
      selection-opaque; candidate design: a windowed Document view over the
      column, or a new typed reference step — new step types need no sealed
      kernel edit, `PointReferenceStep` is the precedent).
- [ ] **P8 (optional, separate scope) — `GraphicsPolygon` primitive.** Real
      filled-polygon support: document type + `hit_element_at` branch
      (point-in-polygon) + `graphics_size` bounds in
      `package/visual/main/graphics/Graphics.jl`, and draw paths in all three
      backends (SDL geometry fill, PDF path fill, web canvas path) — unlocking
      diamond/triangle/star markers and area fills. Touches `package/visual` +
      backends, not the chart slice — only do with explicit sign-off.

## Risks

- **Introduced-token selection gap (D8)** — same unresolved class that keeps
  graph `@test_broken` in reader/repl sweeps; mitigations known but budgeted, not
  guaranteed.
- **No rubber-band precedent** — new interaction pattern; mirror the split-pane
  drag lifecycle and test the cancel path.
- **Per-frame recompute** — cell propagation has no equality check; if the editor's
  per-frame re-reads show up in profiles, apply the content-hash cache pattern (D6).
- **Function-thunk trap** — live until the cell-computed-marker migration lands;
  keep callables out of document/projection fields (D6).
- **`@domain` kit vs graphics-direct** — the insertion kit's completion UX
  assumes the Syntax pipeline; if `@domain Chart` drags syntax-side requirements
  into the slice, fall back to graph's hand-rolled insertion shape and record
  the AR-DOMAIN-OWNS-EDITS deviation here (D2).
- **Backend feature unevenness** — no rotation on SDL/PDF (category labels wrap
  + decimate instead), no filled polygon (marker set restricted), no working
  canvas rasterization (not needed under D5).

## Out of scope (follow-ups elsewhere)

- omnetpp-julia adapter: `VectorResult`/`StatisticItem`/`get_histograms` →
  chart documents (incl. the binedges/binvalues reshaping described in the
  header), replacing `VectorResultToGraphics` in `WorkbenchRender.jl`
  (separate plan in omnetpp-julia).
- Pie/donut charts (needs arc primitive), area fills, error bars, delta
  measurement ruler (OMNeT++ A/D/S/X keys), undo for view changes (no undo
  mechanism exists anywhere), streaming-append optimization for live series
  (whole-column reassign is O(n) — acceptable now, chunked append later).
