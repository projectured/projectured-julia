# Colored-strips chart series — enumerated values (states) over time

Add a fifth series type to the chart slice: a **colored strip** that displays a
series of enumerated values — usually states — over time. Each recorded value
paints as a solid-colored horizontal segment from its own timestamp up to the
next sample's timestamp (sample-and-hold), so a state-machine trace reads as a
band of colored runs. Multiple strip series stack as rows in one plot.

This is the native re-implementation of OMNeT++'s **"Display enums as colored
strips"** option of `plot_vectors_separate()` (the "Line Chart on Separate
Axes with Matplotlib" template, `python/omnetpp/scave/utils.py`
`_plot_enum()`). There, an enum-attributed vector is drawn with
`pcolorfast`/`pcolormesh` over the sample timestamps as cell edges — exactly
sample-and-hold — with colors from the default cycle, state names floated as
text inside any segment wider than ~10px (rotated vertical when the name does
not fit horizontally), the y axis hidden, and one subplot per vector. The
feature is matplotlib-only in OMNeT++; the native SWT plot widget never had
it.

**Independence requirement** (inherited from the chart domain): no dependency
on omnetpp-julia. Data enters as plain Julia columns — a time column and a
value-code column plus a name table. Parsing OMNeT++'s enum result-attribute
spec (`"IDLE=0,BUSY=1"`, sparse codes allowed) into that shape is a small
adapter that belongs in omnetpp-julia's `ResultChart` machinery, out of scope
here (the same split the histogram adapter precedent made). The in-repo
producer this is designed against is an FSM state trace (the `fsm` domain's
machines; omnetpp-julia's enum-attributed vectors later).

## Requirements

- [x] `ChartStripSeries`: a new `ChartSeries` document type rendering an
      enumerated-value column over an ascending time column as colored
      sample-and-hold segments.
- [x] Multiple strip series stack as rows in one plot; a strips-only chart
      labels the y axis with the series labels, one per row.
- [x] Per-state colors from the chart's color cycle indexed by state code,
      overridable per series; state names drawn inside segments wide enough to
      hold them; optional faint segment edges.
- [x] Interaction: clicking a segment selects that sample (the segment is
      outlined); the crosshair readout names the state under the cursor;
      hover veil, legend toggling, zoom/pan/rubber-band, series reordering
      all work (hiding or reordering strips under an explicit zoom window
      renumbers rows; `0` refits — D4).
- [x] Scalable: element count bounded by the plot width, not the sample count —
      equal-adjacent runs coalesce, sub-pixel runs fold; a zoomed-in window
      renders every segment it contains exactly.
- [x] Reactive: replacing the value column (one cell write) repaints the strip.
- [x] Registered example, tests, docs; the umbrella sweeps stay green with no
      new skip entries.

## Where the code goes

No new files and no new slice — the type joins the existing chart slice's
five files:

```
chart/Chart.jl               ChartStripSeries + ctors, chart_series_family,
                             chart_sample, state-color/name helpers
chart/ChartGeometry.jl       strip_runs, fold_strips (pure, unit-tested)
chart/ChartPlot.jl           (no change — view/cursor/hover are type-agnostic)
chart/ChartToChartPlot.jl    (no change — stage 1 peels only its own step)
chart/ChartPlotToGraphics.jl draw method, row layout, y row-label mode,
                             hit-testing, overlay/readout extensions
```

plus the example/registration/test/doc files listed below. No sealed file is
touched (the sealed inventory covers only `package/kernel/main/`), and
`ChartSampleReferenceStep` needs no change at all — sample evaluation was
deliberately left to `chart_sample` dispatch.

## Design decisions

### D1 — A series type in the chart slice, not a new domain

In OMNeT++ this is a rendering mode of the line chart, not a chart of its own,
and everything around the strip — axes, view window, legend, zoom/pan, part
selection, the two-stage pipeline — is exactly the chart slice's machinery.
A new slice would duplicate all of it to change only the series geometry.
Precedent: scatter was likewise promoted to a first-class series type rather
than a separate chart.

Name: `ChartStripSeries` — one series draws one strip, matching the
one-`ChartLineSeries`-per-line convention. (`ChartEnumSeries` says the data
shape, not the visual; `ChartStateSeries` over-commits to the state-machine
use.)

### D2 — Data model: integer codes plus a name table

```
x       ascending sample times (whole-column cell, any AbstractVector{<:Real})
values  one code per sample     (whole-column cell, AbstractVector{<:Integer})
states  name table: code i (1-based) means states[i]
```

Columnar codes keep a million-sample trace compact (no string per sample) and
mirror `ChartCategoryAxis.categories`' names-table shape. Codes are 1-based
into `states`, per the repository convention; OMNeT++'s sparse zero-based
specs (`"A=1,C=5"`) renumber in the out-of-scope adapter — which is strictly
more faithful than OMNeT++ itself, whose colormap bins are positional
`0..n-1` so a sparse code clamps to the last color there. A code outside the
table still draws (cycle color by code) and labels as the code's decimal
string, so a truncated table degrades visibly rather than erroring.

A second convenience constructor accepts a string/symbol column and pools it:
distinct values in order of first appearance become `states`, the column
becomes codes. Precedent: `ChartHistogramSeries`' raw-sample binning ctor.

`x` must ascend — sample-and-hold has no meaning otherwise — checked by the
convenience constructors (`issorted`), relied on by `visible_range` and the
segment search. Non-strictly: equal adjacent times are legal, because
zero-duration states occur in real traces (an FSM passing through a state in
one dispatch); they coalesce or fold away in the geometry pass. There is no
`sorted::Bool` escape hatch like the line series has.

### D3 — Sample-and-hold; the last segment runs to the view edge

Segment *i* spans `[x[i], x[i+1])`. The last sample's segment runs to
`x_end` when set, else to the resolved view's right edge — a state persists
until something ends it. This reproduces OMNeT++'s appended `endtime` (the
"last value not painted" fix there): with mixed series the strip runs to the
other series' extent, and strips-only charts paint to the (padded) window
edge. Auto-fit x comes from `(x[1], max(x[end], x_end))`, so `x_end` also
extends the fitted window.

### D4 — `:xy` family; rows at integer y, first series on top

`chart_series_family(::ChartStripSeries) = :xy` — time on a numeric
`ChartAxis`. (The `:category` x-axis branch routes wholesale to the bar group
renderer; restructuring it would buy nothing, since strip x really is
numeric.)

Visible strip series occupy rows: k strips → row centers at integer y
`1..k`, first series in list order on top (row r draws at `y = k - r + 1`),
matching the top-to-bottom reading order of the legend in its default
unsorted order (`legend.sort` diverges) and of OMNeT++'s stacked subplots.
Each strip's band spans row center ± 0.4 **in data coordinates**, so zooming
y scales rows like any data (zoom rewrites the data window; nothing here is a
pixel transform). A row depends on the other visible strips, so a per-series
`_series_y_bounds` cannot know it: strips return `nothing` there, and the
auto-fit contribution `(0.5, k + 0.5)` merges in **`_data_bounds`** — the
function `resolve_view` builds the window from, and which the gesture
readers (`_scroll_intent`, `_drag_start`, `_key_intent`) reach directly, so
the printer and every zoom/pan gesture resolve the same window. `_layout`
computes only the series-index → row map and the y-tick mode.

Rows are positions over the *visible* strips, so under an explicit (zoomed)
window, hiding a strip via the legend or reordering series renumbers the
rows while the window keeps its coordinates — the window then shows
different rows. Accepted: hiding a bar series already re-slots the remaining
bars the same way, and double-click / `0` refits. (The alternative — rows
over all strips, hidden ones keeping an empty labeled row — was rejected:
everywhere else in the chart, hidden means gone.)

Mixing strips with line/scatter/histogram series on one chart is legal but
degraded: the y axis stays numeric and the strips just occupy their integer
rows against it. A log y axis under strips is likewise degraded — rows land
at log positions — and not diagnosed. Not encouraged, recorded here.
(OMNeT++ "mixes" only at the one-subplot-per-vector level, and pins a strip
subplot's y axis outright.)

### D5 — Y row labels without a categorical y axis

When at least one strip is visible and **every** visible xy series is a
strip, the y tick section of `_layout` switches to row-label mode: one tick
per row centered on it, labeled with the series' label, no y gridlines.
Otherwise — including the all-hidden k = 0 chart — the numeric path runs
untouched. The y gridlines are emitted by `_frame_elements!` (gated on
`_axis_grid(chart.y_axis)`, which reads the user's `grid` field directly),
so the mode travels as a flag on the geometry NamedTuple that
`_frame_elements!` consults to skip the y-gridline loop — the one edit this
makes to the shared frame path.

A `ChartCategoryAxis` on y was rejected: the whole y path — `_layout`'s tick
section, `_data_bounds`, `resolve_view`, `_fit_range`, `AxisScale` — is
purely numeric today, and a categorical y axis would touch all of it to
express what one branch in the tick section expresses. OMNeT++ hides the y
axis entirely; series-label ticks are strictly more informative and reuse the
measured-label margin machinery (`ylabel_w` already works off measured
sizes). The row labels are ticks, not parts: clicking the y-axis strip still
selects the y axis, as everywhere.

### D6 — Colors: per state from the cycle, series color kept for the contract

A segment's color is `style.color_cycle` indexed by its state code (cycled),
overridable by a per-series `state_colors` vector parallel to `states` —
the translation of OMNeT++'s `ListedColormap` of `"C0", "C1", …` (whose bins
are actually positional `0..n-1`, exact only for dense zero-based enums;
ours indexes the true code). The hover veil applies `_veiled` to the state
color when a different series is hovered, same policy as `_draw_color`.

The series keeps the standard `color::Any = nothing` field: the legend
swatch machinery (`series_color(s.color, index, cycle)`) is type-generic
with no per-type dispatch, and every series type carries the field. So a
strip's legend row shows a single series color — same as OMNeT++'s default
one-gray-swatch legend entry. The per-value legend (OMNeT++'s alternate,
click-toggled legend) is a follow-up, not v1: our legend click already means
hide/show, so the toggle gesture would conflict and the value→name mapping
is already served by in-strip labels and the crosshair readout.

### D7 — Scale: coalesce runs, fold sub-pixel spans by dominant duration

Cost must stay bounded by pixels:

1. **Visible-range clipping** — `visible_range` on the ascending `x`, one
   extra index each side so straddling segments draw.
2. **Run coalescing** — consecutive samples with equal codes merge into one
   run before anything is drawn (FSM traces re-record freely), a pure
   `strip_runs` pass.
3. **Sub-pixel folding** — runs narrower than 1px fold, mirroring
   `fold_bins`' absorb-until-wide-enough sweep; the folded span takes the
   code of the **dominant state by accumulated duration** within it.
   Deterministic and stable under panning; a fast 50/50 toggle renders as a
   per-pixel dither of the two colors, which is honestly informative. The
   alternative — a neutral "mixed" fill — was rejected because a
   fine-toggling machine would render as one long gray bar and hide
   everything. This is the one place a strip is not pixel-exact reproduction
   (a sub-pixel span genuinely has no single color); at or above 1px every
   segment draws exactly, which the scale test asserts on a zoomed window.
   One deliberate divergence from `fold_bins`' sweep: an accumulating
   sub-pixel group closes *before* a run that is itself ≥ 1px, so a wide run
   is never swallowed by the sliver in front of it — pass-through applies to
   every wide run, not only group-initial ones (unit-tested exactly there;
   `fold_bins` absorbs by cumulative width and would shift the wide run's
   left edge).
4. **Label fitting** — a state name draws inside a segment only when the
   measured text fits with padding (no rotation: the SDL/PDF backends drop
   affine rotation, the same reason category labels thin instead of rotate).
   OMNeT++ labels any segment past 10px, rotating vertical when the name
   does not fit horizontally; we simply omit until it fits. Label count is
   bounded by plot width over minimum label width.

Elements per strip ≤ plot-width rects + fitting labels; a million-sample
toggle trace stays bounded, asserted in `test_chart_scale()`.

### D8 — Interaction: segments are samples, reached by pointing

A click inside a strip's band selects the **sample** whose segment contains
the click x (`searchsorted` on the raw column — the raw sample index, not the
coalesced run, so the reference stays stable when zoom changes coalescing).
The hit's right edge is the **drawn** end — `x_end` when set, else the view
edge — so a click between the last data edge and the drawn end selects the
last sample, and band space right of a set `x_end`, where nothing is drawn,
falls through to series selection like the space left of `x[1]`. In a mixed
chart the precedence is fixed: a line/scatter point within `_HIT_TOLERANCE`
wins, strip band containment is the fallback when no point hits, and the
crosshair readout follows the same rule (snapped sample over in-band state).
`chart_sample(s, i)` evaluates a sample to `(x_lo, x_hi, state_name)` —
the histogram bin's `(lower, upper, value)` shape with the name as the value.
`ChartSampleReferenceStep`, `chart_sample_reference` and `selected_sample`
work unchanged; the selected segment is called out by outlining its **drawn**
extent (the folded span's rect; the last segment out to its drawn end) — the
same drawn-vs-evaluated split hit-testing makes — via `_outline!`, the
four-line outline every existing chart selection highlight uses.

Clicking the band left of `x[1]` (no segment there) falls through to series
selection, keeping the "a selected sample still counts as its series"
containment. The crosshair keeps its vertical line; when the cursor is inside
a strip band the readout shows `label: STATE` plus the time instead of an
x/y pair. No point snapping (`_hit_points` stays empty for strips — nearest-
point search is wrong-shaped for intervals). Arrow keys stay at part
granularity, per the house rule: samples are reached by pointing, not by
walking.

## Document model (sketch)

```julia
@document struct ChartStripSeries <: ChartSeries
    label::String
    x::Any                    # ascending times; segment i spans [x[i], x[i+1])
    values::Any               # Int codes, 1-based into states
    states::Any = String[]    # code → name table
    x_end::Any = nothing      # explicit end of the last segment; nothing = view edge
    state_colors::Any = nothing  # per-state colors parallel to states; nothing = cycle
    show_labels::Bool = true  # state names inside wide-enough segments
    draw_edges::Bool = false  # faint 1px borders between segments (OMNeT++ opt-in)
    color::Any = nothing      # series color (legend swatch), per the series contract
    visible::Bool = true
end

# Hand-written mixed positional+keyword ctors (the macro generates only
# all-positional or all-keyword; typed args keep these more specific):
ChartStripSeries(label::AbstractString, x::AbstractVector,
                 values::AbstractVector{<:Integer};
                 states=String[], x_end=nothing, state_colors=nothing,
                 show_labels=true, draw_edges=false, color=nothing, visible=true)
# String/symbol column pools to codes + first-appearance name table:
ChartStripSeries(label::AbstractString, x::AbstractVector,
                 values::AbstractVector{<:Union{AbstractString,Symbol}}; kw...)
```

Both check `issorted(x)` and `x_end === nothing || x_end >= x[end]`, and
pass the trailing `nothing` selection field.
Whole-column cells, one per column, as every series does — the deliberate
`AR-FINEST-GRANULARITY` exception already recorded for the slice.

In `Chart.jl` beside the existing dispatch families:

```julia
chart_series_family(::ChartStripSeries) = :xy

function chart_sample(s::ChartStripSeries, index::Integer)
    n = min(length(s.x), length(s.values))
    (1 <= index <= n) || return nothing
    hi = index < n ? Float64(s.x[index + 1]) :
         (s.x_end === nothing ? Float64(s.x[n]) : Float64(s.x_end))
    (Float64(s.x[index]), hi, strip_state_name(s, s.values[index]))
end
```

(The last in-data segment's upper edge reports the data end, not the view
edge — a reference must not evaluate differently as someone zooms.)
`strip_state_name(s, code)` = `states[code]` in range, else `string(code)`;
`strip_state_color(s, code, style)` = `state_colors[code]` when given, else
`series_color(nothing, code, style.color_cycle)`.

## Geometry (pure functions, `ChartGeometry.jl`)

- `strip_runs(values, i0, i1) -> Vector{Tuple{Int,Int}}` — coalesce equal
  adjacent codes over the index window into `(first_index, last_index)` runs.
- `fold_strips(lefts, rights, codes, min_px) -> Vector{Tuple{Int,Int,Int}}` —
  `fold_bins`' left-to-right absorb-until-`(r - l) >= min_px` sweep, but the
  payload is the dominant code by accumulated pixel width instead of a
  min/max envelope; pass-through (with its own code) for spans already wide
  enough.

Parallel-column inputs, tuple-per-primitive outputs, 1-based inclusive index
windows, `Float64(...)` coercion — the module's existing conventions. Reused
as-is: `visible_range`, `AxisScale`/`to_pixel`/`to_data`, `label_step` (if
row labels ever need thinning), `column_bounds`/`merge_bounds`.

## Printer / reader outline (the dispatch checklist)

`ChartPlotToGraphics.jl`:

1. `_data_bounds` (~line 182): the xy branch merges `(0.5, k + 0.5)` into
   the y bounds when k visible strips exist — this is the function
   `resolve_view` builds the window from, and the gesture readers call
   `resolve_view` directly, so the merge must live here, not in `_layout`,
   for the printer and every zoom/pan gesture to resolve the same window
   (D4).
2. `_layout` (~line 436): the visible-strip row map, and the y-tick
   row-label mode when k ≥ 1 and every visible xy series is a strip (D5);
   both stored on the geometry NamedTuple.
3. `_frame_elements!` (~line 523): skip the y-gridline loop when the
   row-label flag is set; everything else untouched (D5).
4. `_series_elements!(out, g, index, s::ChartStripSeries)` (beside ~line
   704/741/862): clip → `strip_runs` → pixel edges → `fold_strips` → one
   opaque `GraphicsRect` per surviving span in the state color (veiled via
   `_veiled` when another series is hovered), `border_width=1` faint border
   when `draw_edges` — the histogram-bar precedent. Fills are opaque because
   solid state colors are the point of a strip, not as a backend
   constraint: the true-ring border work made translucent-fill-plus-border
   render correctly in all three backends, and the older in-file comments
   claiming a translucent fill composites against its border color are
   stale. Then fitting state-name `GraphicsText`s via `g.measure_label`.
   Viewport-local coordinates throughout. Factor the band geometry (row →
   pixel band, drawn right edge) into one helper used by both the printer
   and the hit-testing below, so drawing and clicking can never disagree —
   the discipline the shared geometry cell already enforces between the two.
5. `_series_x_bounds(s::ChartStripSeries)` (~line 148): `(x[1],
   max(x[end], x_end))`, `nothing` when empty.
6. `_series_y_bounds(s::ChartStripSeries)` (~line 154): `nothing` — the row
   extent is `_data_bounds`' job (D4).
7. `_sample_hit` (~line 1386): the strip branch — band containment on y,
   `searchsorted` on raw `x`, right edge bounded at the drawn end; a
   line/scatter point within tolerance wins over band containment (D8).
8. `_series_hit` (~line 1365): band-containment branch so clicks that miss
   every segment (left of `x[1]`, right of a set `x_end`) still select the
   series; `_hit_points` keeps its empty fallback for strips (no crosshair
   snap).
9. `_overlay_elements!` (~line 945): selected-sample branch for strips —
   outline the segment's drawn extent via the shared band helper instead of
   the 2-tuple point ring (bar/histogram samples keep drawing nothing,
   unchanged). The row lookup uses `get`: a selected sample whose series has
   no row — hidden via the legend after the click, or family-mismatched —
   draws nothing rather than erroring. The crosshair readout names the state
   when the cursor is inside a strip band, with the snapped-sample readout
   taking precedence (D8); the readout's row lookup gets the same `get`
   guard.

`Chart.jl`: the `@document` type (auto-exported by the macro like every
series type — the hand-written export list carries only functions), two
ctors, `chart_series_family`, `chart_sample`, and
`strip_state_name`/`strip_state_color` kept module-internal: plain functions
get no auto-export, and nothing outside the slice needs them.

No change: `ChartToChartPlot` (peels only its own step), `chart_parts` /
`chart_part_index` / `move_series` / `remove_series` / the `@gestures Chart`
block (all operate on the series list generically), legend plan and swatch
(type-generic via `s.label` / `s.color`), `ChartSampleReferenceStep` and its
DSL registration.

## Examples, tests, registration, docs

**Example** `chart_strip_example` — strips-only, so the row-label y mode is
what the screenshot shows: two-or-three MAC-ish state traces (e.g. IDLE /
BACKOFF / TRANSMIT / COLLISION over a few hundred alternating samples, two
hosts sharing one state table plus one series with its own), `x_end` set on
one series and defaulted on another, a title and a legend. Registration in
all the hand-maintained lists: `make_chart_strip_document_example` in
`package/domain/example/document/Chart.jl`,
`make_chart_strip_projection_example` (delegating to
`make_chart_pipeline_example`) in `package/domain/example/projection/Chart.jl`,
the `Example` const + `domain_examples` entry in
`package/domain/example/Examples.jl`, the export in
`ProjecturedDomainExample.jl`, and the umbrella `const examples` in
`package/projectured/example/Examples.jl` — the list the sweeps actually
iterate; missing it means no sweep coverage. The composite 2×2 `chart_example`
stays as it is (its grid is full; the guide screenshot embeds only it).

**Tests**:

- `test_chart_geometry()` (`ChartGeometryTest.jl`): `strip_runs` (coalescing,
  window edges, single-run, empty) and `fold_strips` (pass-through above
  min_px, dominant-by-width choice, chained sub-pixel absorption, a wide run
  immediately after a sub-pixel group passes through untouched — the group
  closes early — and the `l == r` guard) unit tests.
- `test_chart()` (`ChartTest.jl`), new `@testset`s following the per-kind
  pattern: segment geometry and colors (counts, sample-hold edges, the
  view-edge last segment, `x_end`); run coalescing; state_colors override and
  out-of-table degradation; in-strip labels appear exactly when they fit;
  `draw_edges`; row layout and first-series-on-top; y row-label mode on a
  strips-only chart and numeric y on a mixed one; family trait;
  `chart_sample` evaluation incl. edge cases; auto-fit resolves through
  `resolve_view` to a window spanning the rows (so printer and gesture
  readers agree); click-a-segment → sample-reference round-trip through both
  stages; selected-segment outline drawn; the selected sample survives
  hiding its series (click a segment, legend-hide the series, reprint — no
  error, no callout); mixed-chart hit precedence (a point within tolerance
  beats band containment); click left of `x[1]` or right of a set `x_end`
  selects the series; crosshair readout names the state; hover veil; legend
  visibility toggle; reactivity (replace `values` → repaint, no projection
  re-run).
- `test_chart_scale()`: a million-sample two-state toggle strip prints under
  the element ceiling; a zoomed-in window draws its segments exactly (every
  ≥1px run its own rect).
- Sweeps: `chart_strip_example` is picked up automatically once in the
  umbrella list — printer/reader/repl/position-nav/tree-nav/click-roundtrip
  green, no new skip entries expected (the four standalone chart examples all
  navigate; only the widget-container composites are skipped).
- Baseline discipline: the y-tick section of `_layout` is shared by every
  chart, so diff `test_domain()` against clean main, not just the chart
  tests.
- Live-editor verification per house practice: print → refresh → select →
  click → type in the real editor order, not only headless probes.

**Docs**: `package/domain/doc/chart.md` — add the type to the types table,
a strips section (sample-and-hold, rows, state colors/labels, the
dominant-fold rule), the sample-evaluation triple, and the interaction rows
that differ. The customization-against-OMNeT++ section gains
`enum_as_strip`/`enum_strip_edges` ↔ `ChartStripSeries`/`draw_edges`, and the
per-value legend + y-axis-hidden differences called out under "not covered,
and why".

## Phases

Implement in a dedicated worktree; one commit per phase; keep this plan
updated (check boxes, record decisions) as work lands.

- [x] **P0 — geometry + document type.** DONE. `strip_runs`/`fold_strips` with
      unit tests; `ChartStripSeries` + ctors + `chart_series_family` +
      `chart_sample` + name/color helpers.
      Exit: `test_chart_geometry()` 105/105 (was 81).

      Decisions made while implementing:
      - `fold_strips` takes the pixel edges **unrounded**, rounding only on
        output. With `Int` edges every sub-pixel run has width zero, so
        "dominant by duration" would have had no signal to work with and the
        winner would have been arbitrary. Fractional pixel width is
        proportional to data duration, which is what the rule wants.
      - The distinct-code accumulator is a `Vector{Tuple{Int,Float64}}`
        scanned linearly rather than a `Dict`: a fold spans a handful of
        states, and this allocates nothing per span.
      - The name-column check is O(1) — `eltype`, falling back to the first
        element for a `Vector{Any}` — so a million-sample `Vector{Int}` is
        neither scanned nor copied on its way into a series.
- [x] **P1 — rendering.** DONE. The `_data_bounds` row merge; row map + y
      row-label mode in `_layout`; the `_frame_elements!` gridline flag;
      `_series_elements!`; x/y bounds methods; labels, edges, veiling.
      Exit: the existing `test_chart()` 235/235 and `test_chart_scale()`
      14/14 unchanged by the shared-seam edits, before any strip test was
      added — the baseline diff the top risk asks for.

      Decisions made while implementing:
      - `_strip_rows` takes the **chart**, not just the series list: on a
        category x axis it returns no rows at all. A strip there is never
        drawn (the printer routes the whole category family to the bar
        renderer), and without this its band would still have been clickable
        with nothing in it.
      - The row-label flag gates only the **y** gridline loop.
        `_frame_elements!` runs one loop per axis off the same `grid_color`,
        and the x gridlines must stay — a strip chart still measures time.
      - `_series_label` already existed for the legend and reads `label` off
        anything that has one, so the row labels reuse it rather than
        introducing a second accessor.
      - In-strip label colour is picked by luminance against the state's own
        fill, so a name stays readable at both ends of the colour cycle.
- [x] **P2 — interaction.** DONE. `_sample_hit` strip branch; `_series_hit`
      band fallback; selected-segment outline; crosshair state readout.
      Exit: `test_chart()` 289/289, including 30 strip and 21 strip-sample
      assertions.

      Decisions made while implementing:
      - Precedence is expressed by **ordering, not distance**: the existing
        point loops keep their `best_d` competition and the strip branch runs
        only when they come back empty. Band containment has no distance to
        compare against a pixel radius, so folding it into the same
        comparison would have meant inventing one.
      - `_strip_sample_at` bounds the hit at `_strip_end` — the same function
        the printer uses for the drawn edge — which is what makes the empty
        band past an explicit `x_end` fall through to series selection.
- [x] **P3 — example, registration, scale, docs.** DONE.
      `chart_strip_example` in all five registration points; scale test;
      `chart.md`.
      Exit: `test_chart_geometry()` 105/105, `test_chart()` 289/289,
      `test_chart_scale()` 21/21.

      Decisions and discoveries:
      - The example passes **integer codes** with an explicit `states` table
        rather than a name column: pooling assigns codes by first appearance,
        which would not have matched the declared table's order.
      - **No screenshot to regenerate.** That exit criterion was inherited
        from the chart-domain plan, but `chart.md` carries no screenshot on
        `main` and no `chart*.png` is checked in — the guide injector has
        never been run for it. Nothing to do rather than something to add.
      - The scale test cannot assert `spans == visible_samples`:
        `visible_range` deliberately keeps one extra index each side so a
        segment straddling an edge still draws, so exactness is pinned as
        `visible <= spans <= visible + 2` with every span at least a pixel.
      - `GraphicsRect`'s fields are `w`/`h`, not `width`/`height`.

## Risks

- **The shared seams — `_layout`'s y-tick section, `_frame_elements!`'s
  gridline loop, `_data_bounds` — are walked by every chart.** All three
  edits must leave the numeric path byte-identical when no strips are
  visible; the baseline diff of `test_domain()` is the guard (wide-refactor
  lesson).
- **The macro-generated all-positional constructor bypasses the ctor
  checks.** A strip built through it with unsorted `x` silently mis-clips
  (`visible_range`) and mis-hits (`searchsorted`) — there is no `sorted`
  fallback scan as the line series has. Ascending `x` is a documented data
  contract in chart.md's strips section, garbage-in otherwise.
- **Overlay/sample plumbing predates 3-tuple-with-outline samples.** The
  selected-sample block must keep bars/histograms drawing nothing and
  line/scatter ringing exactly as today; dispatch on series type, not tuple
  shape.
- **Mixed strip + line charts are legal but odd** (integer rows on a numeric
  axis). Accepted and recorded in D4; if it turns out actively confusing, a
  diagnostic like the family-mismatch placeholder is the follow-up, not a
  categorical y axis.
- **Label pass cost.** Measuring a name per visible segment is bounded by
  plot width / min label width, but the measure closure is called during
  layout — keep labels out of the hot geometry cell if profiling ever shows
  it (the point cache precedent).
- **Color-by-code collides with color-by-series-index** for charts mixing
  strips and lines: segment colors and line colors draw from the same cycle
  with different indexing. Cosmetic, OMNeT++ has the same property, noted in
  the docs.

## Out of scope (follow-ups)

- **Per-value legend** (OMNeT++'s click-toggled alternate legend): needs a
  legend-swatch dispatch seam and an affordance that doesn't collide with
  legend-click-hides-series. Until then, in-strip labels + the crosshair
  readout carry the value→name mapping.
- **omnetpp-julia adapter**: parse the `"IDLE=0,BUSY=1"` enum result
  attribute (sparse codes, auto-increment) into codes + table and hook
  `VectorResultToChart` to emit a `ChartStripSeries` for enum-attributed
  vectors — omnetpp-julia side, with its own plan.
- **FSM trace recording**: the `fsm` domain generating a strip-ready
  (time, state) trace from a running machine — belongs with the fsm/runtime
  work.
- **Y-axis strip zoom lock** (OMNeT++ pins y to `[0,1]` on strip subplots):
  our rows are real data coordinates and y-zoom behaves coherently, so no
  lock in v1; revisit only if users trip over it.
