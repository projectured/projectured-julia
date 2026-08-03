"""
    ChartModule

The chart document domain: a `Chart` holds a list of data series, two axes, a
legend and a style. This file is **pure semantic content** — everything here
serializes. Transient view state (the zoom window, the hovered item, an
in-progress drag) lives on `ChartPlot` in `ChartPlot.jl`, which is projection
output, exactly as `GraphLayout` holds geometry outside `GraphGraph`.

Series data is held as whole column vectors, one reactive cell per column: a
column is bulk numeric leaf data, not navigable structure, so per-point cells
would cost ~88 bytes each and buy nothing. Reassigning a column is what makes a
chart repaint. Any `AbstractVector{<:Real}` works, so a data-frame column can be
handed straight to a series without this package depending on DataFrames.

Two axis families:
- **XY** (`ChartAxis` on x) carries `ChartLineSeries`, `ChartScatterSeries` and
  `ChartHistogramSeries`, which may be mixed on one chart.
- **Category** (`ChartCategoryAxis` on x) carries `ChartBarSeries`.
"""
module ChartModule

using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..ProjectionReferenceStepModule
using ..OperationModule
using ..SelectionModule
using ..EventPatternModule
using ..GestureBindingModule
using ..DomainModule

import ..ColorModule: StyleColor,
    color_solarized_blue, color_solarized_red, color_solarized_green,
    color_solarized_orange, color_solarized_violet, color_solarized_cyan,
    color_solarized_magenta, color_solarized_yellow
import ..ChartGeometryModule: bin_values

export ChartSeries, chart_series_family, chart_axis_family,
       default_color_cycle, default_symbol_cycle,
       series_color, series_symbol

@domain Chart

"""
Common supertype of every data series a `Chart` can hold.
"""
abstract type ChartSeries <: ChartDocument end

# ── Style ────────────────────────────────────────────────────────────────

"""
    default_color_cycle() -> Vector{StyleColor}

The per-series color cycle: the Solarized accents, in the order a chart hands
them out to series that leave `color` unset.
"""
default_color_cycle() = StyleColor[
    color_solarized_blue, color_solarized_red, color_solarized_green,
    color_solarized_orange, color_solarized_violet, color_solarized_cyan,
    color_solarized_magenta, color_solarized_yellow]

"""
    default_symbol_cycle() -> Vector{Symbol}

The per-series marker cycle. Only shapes the existing graphics primitives can
draw exactly appear here — a filled polygon primitive (diamond, triangle, star)
does not exist yet, and faking one out of line segments is not worth it.
"""
default_symbol_cycle() = Symbol[:circle, :square, :plus, :cross, :dot, :hline, :vline]

"""
Chart-wide visual style. Every field defaults, so `ChartStyle()` constructs and a
chart only names what it overrides. A `nothing` color/font means "take the
projection's theme default", resolved at print time rather than baked in here.

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
    color_cycle::Any = default_color_cycle()
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
`:solid`, `:dotted`, `:dashed` or `:dashdot`. A `nothing` `color` takes the next
entry of the chart's color cycle.
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

# Arity 2 with a keyword, so it never collides with the macro's arity-3
# `ChartHistogramSeries(label, binedges, binvalues)`.
function ChartHistogramSeries(label::AbstractString, values::AbstractVector; nbins::Integer=20)
    edges, counts = bin_values(values, nbins)
    ChartHistogramSeries(String(label), edges, counts)
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

# ── Family traits ────────────────────────────────────────────────────────

"""
    chart_series_family(series) -> :xy | :category | :unknown

Which axis family a series needs on x. The projection refuses to draw a series
whose family does not match the chart's x axis, and renders a diagnostic in its
place rather than throwing.
"""
chart_series_family(::Any) = :unknown
chart_series_family(::ChartLineSeries) = :xy
chart_series_family(::ChartScatterSeries) = :xy
chart_series_family(::ChartHistogramSeries) = :xy
chart_series_family(::ChartBarSeries) = :category

"""
    chart_axis_family(axis) -> :xy | :category | :unknown

The counterpart of [`chart_series_family`](@ref) for an x axis.
"""
chart_axis_family(::Any) = :unknown
chart_axis_family(::ChartAxis) = :xy
chart_axis_family(::ChartCategoryAxis) = :category

"""
    series_color(series, index, cycle) -> StyleColor

A series' own `color`, or the `index`-th entry of the chart's color cycle when
it left the field unset. Cycling is by position in the series list, so inserting
a series shifts the colors after it — the same rule OMNeT++'s native charts use.
"""
function series_color(color, index::Integer, cycle)
    color === nothing || return color
    isempty(cycle) && return color_solarized_blue
    cycle[mod1(index, length(cycle))]
end

"""
    series_symbol(symbol, index, cycle) -> Symbol

The marker shape for a series: its own `symbol` unless that is `:cycle`, in
which case the `index`-th entry of the style's symbol cycle.
"""
function series_symbol(symbol::Symbol, index::Integer, cycle)
    symbol === :cycle || return symbol
    isempty(cycle) && return :circle
    cycle[mod1(index, length(cycle))]
end

end # module
