# Fragment of `ChartModule`.
#
# The chart document domain: a `Chart` holds a list of data series, two axes, a
# legend and a style. This file is **pure semantic content** — everything here
# serializes. Transient view state (the zoom window, the cursor, an in-progress
# drag) lives on `ChartPlot` in `ChartPlot.jl`, which is projection
# output, exactly as `GraphLayout` holds geometry outside `GraphGraph`.
#
# Series data is held as whole column vectors, one reactive cell per column: a
# column is bulk numeric leaf data, not navigable structure, so per-point cells
# would cost ~88 bytes each and buy nothing. Reassigning a column is what makes a
# chart repaint. Any `AbstractVector{<:Real}` works, so a data-frame column can be
# handed straight to a series without this package depending on DataFrames.
#
# Two axis families:
# - **XY** (`ChartAxis` on x) carries `ChartLineSeries`, `ChartScatterSeries`,
#   `ChartHistogramSeries` and `ChartStripSeries`, which may be mixed on one chart.
# - **Category** (`ChartCategoryAxis` on x) carries `ChartBarSeries`.
using ..KernelModule
using ..PlatformModule



@domain Chart

"""
Common supertype of every data series a `Chart` can hold.
"""
abstract type ChartSeries <: ChartDocument end

# ── Style ────────────────────────────────────────────────────────────────
# The colour and marker cycles themselves live in `PlotModule`, beside the
# plot arithmetic: a sequence chart hands colours out by the same rule.

"""
Chart-wide visual style. Every field defaults, so `ChartStyle()` constructs and a
chart only names what it overrides. A `nothing` color/font means "take the
projection's theme default", resolved at print time rather than baked in here.
So a `nothing` `color_cycle`, the default, takes the `series_colors` of the
theme, which follow the colour settings of the appearance.

`marker_limit`, `scatter_fold_threshold` and `bin_fold_px` are the scalability
knobs: how many visible points still get individual markers, when a scatter
cloud folds to a density grid, and how narrow a bar/bin may get before adjacent
ones fold into an envelope.
"""
@document struct ChartStyle <: ChartDocument
    background::Any = nothing
    plot_background::Any = nothing
    grid_color::Any = nothing
    title_color::Any = nothing
    title_font::Any = nothing
    axis_font::Any = nothing
    legend_font::Any = nothing
    color_cycle::Any = nothing
    symbol_cycle::Any = default_symbol_cycle()
    marker_limit::Int = 64
    scatter_fold_threshold::Int = 10_000
    bin_fold_px::Int = 2
end

# ── Axes ─────────────────────────────────────────────────────────────────

"""
A numeric axis. `min`/`max` are `nothing` for auto-ranging from the data (with
the usual padding), a number to pin that end. `grid` is `:none`, `:major` or
`:all`.
"""
@document struct ChartAxis <: ChartDocument
    title::String = ""
    min::Any = nothing
    max::Any = nothing
    log::Bool = false
    grid::Symbol = :major
    show_title::Bool = true
    show_labels::Bool = true
end

"""
A categorical axis: one slot per entry of `categories`. Bars occupy the slots;
the axis coordinate is the category index, so zoom and pan work on index space
just as they do on a numeric axis.
"""
@document struct ChartCategoryAxis <: ChartDocument
    title::String = ""
    categories::Any = String[]
    wrap_labels::Bool = true
    show_title::Bool = true
    show_labels::Bool = true
end

# ── Legend ───────────────────────────────────────────────────────────────

"""
The legend box. `position` is `:inside`, `:above`, `:below`, `:left` or
`:right`; `anchor` is one of the eight compass points, placing the box within
whichever strip `position` reserved. `sort` switches item order from the series
order to a dictionary sort of the labels.
"""
@document struct ChartLegend <: ChartDocument
    visible::Bool = true
    position::Symbol = :inside
    anchor::Symbol = :north
    border::Bool = false
    sort::Bool = false
end

# ── Series ───────────────────────────────────────────────────────────────

"""
A line series over paired `x`/`y` columns.

`sorted` records that `x` ascends, which lets the projection binary-search the
visible index range instead of scanning the column. `draw_style` is `:none`,
`:linear`, `:pins`, `:steps_post`, `:steps_pre` or `:steps_mid`; `line_style` is
`:solid`, `:dotted` or `:dashed`. A `nothing` `color` takes the next entry of the
chart's color cycle.
"""
@document struct ChartLineSeries <: ChartSeries
    label::String
    x::Any
    y::Any
    sorted::Bool = true
    draw_style::Symbol = :linear
    line_style::Symbol = :solid
    line_width::Int = 1
    symbol::Symbol = :none
    symbol_size::Int = 4
    color::Any = nothing
    visible::Bool = true
end

# The columns positional, the styling by keyword — the shape anyone actually
# writes. The macro generates either all-positional or all-keyword, never the
# mix, so this is hand-written (as `GraphEdge` is); the typed arguments keep it
# strictly more specific than the generated arity-3 form.
function ChartLineSeries(label::AbstractString, x::AbstractVector, y::AbstractVector;
                         sorted::Bool=issorted(x), draw_style::Symbol=:linear,
                         line_style::Symbol=:solid, line_width::Integer=1,
                         symbol::Symbol=:none, symbol_size::Integer=4,
                         color=nothing, visible::Bool=true)
    ChartLineSeries(String(label), x, y, sorted, draw_style, line_style,
                    Int(line_width), symbol, Int(symbol_size), color, visible, nothing)
end

"""
A scatter series over paired `x`/`y` columns: markers only, no connecting line.
Above the style's `scatter_fold_threshold` visible points the projection folds
the cloud into a density grid instead of drawing one marker per point.
"""
@document struct ChartScatterSeries <: ChartSeries
    label::String
    x::Any
    y::Any
    symbol::Symbol = :circle
    symbol_size::Int = 4
    color::Any = nothing
    visible::Bool = true
end

function ChartScatterSeries(label::AbstractString, x::AbstractVector, y::AbstractVector;
                            symbol::Symbol=:circle, symbol_size::Integer=4,
                            color=nothing, visible::Bool=true)
    ChartScatterSeries(String(label), x, y, symbol, Int(symbol_size), color, visible, nothing)
end

"""
A bar series: one value per category of the chart's `ChartCategoryAxis`. How
several bar series share a category slot is the chart's `bar_placement`.
"""
@document struct ChartBarSeries <: ChartSeries
    label::String
    values::Any
    color::Any = nothing
    visible::Bool = true
end

"""
A histogram series: `binedges` holds `n+1` ascending edges, `binvalues` the `n`
per-bin values, and `underflows`/`overflows` the weight outside the outermost
edges (drawn as extra cells when `show_overflow`).

`cumulative` and `density` select the four value transforms — raw count, density
(value per unit width per total weight), running sum, and CDF.

`ChartHistogramSeries(label, values; nbins)` bins a raw sample column instead.
"""
@document struct ChartHistogramSeries <: ChartSeries
    label::String
    binedges::Any
    binvalues::Any
    underflows::Float64 = 0.0
    overflows::Float64 = 0.0
    draw::Symbol = :solid
    cumulative::Bool = false
    density::Bool = false
    show_overflow::Bool = false
    color::Any = nothing
    visible::Bool = true
end

function ChartBarSeries(label::AbstractString, values::AbstractVector;
                        color=nothing, visible::Bool=true)
    ChartBarSeries(String(label), values, color, visible, nothing)
end

function ChartHistogramSeries(label::AbstractString, binedges::AbstractVector,
                              binvalues::AbstractVector;
                              underflows::Real=0.0, overflows::Real=0.0,
                              draw::Symbol=:solid, cumulative::Bool=false,
                              density::Bool=false, show_overflow::Bool=false,
                              color=nothing, visible::Bool=true)
    ChartHistogramSeries(String(label), binedges, binvalues,
                         Float64(underflows), Float64(overflows), draw,
                         cumulative, density, show_overflow, color, visible, nothing)
end

"""
    ChartHistogramSeries(label, values; nbins=20)

Bin a raw sample column into `nbins` equal-width bins. Arity 2, so it never
collides with the edges-and-values form above.
"""
function ChartHistogramSeries(label::AbstractString, values::AbstractVector; nbins::Integer=20)
    edges, counts = compute_bin_values(values, nbins)
    ChartHistogramSeries(String(label), edges, counts)
end

"""
A strip series: a column of enumerated values — usually the states of a machine
— over an ascending time column, drawn as a band of colored segments. Segment
`i` spans `[x[i], x[i+1])`, so a value holds until the next sample replaces it.

`values` holds 1-based codes into the `states` name table; a code outside the
table is drawn and labelled as its own number. `x_end` ends the last segment,
which otherwise runs to the edge of the view — a state persists until something
ends it. `state_colors`, when given, replaces the color a code would take from
the chart's cycle.

`x` must ascend, non-strictly: equal adjacent times are legal (a machine can
pass through a state within one dispatch) and fold away. Nothing recovers a
column that does not ascend — the clipping and the hit-testing both binary-search
it — so the convenience constructors check, and a series built through the
generated all-positional form is the caller's responsibility.
"""
@document struct ChartStripSeries <: ChartSeries
    label::String
    x::Any
    values::Any
    states::Any = String[]
    x_end::Any = nothing
    state_colors::Any = nothing
    show_labels::Bool = true
    draw_edges::Bool = false
    color::Any = nothing
    visible::Bool = true
end

"""
    ChartStripSeries(label, x, values; states, x_end, …)

`values` may be the codes themselves, or the state names: a column of strings or
symbols is pooled into codes and a `states` table in order of first appearance,
the same convenience `ChartHistogramSeries(label, values; nbins)` offers over
raw samples.
"""
function ChartStripSeries(label::AbstractString, x::AbstractVector, values::AbstractVector;
                          states=nothing, x_end=nothing, state_colors=nothing,
                          show_labels::Bool=true, draw_edges::Bool=false,
                          color=nothing, visible::Bool=true)
    issorted(x) || throw(ArgumentError("ChartStripSeries needs an ascending x column"))
    if x_end !== nothing && !isempty(x) && x_end < last(x)
        throw(ArgumentError("ChartStripSeries x_end must not precede the last sample"))
    end
    codes, pooled = _strip_codes(values)
    ChartStripSeries(String(label), x, codes,
                     states === nothing ? pooled : states,
                     x_end, state_colors, show_labels, draw_edges,
                     color, visible, nothing)
end

# A named column pools; a code column is handed through untouched, so a
# million-sample trace is not copied to be wrapped in a series.
_strip_named_column(values::AbstractVector) =
    eltype(values) <: Union{AbstractString, Symbol} ||
    (!isempty(values) && !(eltype(values) <: Integer) &&
     first(values) isa Union{AbstractString, Symbol})

function _strip_codes(values::AbstractVector)
    _strip_named_column(values) || return (values, String[])
    table = String[]
    index = Dict{String, Int}()
    codes = Vector{Int}(undef, length(values))
    for (i, value) in enumerate(values)
        name = String(string(value))
        codes[i] = get!(index, name) do
            push!(table, name)
            length(table)
        end
    end
    (codes, table)
end

"""
    strip_state_name(series, code) -> String

What a code is called: its entry in the series' `states`, or its own number when
the table does not reach it — a truncated table degrades visibly instead of
erroring.
"""
function strip_state_name(series::ChartStripSeries, code)
    states = series.states
    c = Int(code)
    (1 <= c <= length(states)) ? String(states[c]) : string(c)
end

"""
    strip_state_color(series, code, cycle) -> StyleColor

The color of a state: the series' own `state_colors` entry, else the cycle
entry for that code. Colors follow the code rather than the series, so the same
state reads the same across every strip on the chart.
"""
function strip_state_color(series::ChartStripSeries, code, cycle)
    c = Int(code)
    own = series.state_colors
    own !== nothing && 1 <= c <= length(own) && return own[c]
    get_series_color(nothing, c, cycle)
end

# ── Chart ────────────────────────────────────────────────────────────────

"""
A chart: a title, a list of `ChartSeries` (the order is both the draw order and
the legend order), the two axes, the legend and the style.

The bar fields are chart-wide because placement is a property of how the series
share a category slot, not of any one series: `:aligned` gives each series its
own sub-slot, `:overlap` offsets them by half a bar, `:infront` draws them over
each other from the baseline, and `:stacked` sums them.
"""
@document struct Chart <: ChartDocument
    title::String
    series::CellVector = CellVector()
    x_axis::Any = ChartAxis()
    y_axis::Any = ChartAxis()
    legend::Any = ChartLegend()
    style::Any = ChartStyle()
    bar_placement::Symbol = :aligned
    bar_baseline::Float64 = 0.0
    bar_baseline_color::Any = nothing
end

function Chart(title::AbstractString, series::AbstractVector;
               x_axis=ChartAxis(), y_axis=ChartAxis(),
               legend=ChartLegend(), style=ChartStyle(),
               bar_placement::Symbol=:aligned, bar_baseline::Real=0.0,
               bar_baseline_color=nothing)
    Chart(String(title), CellVector(series), x_axis, y_axis, legend, style,
          bar_placement, Float64(bar_baseline), bar_baseline_color, nothing)
end

# ── Family traits ────────────────────────────────────────────────────────

"""
    get_chart_series_family(series) -> :xy | :category | :unknown

Which axis family a series needs on x. The projection leaves out a series
whose family does not match the chart's x axis, and the frame still draws,
rather than throwing.
"""
get_chart_series_family(::Any) = :unknown
get_chart_series_family(::ChartLineSeries) = :xy
get_chart_series_family(::ChartScatterSeries) = :xy
get_chart_series_family(::ChartHistogramSeries) = :xy
get_chart_series_family(::ChartStripSeries) = :xy
get_chart_series_family(::ChartBarSeries) = :category

"""
    get_chart_axis_family(axis) -> :xy | :category | :unknown

The counterpart of [`get_chart_series_family`](@ref) for an x axis.
"""
get_chart_axis_family(::Any) = :unknown
get_chart_axis_family(::ChartAxis) = :xy
get_chart_axis_family(::ChartCategoryAxis) = :category

# ── Samples ──────────────────────────────────────────────────────────────

"""
    get_chart_sample(series, index) -> value | nothing

What the `index`-th sample of a series is: the `(x, y)` pair of a line or
scatter point, the `(lower, upper, value)` of a histogram bin, the value of a
bar. `nothing` when the index is out of range.

This is what a `ChartSampleReferenceStep` evaluates to — every reference in the
tree descends to a value, and this is a sample's.
"""
get_chart_sample(::Any, ::Integer) = nothing

function get_chart_sample(s::Union{ChartLineSeries, ChartScatterSeries}, index::Integer)
    n = min(length(s.x), length(s.y))
    (1 <= index <= n) || return nothing
    (Float64(s.x[index]), Float64(s.y[index]))
end

function get_chart_sample(s::ChartBarSeries, index::Integer)
    (1 <= index <= length(s.values)) || return nothing
    Float64(s.values[index])
end

function get_chart_sample(s::ChartHistogramSeries, index::Integer)
    (1 <= index <= min(length(s.binvalues), length(s.binedges) - 1)) || return nothing
    (Float64(s.binedges[index]), Float64(s.binedges[index+1]), Float64(s.binvalues[index]))
end

# The extent evaluated here is the one in the data, not the one on screen: the
# last segment is drawn out to the end of the view, but a reference must not
# evaluate differently as someone zooms.
function get_chart_sample(s::ChartStripSeries, index::Integer)
    n = min(length(s.x), length(s.values))
    (1 <= index <= n) || return nothing
    lower = Float64(s.x[index])
    upper = index < n ? Float64(s.x[index + 1]) :
            (s.x_end === nothing ? lower : Float64(s.x_end))
    (lower, upper, strip_state_name(s, s.values[index]))
end

# The step type is domain-agnostic; what a sample *is* depends on the series
# holding it, so the evaluation lives here rather than in the step's own file.
ReferenceModule.evaluate_reference_step(step::ChartSampleReferenceStep, document) =
    get_chart_sample(document, step.index)

"""
    make_chart_sample_reference(chart, series_index, sample_index) -> Reference

The reference naming one sample of one series, fully typed.
"""
function make_chart_sample_reference(chart::Chart, series_index::Integer, sample_index::Integer)
    # Built structurally rather than through the `@reference` DSL: the DSL reads
    # a lowercase `::t` as a runtime type and cannot then continue into an
    # extension step. Annotating against the chart fills in every node's type,
    # including the sample's own, which is whatever `get_chart_sample` returns.
    annotate_reference_types(chart,
        ConcreteReference(FieldReferenceStep("series"),
            ConcreteReference(ElementReferenceStep(series_index),
                ConcreteReference(ChartSampleReferenceStep(sample_index),
                                  EmptyReference()))))
end

"""
    get_selected_sample(chart) -> (series_index, sample_index) | nothing

Which sample the chart's selection names, or `nothing` when it names something
coarser.
"""
function get_selected_sample(chart::Chart)
    reference = chart.selection
    reference === nothing && return nothing
    n = length(chart.series)
    @reference_case reference begin
        ::Chart.series[i].sample(k) => (1 <= i <= n ? (i, k) : nothing)
        __ => nothing
    end
end

# ── Parts, selection and navigation ──────────────────────────────────────
#
# A chart is a document like any other, so its parts are selectable and the
# selection moves with the editor's own navigation keys. The parts are the
# things that are actually on screen — the title, the two axes, the legend and
# each series — in the order they read: chrome first, then the data.
#
# `style` is deliberately not among them. It has no region on the canvas, so a
# selection landing there would have nothing to show; it is reached through a
# property inspector instead.

_chart_field_reference(chart::Chart, field::AbstractString) =
    annotate_reference_types(chart,
        ConcreteReference(FieldReferenceStep(field), EmptyReference()))

_chart_series_reference(chart::Chart, index::Integer) =
    annotate_reference_types(chart,
        ConcreteReference(FieldReferenceStep("series"),
            ConcreteReference(ElementReferenceStep(index), EmptyReference())))

"""
    collect_chart_parts(chart) -> Vector{Reference}

Every selectable part of a chart, in reading order: the title, the x axis, the
y axis, the legend, then each series. Navigation walks this list, and the
projection draws whichever entry is selected.
"""
function collect_chart_parts(chart::Chart)
    parts = Reference[_chart_field_reference(chart, "title"),
                      _chart_field_reference(chart, "x_axis"),
                      _chart_field_reference(chart, "y_axis"),
                      _chart_field_reference(chart, "legend")]
    for i in 1:length(chart.series)
        push!(parts, _chart_series_reference(chart, i))
    end
    parts
end

"""
    get_chart_part_index(chart, reference) -> Int

Which part a reference points at (or into), or `0` for the whole chart and
anything unrecognised.
"""
function get_chart_part_index(chart::Chart, reference)
    reference === nothing && return 0
    n = length(chart.series)
    @reference_case reference begin
        ::Chart.title.rest... => 1
        ::Chart.x_axis.rest... => 2
        ::Chart.y_axis.rest... => 3
        ::Chart.legend.rest... => 4
        ::Chart.series[i].rest... => (1 <= i <= n ? 4 + i : 0)
        __ => 0
    end
end

"""
    get_selected_series_index(chart) -> Int

Which series the chart's selection points into, or `0`. The series list is both
the draw order and the legend order, so this is what the reorder gestures act
on.
"""
function get_selected_series_index(chart::Chart)
    reference = chart.selection
    reference === nothing && return 0
    @reference_case reference begin
        ::Chart.series[i].rest... => (1 <= i <= length(chart.series) ? i : 0)
        __ => 0
    end
end

# Step to another part by offset, clamping at both ends. Returns nothing when
# there is nowhere to go, which declines the gesture rather than consuming it.
function _step_part(chart::Chart, offset::Integer)
    parts = collect_chart_parts(chart)
    isempty(parts) && return nothing
    current = get_chart_part_index(chart, chart.selection)
    # From the whole chart, a forward step enters the first part and a backward
    # step stays put.
    target = current == 0 ? (offset > 0 ? 1 : 0) : current + offset
    (1 <= target <= length(parts)) || return nothing
    target == current && return nothing
    ReplaceSelectionOperation(parts[target])
end

_select_part(chart::Chart, index::Integer) = begin
    parts = collect_chart_parts(chart)
    (1 <= index <= length(parts)) ? ReplaceSelectionOperation(parts[index]) : nothing
end

_select_whole(chart::Chart) =
    ReplaceSelectionOperation(EmptyReference(get_reference_node_type(chart)))

"""
    move_series(chart, from, to) -> Operation | Nothing

Move a series within the list, as a delete paired with an insert. The selection
follows the series to its new position, so a run of reorder gestures keeps
acting on the same one.

Reordering *is* the ordering feature: the list order decides both which series
draws on top and the order the legend lists them in.
"""
function move_series(chart::Chart, from::Integer, to::Integer)
    n = length(chart.series)
    (1 <= from <= n && 1 <= to <= n && from != to) || return nothing
    moved = chart.series[from]
    field_path = _chart_field_reference(chart, "series")
    landing = concat_references(field_path,
        ConcreteReference(ElementReferenceStep(to),
                          EmptyReference(get_reference_node_type(moved))))
    CompoundOperation(Any[
        make_delete_elements_operation(field_path, from; root=chart),
        make_insert_elements_operation(field_path, to, Any[moved]; root=chart),
        ReplaceSelectionOperation(landing)])
end

"""
    remove_series(chart) -> Operation | Nothing

Delete whichever series the selection points into, or nothing when it points
somewhere else.
"""
function remove_series(chart::Chart)
    index = get_selected_series_index(chart)
    index == 0 && return nothing
    make_delete_elements_operation(_chart_field_reference(chart, "series"), index;
                                   root=chart)
end

# Navigation owns the arrow keys, as it does everywhere else in the editor: the
# plain arrows step between parts and Alt+arrows walk the tree. Panning and
# zooming the view are the projection's, on Shift+arrow and the wheel, and
# reordering takes Ctrl+Shift so it collides with neither.
@gestures Chart begin
    KeyDown(:home; ctrl) => "Select the first part" => _select_part(doc, 1)
    KeyDown(:end; ctrl) => "Select the last part" => _select_part(doc, length(collect_chart_parts(doc)))
    KeyDown(:home;) => "Select the first part" => _select_part(doc, 1)
    KeyDown(:end;) => "Select the last part" => _select_part(doc, length(collect_chart_parts(doc)))
    KeyDown(:left;) => "Select the previous part" => _step_part(doc, -1)
    KeyDown(:up;) => "Select the previous part" => _step_part(doc, -1)
    KeyDown(:right;) => "Select the next part" => _step_part(doc, 1)
    KeyDown(:down;) => "Select the next part" => _step_part(doc, 1)

    KeyDown(:home; ctrl, alt) => "Select the whole chart" => _select_whole(doc)
    # Alt and an arrow walk the chart as they walk any document: up to the
    # whole chart, down to its first part, and sideways between the parts, where
    # the first and the last part keep the selection. A key with nothing to walk
    # to answers nothing, so a walk around the chart can.
    KeyDown(:up; alt) => "Select the whole chart" =>
        (get_chart_part_index(doc, doc.selection) == 0 ? nothing : _select_whole(doc))
    KeyDown(:down; alt) => "Select the first part" =>
        (get_chart_part_index(doc, doc.selection) == 0 ? _select_part(doc, 1) : nothing)
    KeyDown(:left; alt) => "Select the previous part" =>
        (get_chart_part_index(doc, doc.selection) == 0 ? nothing :
         something(_step_part(doc, -1), ReplaceSelectionOperation(doc.selection)))
    KeyDown(:right; alt) => "Select the next part" =>
        (get_chart_part_index(doc, doc.selection) == 0 ? nothing :
         something(_step_part(doc, 1), ReplaceSelectionOperation(doc.selection)))

    # The "is a series selected" test lives in the handlers rather than in a
    # guard: a block-level `when` would gate the navigation rules above as well,
    # and a per-rule guard sees only the event, not the document.
    KeyDown(:up; ctrl, shift) => "Move the selected series earlier" =>
        move_series(doc, get_selected_series_index(doc), get_selected_series_index(doc) - 1)
    KeyDown(:down; ctrl, shift) => "Move the selected series later" =>
        move_series(doc, get_selected_series_index(doc), get_selected_series_index(doc) + 1)
    KeyDown(:delete; alt) => "Remove the selected series" => remove_series(doc)
end
