# Fragment of `ChartModule`.
#
# ChartPlot → Graphics: the chart renderer. Everything a chart shows — the plot
# frame, gridlines, ticks and their labels, the axis titles, the series geometry —
# is composed here out of the existing graphics primitives. There is no plotting
# library underneath and no rasterization step; a chart is vector output like
# every other projection, so it stays selectable and resolution-independent.
#
# **Layout.** One computed cell (`geometry`) derives the whole frame from the
# chart, the view window and the available size: the data ranges, the plot
# rectangle, the tick positions and their measured labels. Axis margins fall out
# of measuring the labels, so the two-pass measure-then-remeasure dance a
# retained-mode toolkit needs does not arise — the margins are just a cell that
# depends on the ticks.
#
# **Cost.** Series geometry goes through `PlotGeometry.jl`'s `decimate_minmax`,
# so the number of graphics elements is bounded by the size of the plot
# rectangle rather than by the length of the columns. A million-sample series
# and a thousand-sample one produce the same amount of output at the same zoom.
#
# The plot area is a `GraphicsViewport` purely to clip; the data-to-pixel mapping
# is computed from the view window rather than carried as an affine transform, so
# zooming in re-derives ticks and decimation instead of magnifying pixels.
# ── Theme defaults ───────────────────────────────────────────────────────
# A `nothing` style field means "whatever the theme says"; these are that.

const _BACKGROUND = color_solarized_background_lighter
const _PLOT_BACKGROUND = StyleColor(1.0, 1.0, 1.0, 1.0)
const _AXIS = color_solarized_content_dark
const _GRID = StyleColor(0.0, 0.0, 0.0, 0.10)
const _TEXT = color_solarized_content_darker
const _SELECTION = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x60 / 255)
const _SELECTION_EDGE = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.9)
const _HOVER = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x28 / 255)

# Frame metrics, in logical pixels.
const _PAD = 8            # breathing room around the whole chart
const _TICK = 4           # length of a tick mark outside the plot frame
const _LABEL_GAP = 3      # between a tick mark and its label
const _TICK_TARGET_PX = 70   # aim for roughly one tick per this many pixels

_or(value, fallback) = value === nothing ? fallback : value

# Hovering one series fades the others, so the one under the pointer reads
# clearly without anything being hidden.
const _VEIL = 0.25

_veiled(color::StyleColor, on::Bool) =
    on ? StyleColor(color.red, color.green, color.blue, color.alpha * _VEIL) : color

# The colour a series draws in: its own or the cycle's, faded when some *other*
# series is being hovered.
function _draw_color(g, index::Int, own)
    color = get_series_color(own, index, g.style.color_cycle)
    _veiled(color, g.hovered_index != 0 && g.hovered_index != index)
end

"""
    ChartPlotToGraphicsCanvas(; measure, width=760, height=460)

The chart renderer. `measure(text, font) -> (w, h)` is how tick and title text
is sized; pass `measure_truetype_text` for a backend-free pipeline or
`measure_sdl_text` when running against a live SDL window.

`width`/`height` are the fallback canvas size, used when the printer context
carries no allocation from a parent layout.

A plain struct rather than an `@projection`: `measure` is a `Function`, and a
`Function` in a reactive field would be read as a thunk and called.
"""
struct ChartPlotToGraphicsCanvas <: Projection
    measure::Function
    width::Int
    height::Int
end

ChartPlotToGraphicsCanvas(; measure::Function, width::Integer=760, height::Integer=460) =
    ChartPlotToGraphicsCanvas(measure, Int(width), Int(height))

@iomap struct ChartPlotToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    geometry::Cell      # the laid-out frame: ranges, plot rect, scales, ticks
end

# ── Data ranges ──────────────────────────────────────────────────────────

# The visible series of a chart, paired with their position in the series list
# (the position, not the filtered index, is what drives the color cycle — hiding
# a series must not recolor the ones after it).
function _visible_series(chart::Chart)
    out = Tuple{Int,Any}[]
    for i in 1:length(chart.series)
        s = chart.series[i]
        s isa ChartSeries || continue
        s.visible || continue
        push!(out, (i, s))
    end
    out
end

_series_x_bounds(s::ChartLineSeries) = get_column_bounds(s.x)
_series_x_bounds(s::ChartScatterSeries) = get_column_bounds(s.x)
# A histogram spans its outermost edges, whatever the values do.
_series_x_bounds(s::ChartHistogramSeries) = get_column_bounds(s.binedges)
# A strip reaches past its last sample when it is told where the trace ends.
function _series_x_bounds(s::ChartStripSeries)
    b = get_column_bounds(s.x)
    (b === nothing || s.x_end === nothing) && return b
    (b[1], max(b[2], Float64(s.x_end)))
end
_series_x_bounds(::Any) = nothing

_series_y_bounds(s::ChartLineSeries) = get_column_bounds(s.y)
_series_y_bounds(s::ChartScatterSeries) = get_column_bounds(s.y)
# A strip has no y data of its own: which row it occupies depends on the other
# strips, so the extent is contributed by `_data_bounds` over the whole set.
_series_y_bounds(::Any) = nothing

# Histogram bars grow from zero, and the value shown is the transformed one, so
# the y extent has to be taken after the cumulative/density transform.
function _series_y_bounds(s::ChartHistogramSeries)
    vals = _histogram_shown_values(s)
    b = get_column_bounds(vals)
    b === nothing ? nothing : (min(b[1], 0.0), max(b[2], 0.0))
end

"""
    _histogram_shown_values(series) -> Vector{Float64}

The bin values as drawn: the raw counts put through whichever of the four
cumulative/density transforms the series selects, with the under/overflow weight
folded into the normalizing total so a CDF really reaches 1.
"""
function _histogram_shown_values(s::ChartHistogramSeries)
    values = s.binvalues
    total = sum(Float64(v) for v in values; init=0.0) + s.underflows + s.overflows
    compute_histogram_values(s.binedges, values; cumulative=s.cumulative, density=s.density, total)
end

# Which row each visible strip occupies, as the y coordinate of its centre. The
# first strip in the series list sits on top — the order the legend reads in —
# so k strips fill the integer rows k down to 1.
function _strip_rows(series, chart::Chart)
    rows = Dict{Int,Int}()
    # A strip on a category chart is never drawn, so it gets no row either —
    # otherwise its band would still be clickable with nothing in it.
    get_chart_axis_family(chart.x_axis) === :xy || return (rows, 0)
    indices = Int[i for (i, s) in series if s isa ChartStripSeries]
    k = length(indices)
    for (r, i) in enumerate(indices)
        rows[i] = k - r + 1
    end
    (rows, k)
end

# The data extent of everything drawn, before padding or axis overrides. Bar
# series live on a category axis, where x is the category index and y has to
# include the baseline the bars grow from.
function _data_bounds(series, chart::Chart)
    if get_chart_axis_family(chart.x_axis) === :category
        n = length(chart.x_axis.categories)
        yb = (chart.bar_baseline, chart.bar_baseline)
        if chart.bar_placement === :stacked
            yb = merge_bounds(yb, _stacked_bounds(series, n))
        else
            for (_, s) in series
                s isa ChartBarSeries || continue
                yb = merge_bounds(yb, get_column_bounds(s.values))
            end
        end
        return ((0.5, n + 0.5), yb)
    end
    xb = nothing; yb = nothing
    for (_, s) in series
        xb = merge_bounds(xb, _series_x_bounds(s))
        yb = merge_bounds(yb, _series_y_bounds(s))
    end
    # Strips claim integer rows rather than data values. The claim belongs here
    # rather than in the layout because the gesture readers resolve the window
    # through `resolve_view` as well, and a window the printer and the readers
    # disagreed about would jump under the first zoom.
    k = count(s -> s isa ChartStripSeries, (s for (_, s) in series))
    k > 0 && (yb = merge_bounds(yb, (0.5, k + 0.5)))
    (xb, yb)
end

# Stacked bars reach as high as the running sum in the tallest category, not as
# high as the tallest single series.
function _stacked_bounds(series, n::Integer)
    lo = 0.0; hi = 0.0
    for c in 1:n
        acc = 0.0
        for (_, s) in series
            s isa ChartBarSeries || continue
            c <= length(s.values) || continue
            v = Float64(s.values[c])
            isfinite(v) && (acc += abs(v))
        end
        hi = max(hi, acc)
    end
    (lo, hi)
end

# Fit the data, then let an explicitly pinned axis end override that end only.
function _fit_range(bounds, axis, fraction::Real)
    log = axis isa ChartAxis && axis.log
    lo, hi = bounds === nothing ? (0.0, 1.0) : bounds
    lo, hi = pad_range(lo, hi; fraction=fraction, log=log)
    if axis isa ChartAxis
        axis.min === nothing || (lo = Float64(axis.min))
        axis.max === nothing || (hi = Float64(axis.max))
    end
    hi > lo || (hi = lo + 1.0)
    (lo, hi)
end

"""
    resolve_view(plot) -> ChartView

The window currently shown: the plot's own `view`, or the auto-fit over the
visible data when it has none. Readers call this to materialize a concrete
window before zooming or panning relative to it.
"""
function resolve_view(plot::ChartPlot)
    v = plot.view
    v isa ChartView && return v
    chart = plot.chart
    chart isa Chart || return ChartView(0.0, 1.0, 0.0, 1.0)
    series = _visible_series(chart)
    xb, yb = _data_bounds(series, chart)
    # A category axis is already exactly as wide as its slots; padding it would
    # push half a category of empty space in at each end.
    x0, x1 = get_chart_axis_family(chart.x_axis) === :category ?
        (xb === nothing ? (0.5, 1.5) : xb) : _fit_range(xb, chart.x_axis, 0.02)
    y0, y1 = _fit_range(yb, chart.y_axis, 0.08)
    ChartView(x0, x1, y0, y1)
end

# ── Layout ───────────────────────────────────────────────────────────────

# Ticks for one axis over the visible window, at a density suited to the pixels
# the axis actually spans.
function _axis_ticks(axis, lo::Real, hi::Real, span_px::Real)
    target = clamp(round(Int, span_px / _TICK_TARGET_PX), 2, 12)
    (axis isa ChartAxis && axis.log) ? log_ticks(lo, hi) : compute_nice_ticks(lo, hi, target)
end

_tick_step(ticks) = length(ticks) >= 2 ? abs(ticks[2] - ticks[1]) : 0.0

_axis_title(axis) = axis isa ChartAxis || axis isa ChartCategoryAxis ? axis.title : ""
_axis_shows_title(axis) = (axis isa ChartAxis || axis isa ChartCategoryAxis) && axis.show_title
_axis_shows_labels(axis) = (axis isa ChartAxis || axis isa ChartCategoryAxis) && axis.show_labels
# Vertical gridlines through a category axis would just outline the slots the
# bars already fill, so a category axis carries no grid of its own.
_axis_grid(axis) = axis isa ChartAxis ? axis.grid : :none

# Ticks and their labels for the x axis. A numeric axis picks round numbers; a
# category axis puts one tick per slot and thins the labels to whatever fits,
# which is what keeps a ten-thousand-category axis from emitting ten thousand
# text elements.
function _x_ticks_labels(p::ChartPlotToGraphicsCanvas, axis, view, span_px, font)
    if axis isa ChartCategoryAxis
        cats = axis.categories
        n = length(cats)
        (n == 0 || !axis.show_labels) && return (Float64[], String[])
        widest = maximum((p.measure(String(c), font)[1] for c in cats); init=0)
        k = label_step(n, span_px, widest + _PAD)
        idx = [i for i in 1:k:n if view.x_min <= i <= view.x_max]
        (Float64.(idx), String[String(cats[i]) for i in idx])
    else
        ticks = _axis_ticks(axis, view.x_min, view.x_max, span_px)
        step = _tick_step(ticks)
        (ticks, _axis_shows_labels(axis) ? [format_tick(t, step) for t in ticks] : String[])
    end
end

# Which series a reference points into, or 0. Used for both the hover veil and
# the selection highlight; a `ChartPlot`-rooted reference (what the reader
# produces) and a `Chart`-rooted one (what the document holds) both resolve.
function _reference_series_index(chart::Chart, reference)
    reference === nothing && return 0
    n = length(chart.series)
    @reference_case reference begin
        ::ChartPlot.chart.series[i].rest... => (1 <= i <= n ? i : 0)
        ::Chart.series[i].rest... => (1 <= i <= n ? i : 0)
        __ => 0
    end
end

# ── Legend ───────────────────────────────────────────────────────────────

const _SWATCH = 14        # width of a legend item's colour sample
const _LEGEND_GAP = 6     # between swatch and label, and between columns
# A strip's own swatch: neutral, because the band is many colours and any one of
# them would misname the rest.
const _STRIP_SWATCH = StyleColor(0.5, 0.5, 0.5, 0.55)

_series_label(s) = hasproperty(s, :label) ? String(s.label) : ""

"""
    _legend_items(chart, series) -> Vector{Tuple{Int,String,Any}}

What the legend lists, as `(series_index, label, swatch_color)`.

A line, scatter, bar or histogram series is one entry in its own colour. A strip
is a *band* of colours, so a colour of its own would stand for nothing on the
chart: it takes a neutral swatch, and its colours are listed separately as the
states they actually mean. Strips sharing a state table share those entries.

The series come first and the states after them, rather than each strip's states
following it: sharing means a second strip on the same table lists none of its
own, and interleaved that reads as though the states belonged to the first strip
alone. Grouped, the first block is what is drawn and the second is what the
colours mean.

A zero index is an entry that names no series, which is what keeps a state entry
inert without the reader knowing about states: zero already reads as "inside the
legend but on nothing", so such an entry neither toggles nor hovers.
"""
function _legend_items(chart::Chart, series)
    cycle = chart.style.color_cycle
    items = Tuple{Int,String,Any}[]
    states = Tuple{Int,String,Any}[]
    for (index, s) in series
        if s isa ChartStripSeries
            push!(items, (index, _series_label(s), _STRIP_SWATCH))
            for code in 1:length(s.states)
                label = strip_state_name(s, code)
                color = strip_state_color(s, code, cycle)
                any(it -> it[2] == label && it[3] == color, states) && continue
                push!(states, (0, label, color))
            end
        else
            push!(items, (index, _series_label(s), get_series_color(s.color, index, cycle)))
        end
    end
    append!(items, states)
end

# The legend's items and the box that holds them, before it is positioned, in
# series order unless the legend asks for a dictionary sort.
function _legend_plan(p::ChartPlotToGraphicsCanvas, chart::Chart, series,
                      font::StyleFont, w::Int, h::Int)
    legend = chart.legend
    legend isa ChartLegend || return nothing
    legend.visible || return nothing
    items = _legend_items(chart, series)
    isempty(items) && return nothing
    legend.sort && sort!(items; by = it -> it[2])

    sizes = Tuple{Int,Int}[p.measure(it[2], font) for it in items]
    horizontal = legend.position in (:above, :below) ||
                 (legend.position === :inside && legend.anchor in (:north, :south))
    area_w = horizontal ? w - 2 * _PAD : w ÷ 3
    area_h = horizontal ? h ÷ 3 : h - 2 * _PAD
    box = compute_legend_layout(sizes; horizontal, area_w, area_h, swatch=_SWATCH,
                                gap=_LEGEND_GAP)
    (; position = legend.position, anchor = legend.anchor, border = legend.border,
       font, items, sizes, box, box_w = box.box_w, box_h = box.box_h,
       x = 0, y = 0)
end

# Put the box where `position` and `anchor` say. An outside legend is anchored
# within the strip already reserved for it; an inside one within the plot
# rectangle itself.
function _place_legend(plan, plot_x, plot_y, plot_w, plot_h, w, h, top, bottom, left, right)
    plan === nothing && return nothing
    bw, bh = plan.box_w, plan.box_h
    if plan.position === :inside
        dx, dy = get_anchor_offset(plan.anchor, plot_w - 2 * _PAD, plot_h - 2 * _PAD, bw, bh)
        x, y = plot_x + _PAD + dx, plot_y + _PAD + dy
    elseif plan.position === :above
        dx, _ = get_anchor_offset(plan.anchor, plot_w, bh, bw, bh)
        x, y = plot_x + dx, top - bh - _PAD
    elseif plan.position === :below
        dx, _ = get_anchor_offset(plan.anchor, plot_w, bh, bw, bh)
        x, y = plot_x + dx, h - bottom + _PAD
    elseif plan.position === :left
        _, dy = get_anchor_offset(plan.anchor, bw, plot_h, bw, bh)
        x, y = _PAD, plot_y + dy
    else
        _, dy = get_anchor_offset(plan.anchor, bw, plot_h, bw, bh)
        x, y = w - right + _PAD, plot_y + dy
    end
    merge(plan, (; x, y))
end

"""
    get_legend_item_rects(legend) -> Vector{Tuple{Int,Int,Int,Int,Int}}

Each drawn legend item as `(series_index, x, y, w, h)` in canvas coordinates —
what the printer draws into and what the reader hit-tests against, so the two
can never disagree about where an item is.
"""
function get_legend_item_rects(plan)
    out = Tuple{Int,Int,Int,Int,Int}[]
    plan === nothing && return out
    box = plan.box
    pad = 6
    for k in 1:min(box.shown, length(plan.items))
        col = (k - 1) ÷ box.rows
        row = (k - 1) % box.rows
        x = plan.x + pad + col * (box.col_w + _LEGEND_GAP)
        y = plan.y + pad + row * box.row_h
        push!(out, (plan.items[k][1], x, y, box.col_w, box.row_h))
    end
    out
end

function _legend_elements!(out, g)
    plan = g.legend
    plan === nothing && return out
    style = g.style
    text_color = _or(style.title_color, _TEXT)
    box = plan.box

    # Opaque, because a bordered rect paints the border colour underneath its
    # fill: a translucent legend background would take on the border's colour.
    push!(out, GraphicsRect(plan.x, plan.y, plan.box_w, plan.box_h;
                            color = _PLOT_BACKGROUND, radius = 3,
                            border_width = plan.border ? 1 : 0,
                            border_color = plan.border ? _AXIS : nothing))

    rects = get_legend_item_rects(plan)
    for (k, (index, x, y, item_w, row_h)) in enumerate(rects)
        _, label, color = plan.items[k]
        cy = y + row_h ÷ 2
        # The legend is where a selected or hovered series is called out: it is
        # the one place every series has a fixed, findable spot. An entry that
        # names no series has nothing to call out.
        if index != 0
            if index == g.selected_index
                push!(out, GraphicsRect(x - 3, y, item_w + 6, row_h; color = _SELECTION, radius = 3))
            elseif index == g.hovered_index
                push!(out, GraphicsRect(x - 3, y, item_w + 6, row_h; color = _HOVER, radius = 3))
            end
        end
        push!(out, GraphicsRect(x, cy - 4, _SWATCH, 8; color, radius = 2))
        th = plan.sizes[k][2]
        push!(out, GraphicsText(label, x + _SWATCH + _LEGEND_GAP, cy - th ÷ 2;
                                font = plan.font, color = text_color))
    end

    # Whatever did not fit is accounted for rather than silently dropped.
    if box.truncated
        hidden = length(plan.items) - box.shown
        col = box.shown ÷ box.rows
        row = box.shown % box.rows
        x = plan.x + 6 + col * (box.col_w + _LEGEND_GAP)
        y = plan.y + 6 + row * box.row_h
        push!(out, GraphicsText("… and $hidden more", x, y; font = plan.font, color = text_color))
    end
    out
end

# The whole frame in one pass: ranges, then ticks, then the margins the measured
# tick labels imply, then the plot rectangle and the two scales.
function _layout(p::ChartPlotToGraphicsCanvas, plot::ChartPlot, w::Int, h::Int)
    chart = plot.chart
    chart isa Chart || return nothing
    style = chart.style
    title_font = _or(style.title_font, font_ubuntu_bold_16)
    axis_font = _or(style.axis_font, font_ubuntu_regular_14)

    view = resolve_view(plot)
    x_axis, y_axis = chart.x_axis, chart.y_axis
    series = _visible_series(chart)

    title = chart.title
    title_h = isempty(title) ? 0 : p.measure(title, title_font)[2] + _PAD ÷ 2

    y_title = _axis_shows_title(y_axis) ? _axis_title(y_axis) : ""
    y_title_h = isempty(y_title) ? 0 : p.measure(y_title, axis_font)[2] + 2
    x_title = _axis_shows_title(x_axis) ? _axis_title(x_axis) : ""
    x_title_h = isempty(x_title) ? 0 : p.measure(x_title, axis_font)[2] + 2

    # Provisional plot extent, used only to pick a tick density. The ticks then
    # decide the real margins, and those give the final extent.
    prov_w = max(w - 2 * _PAD - 60, 40)
    prov_h = max(h - 2 * _PAD - title_h - y_title_h - x_title_h - 24, 40)

    # Row-label mode: when the chart is nothing but strips, the y axis is the
    # list of strips, so it carries their labels instead of numbers. Any other
    # series visible — or none at all — and the numeric path runs untouched.
    strip_rows, strip_count = _strip_rows(series, chart)
    strip_only = strip_count >= 1 && all(s -> s isa ChartStripSeries, (s for (_, s) in series))

    if strip_only
        yticks = Float64[Float64(strip_rows[i]) for (i, _) in series]
        ylabels = _axis_shows_labels(y_axis) ? [_series_label(s) for (_, s) in series] : String[]
    else
        yticks = _axis_ticks(y_axis, view.y_min, view.y_max, prov_h)
        ylabels = _axis_shows_labels(y_axis) ?
            [format_tick(t, _tick_step(yticks)) for t in yticks] : String[]
    end
    xticks, xlabels = _x_ticks_labels(p, x_axis, view, prov_w, axis_font)

    # Measure each label once, here, and carry the sizes forward — the frame
    # needs them again when it places the text.
    ysizes = Tuple{Int,Int}[p.measure(l, axis_font) for l in ylabels]
    xsizes = Tuple{Int,Int}[p.measure(l, axis_font) for l in xlabels]
    label_h = p.measure("0", axis_font)[2]
    ylabel_w = isempty(ysizes) ? 0 : maximum(sz[1] for sz in ysizes)
    xlabel_last_w = isempty(xsizes) ? 0 : last(xsizes)[1]

    left = _PAD + ylabel_w + (isempty(ylabels) ? 0 : _LABEL_GAP) + _TICK
    right = _PAD + xlabel_last_w ÷ 2
    top = _PAD + title_h + y_title_h
    bottom = _PAD + x_title_h + (isempty(xlabels) ? 0 : label_h + _LABEL_GAP) + _TICK

    # An outside legend reserves a strip, shrinking the plot; an inside one
    # overlays it and takes nothing.
    legend = _legend_plan(p, chart, series, axis_font, w, h)
    if legend !== nothing && legend.position !== :inside
        legend.position === :above && (top += legend.box_h + _PAD)
        legend.position === :below && (bottom += legend.box_h + _PAD)
        legend.position === :left && (left += legend.box_w + _PAD)
        legend.position === :right && (right += legend.box_w + _PAD)
    end

    plot_x = left
    plot_y = top
    plot_w = max(w - left - right, 20)
    plot_h = max(h - top - bottom, 20)
    legend = _place_legend(legend, plot_x, plot_y, plot_w, plot_h, w, h, top, bottom, left, right)

    xlog = x_axis isa ChartAxis && x_axis.log
    ylog = y_axis isa ChartAxis && y_axis.log
    xs = AxisScale(view.x_min, view.x_max, plot_x, plot_x + plot_w; log=xlog)
    ys = AxisScale(view.y_min, view.y_max, plot_y + plot_h, plot_y; log=ylog)

    hovered_index = _reference_series_index(chart, plot.hovered)
    selected_index = _reference_series_index(chart, chart.selection)
    selected_part = get_chart_part_index(chart, chart.selection)
    whole_selected = chart.selection isa EmptyReference

    measure_label = label -> p.measure(label, axis_font)
    # Decimated series geometry is wanted by the printer once per repaint and by
    # the reader on every pointer move, so it is memoized here — inside the
    # layout, which already dies and is rebuilt whenever the data, the window or
    # the size changes.
    point_cache = Dict{Int,Vector{Tuple{Int,Int}}}()
    # Strip spans, computed here rather than on demand: see `_strip_spans`.
    strip_spans = Dict{Int,Vector{Tuple{Int,Int,Int}}}(
        i => _compute_strip_spans(xs, view, s)
        for (i, s) in series if s isa ChartStripSeries && haskey(strip_rows, i))

    (; w, h, chart, style, view, series, legend,
       hovered_index, selected_index, selected_part, whole_selected,
       measure_label,
       plot_x, plot_y, plot_w, plot_h, xs, ys,
       point_cache, strip_spans, strip_rows, strip_count, strip_only,
       xticks, yticks, xlabels, ylabels, xsizes, ysizes, label_h,
       title, title_font, axis_font, title_h,
       x_title, y_title, x_title_h, y_title_h)
end

# ── Frame elements ───────────────────────────────────────────────────────

function _frame_elements!(out, g)
    style = g.style
    grid_color = _or(style.grid_color, _GRID)
    text_color = _or(style.title_color, _TEXT)
    px, py, pw, ph = g.plot_x, g.plot_y, g.plot_w, g.plot_h

    push!(out, GraphicsRect(0, 0, g.w, g.h; color = _or(style.background, _BACKGROUND)))
    push!(out, GraphicsRect(px, py, pw, ph; color = _or(style.plot_background, _PLOT_BACKGROUND)))

    chart = g.chart
    grid_x = _axis_grid(chart.x_axis)
    grid_y = _axis_grid(chart.y_axis)

    # In row-label mode the y ticks name the strips rather than measuring
    # anything, so a gridline through each would just underline the bands.
    if grid_y !== :none && !g.strip_only
        for t in g.yticks
            y = round(Int, to_pixel(g.ys, t))
            (py <= y <= py + ph) || continue
            push!(out, GraphicsLine(px, y, px + pw, y; color = grid_color, dash=(2, 3)))
        end
    end
    if grid_x !== :none
        for t in g.xticks
            x = round(Int, to_pixel(g.xs, t))
            (px <= x <= px + pw) || continue
            push!(out, GraphicsLine(x, py, x, py + ph; color = grid_color, dash=(2, 3)))
        end
    end

    # The two axis lines, drawn over the grid.
    push!(out, GraphicsLine(px, py + ph, px + pw, py + ph; color = _AXIS))
    push!(out, GraphicsLine(px, py, px, py + ph; color = _AXIS))

    # Tick marks and their labels.
    for i in eachindex(g.ylabels)
        y = round(Int, to_pixel(g.ys, g.yticks[i]))
        (py - 1 <= y <= py + ph + 1) || continue
        push!(out, GraphicsLine(px - _TICK, y, px, y; color = _AXIS))
        tw, th = g.ysizes[i]
        push!(out, GraphicsText(g.ylabels[i], px - _TICK - _LABEL_GAP - tw, y - th ÷ 2;
                                font = g.axis_font, color = text_color))
    end
    for i in eachindex(g.xlabels)
        x = round(Int, to_pixel(g.xs, g.xticks[i]))
        (px - 1 <= x <= px + pw + 1) || continue
        push!(out, GraphicsLine(x, py + ph, x, py + ph + _TICK; color = _AXIS))
        tw, _ = g.xsizes[i]
        push!(out, GraphicsText(g.xlabels[i], x - tw ÷ 2, py + ph + _TICK + _LABEL_GAP;
                                font = g.axis_font, color = text_color))
    end

    _selection_elements!(out, g)

    isempty(g.title) ||
        push!(out, GraphicsText(g.title, px, _PAD; font = g.title_font, color = text_color))
    # No rotated text: the backends only honour the translate+scale subset of an
    # affine transform, so the y-axis title sits above the axis rather than
    # running up its side.
    isempty(g.y_title) ||
        push!(out, GraphicsText(g.y_title, px, _PAD + g.title_h; font = g.axis_font, color = text_color))
    isempty(g.x_title) ||
        push!(out, GraphicsText(g.x_title, px + pw ÷ 2, g.h - _PAD - g.x_title_h + 2;
                                font = g.axis_font, color = text_color))
    out
end

# What a selection looks like. Every part of a chart is a document that can be
# selected, so every part has a region the projection can call out — the title's
# line, either axis' label strip, the legend's box, a series' legend row — and
# the whole chart gets a frame of its own.
function _selection_elements!(out, g)
    px, py, pw, ph = g.plot_x, g.plot_y, g.plot_w, g.plot_h
    if g.whole_selected
        _outline!(out, 1, 1, g.w - 2, g.h - 2)
        return out
    end
    part = g.selected_part
    if part == 1 && !isempty(g.title)
        tw, th = g.measure_label(g.title)
        push!(out, GraphicsRect(px - 3, _PAD - 2, tw + 6, g.title_h + 2; color = _SELECTION, radius = 3))
    elseif part == 2
        push!(out, GraphicsRect(px, py + ph + _TICK, pw, g.h - (py + ph + _TICK) - _PAD ÷ 2;
                                color = _SELECTION, radius = 3))
    elseif part == 3
        push!(out, GraphicsRect(_PAD ÷ 2, py, px - _TICK - _PAD ÷ 2, ph; color = _SELECTION, radius = 3))
    elseif part == 4 && g.legend !== nothing
        plan = g.legend
        _outline!(out, plan.x - 3, plan.y - 3, plan.box_w + 6, plan.box_h + 6)
    end
    out
end

# An outline drawn as its four edges. A rect with a border paints the border
# colour across the whole shape and insets the fill on top, so it cannot express
# "outline only" over content that has to stay visible.
function _outline!(out, x::Integer, y::Integer, w::Integer, h::Integer)
    push!(out, GraphicsLine(x, y, x + w, y; color = _SELECTION_EDGE, width=2))
    push!(out, GraphicsLine(x, y + h, x + w, y + h; color = _SELECTION_EDGE, width=2))
    push!(out, GraphicsLine(x, y, x, y + h; color = _SELECTION_EDGE, width=2))
    push!(out, GraphicsLine(x + w, y, x + w, y + h; color = _SELECTION_EDGE, width=2))
    out
end

# ── Series elements ──────────────────────────────────────────────────────

# A line style as the primitive's (on, off) pixel pattern. `:dashdot` would need
# a four-element pattern, which the primitive does not carry, so it is not among
# the styles offered; anything unrecognised draws solid.
_dash_pattern(style::Symbol) =
    style === :dotted ? (1, 3) :
    style === :dashed ? (6, 4) : nothing

# Marker shapes. The straight-edged ones are filled polygons; the rest are the
# primitives whose shape they already are.
function _marker!(out, shape::Symbol, x::Int, y::Int, size::Int, color::StyleColor)
    r = max(size ÷ 2, 1)
    polygon = build_marker_polygon(shape, x, y, r)
    if polygon !== nothing
        push!(out, GraphicsPolygon(polygon; color))
    elseif shape === :circle
        push!(out, GraphicsCircle(x, y, r; color))
    elseif shape === :dot
        push!(out, GraphicsCircle(x, y, max(r ÷ 2, 1); color))
    elseif shape === :square
        push!(out, GraphicsRect(x - r, y - r, 2r, 2r; color))
    elseif shape === :plus
        push!(out, GraphicsLine(x - r, y, x + r, y; color))
        push!(out, GraphicsLine(x, y - r, x, y + r; color))
    elseif shape === :cross
        push!(out, GraphicsLine(x - r, y - r, x + r, y + r; color))
        push!(out, GraphicsLine(x - r, y + r, x + r, y - r; color))
    elseif shape === :hline
        push!(out, GraphicsLine(x - r, y, x + r, y; color))
    elseif shape === :vline
        push!(out, GraphicsLine(x, y - r, x, y + r; color))
    end
    out
end

# Pixel points for a line series over the visible window, already decimated and
# translated into the viewport's local frame.
function _line_points(g, s::ChartLineSeries)
    x, y = s.x, s.y
    (length(x) == 0 || length(y) == 0) && return Tuple{Int,Int}[]
    i0, i1 = get_visible_range(x, g.view.x_min, g.view.x_max; sorted=s.sorted)
    pts = decimate_minmax(x, y; xs=g.xs, ys=g.ys, i0, i1)
    ox, oy = g.plot_x, g.plot_y
    [(px - ox, py - oy) for (px, py) in pts]
end

function _line_elements!(out, g, index::Int, s::ChartLineSeries)
    style = g.style
    color = _draw_color(g, index, s.color)
    pts = _series_points(g, index, s)
    isempty(pts) && return out

    if s.draw_style === :pins
        baseline = round(Int, to_pixel(g.ys, 0.0)) - g.plot_y
        for (x, ytop, ybot) in build_pins_segments(pts, baseline)
            push!(out, GraphicsLine(x, ytop, x, ybot; color, width=max(s.line_width, 1),
                                    dash=_dash_pattern(s.line_style)))
        end
    elseif s.draw_style !== :none
        shaped = s.draw_style === :linear ? pts : step_points(pts, s.draw_style)
        length(shaped) >= 2 &&
            push!(out, GraphicsPolyline(shaped; color, width=max(s.line_width, 1),
                                        dash=_dash_pattern(s.line_style)))
    end

    shape = get_series_symbol(s.symbol, index, style.symbol_cycle)
    # Markers only while they still read as individual points; past that they
    # merge into a smear and the line already carries the shape.
    if shape !== :none && length(pts) <= style.marker_limit
        for (x, y) in pts
            _marker!(out, shape, x, y, s.symbol_size, color)
        end
    end
    out
end

# ── Scatter ──────────────────────────────────────────────────────────────

# Two ways to draw a cloud, chosen by how crowded it is. Below the fold
# threshold each point gets a marker, deduplicated per pixel so overlapping
# samples do not each cost an element. Above it the individual points stopped
# being distinguishable anyway, so the cloud folds into a density grid: one
# shaded cell per occupied bin, alpha carrying the count.
function _scatter_elements!(out, g, index::Int, s::ChartScatterSeries)
    style = g.style
    color = _draw_color(g, index, s.color)
    n = min(length(s.x), length(s.y))
    n == 0 && return out
    ox, oy = g.plot_x, g.plot_y

    if n > style.scatter_fold_threshold
        cell = max(style.bin_fold_px + 1, 3)
        bands = fold_scatter(s.x, s.y; xs=g.xs, ys=g.ys, cell_px=cell, i0=1, i1=n, levels=_DENSITY_LEVELS)
        for (px, py, bw, bh, level) in bands
            a = 0.15 + 0.85 * level / _DENSITY_LEVELS
            shade = StyleColor(color.red, color.green, color.blue, color.alpha * a)
            push!(out, GraphicsRect(px - ox, py - oy, bw, bh; color = shade))
        end
        return out
    end

    shape = get_series_symbol(s.symbol, index, style.symbol_cycle)
    shape === :none && return out
    seen = Set{Tuple{Int,Int}}()
    @inbounds for i in 1:n
        xv = Float64(s.x[i]); yv = Float64(s.y[i])
        (isfinite(xv) && isfinite(yv)) || continue
        px = round(Int, to_pixel(g.xs, xv)) - ox
        py = round(Int, to_pixel(g.ys, yv)) - oy
        (px, py) in seen && continue
        push!(seen, (px, py))
        _marker!(out, shape, px, py, s.symbol_size, color)
    end
    out
end

# ── Bars ─────────────────────────────────────────────────────────────────

# Where each series' bar sits within a category slot, per placement mode:
# `:aligned` splits the slot into one sub-slot per series, `:overlap` steps them
# by half a bar so each stays partly visible, and `:infront`/`:stacked` give
# every series the full slot (they are separated by draw order and by height).
function _bar_geometry(placement::Symbol, slot_w::Float64, count::Int, j::Int)
    usable = slot_w * 0.8
    if placement === :aligned
        w = usable / max(count, 1)
        (-usable / 2 + (j - 1) * w, w)
    elseif placement === :overlap
        w = usable / (1 + (count - 1) * 0.5)
        (-usable / 2 + (j - 1) * w * 0.5, w)
    else
        (-usable / 2, usable)
    end
end

function _bar_elements!(out, g, bar_series)
    chart = g.chart
    style = g.style
    axis = chart.x_axis
    n = length(axis.categories)
    (n == 0 || isempty(bar_series)) && return out
    ox, oy = g.plot_x, g.plot_y
    baseline = to_pixel(g.ys, chart.bar_baseline) - oy
    slot_w = abs(to_pixel(g.xs, 2.0) - to_pixel(g.xs, 1.0))
    placement = chart.bar_placement
    count = length(bar_series)

    # Sub-pixel slots: the individual bars are no longer resolvable, so each
    # series collapses to an envelope over the categories that share a column.
    if slot_w < style.bin_fold_px
        for (index, s) in bar_series
            color = _draw_color(g, index, s.color)
            lefts = Int[round(Int, to_pixel(g.xs, c - 0.5)) - ox for c in 1:n]
            rights = Int[round(Int, to_pixel(g.xs, c + 0.5)) - ox for c in 1:n]
            vals = Float64[c <= length(s.values) ? Float64(s.values[c]) : 0.0 for c in 1:n]
            for (l, r, lo, hi) in fold_bins(lefts, rights, vals; min_px = style.bin_fold_px)
                ylo = to_pixel(g.ys, hi) - oy
                yhi = to_pixel(g.ys, lo) - oy
                push!(out, GraphicsRect(l, round(Int, min(ylo, yhi)), max(r - l, 1),
                                        max(round(Int, abs(yhi - ylo)), 1); color))
            end
        end
        return out
    end

    # Later series are drawn first so the earlier ones end up in front, which is
    # what makes the overlap and in-front placements read correctly.
    order = placement in (:overlap, :infront) ? reverse(1:count) : (1:count)
    stack = zeros(Float64, n)
    for j in order
        index, s = bar_series[j]
        color = _draw_color(g, index, s.color)
        dx, bw = _bar_geometry(placement, slot_w, count, j)
        for c in 1:n
            c <= length(s.values) || continue
            v = Float64(s.values[c])
            isfinite(v) || continue
            centre = to_pixel(g.xs, Float64(c)) - ox
            if placement === :stacked
                base = to_pixel(g.ys, chart.bar_baseline + stack[c]) - oy
                stack[c] += abs(v)
                top = to_pixel(g.ys, chart.bar_baseline + stack[c]) - oy
            else
                base = baseline
                top = to_pixel(g.ys, v) - oy
            end
            x = round(Int, centre + dx)
            y0, y1 = min(base, top), max(base, top)
            push!(out, GraphicsRect(x, round(Int, y0), max(round(Int, bw), 1),
                                    max(round(Int, y1 - y0), 1); color))
        end
    end

    # The reference line bars grow from, drawn over them so it stays readable.
    bl = round(Int, baseline)
    if 0 <= bl <= g.plot_h
        push!(out, GraphicsLine(0, bl, g.plot_w, bl;
                                color = _or(chart.bar_baseline_color, _AXIS)))
    end
    out
end

# ── Histograms ───────────────────────────────────────────────────────────

function _histogram_elements!(out, g, index::Int, s::ChartHistogramSeries)
    style = g.style
    color = _draw_color(g, index, s.color)
    edges = s.binedges
    values = _histogram_shown_values(s)
    n = min(length(values), length(edges) - 1)
    n >= 1 || return out
    ox, oy = g.plot_x, g.plot_y
    baseline = round(Int, to_pixel(g.ys, 0.0) - oy)

    lefts = Int[round(Int, to_pixel(g.xs, Float64(edges[i]))) - ox for i in 1:n]
    rights = Int[round(Int, to_pixel(g.xs, Float64(edges[i+1]))) - ox for i in 1:n]
    bars = fold_bins(lefts, rights, Float64.(values[1:n]); min_px = style.bin_fold_px)

    if s.draw === :outline
        # A silhouette instead of filled cells: several overlaid histograms stay
        # readable, which is the whole point of the outline mode.
        pts = Tuple{Int,Int}[]
        for (l, r, _, hi) in bars
            y = round(Int, to_pixel(g.ys, hi) - oy)
            push!(pts, (l, y)); push!(pts, (r, y))
        end
        if !isempty(pts)
            pushfirst!(pts, (first(bars)[1], baseline))
            push!(pts, (last(bars)[2], baseline))
            push!(out, GraphicsPolyline(pts; color, width=2))
        end
    else
        for (l, r, lo, hi) in bars
            ytop = to_pixel(g.ys, hi) - oy
            ybot = to_pixel(g.ys, lo == hi ? 0.0 : lo) - oy
            y0, y1 = min(ytop, ybot, baseline), max(ytop, ybot, baseline)
            push!(out, GraphicsRect(l, round(Int, y0), max(r - l, 1),
                                    max(round(Int, y1 - y0), 1); color,
                                    border_width=1, border_color=_AXIS))
        end
    end

    # Under/overflow cells span from the axis edge to the outermost bin, drawn
    # translucent so they read as "everything beyond here" rather than as data.
    if s.show_overflow
        faint = StyleColor(color.red, color.green, color.blue, color.alpha * 0.5)
        if s.underflows > 0
            l = round(Int, to_pixel(g.xs, g.view.x_min)) - ox
            r = first(lefts)
            y = round(Int, to_pixel(g.ys, s.underflows) - oy)
            r > l && push!(out, GraphicsRect(l, min(y, baseline), r - l,
                                             max(abs(baseline - y), 1); color = faint))
        end
        if s.overflows > 0
            l = last(rights)
            r = round(Int, to_pixel(g.xs, g.view.x_max)) - ox
            y = round(Int, to_pixel(g.ys, s.overflows) - oy)
            r > l && push!(out, GraphicsRect(l, min(y, baseline), r - l,
                                             max(abs(baseline - y), 1); color = faint))
        end
    end
    out
end

# ── Strips ───────────────────────────────────────────────────────────────
#
# A strip draws one filled rect per run of equal values, from each sample's time
# to the next one's — a value holds until something replaces it. The band, its
# drawn right edge and the pixel spans are all computed here and used by both the
# printer and the hit-testing, so what is drawn and what is clickable cannot
# drift apart.

# Half the height of a band, in rows. Bands are placed in data coordinates so
# they scale with a y zoom like everything else.
const _STRIP_HALF = 0.4
const _STRIP_EDGE = StyleColor(0.0, 0.0, 0.0, 0.10)

# The band a strip occupies, in absolute pixels, or `nothing` when the series
# has no row — hidden, or not a strip at all.
function _strip_band(g, index::Int)
    center = get(g.strip_rows, index, 0)
    center == 0 && return nothing
    a = to_pixel(g.ys, center + _STRIP_HALF)
    b = to_pixel(g.ys, center - _STRIP_HALF)
    (round(Int, min(a, b)), round(Int, max(a, b)))
end

# Where the last segment stops: the trace's own end when it has one, otherwise
# the edge of the view — a state with nothing after it is still in effect.
_strip_end(s::ChartStripSeries, view) =
    s.x_end === nothing ? view.x_max : Float64(s.x_end)

"""
    _strip_spans(g, index) -> Vector{Tuple{Int,Int,Int}}

The `(left, right, code)` pixel spans a strip draws over the visible window:
clipped to the window, runs of equal values coalesced, and sub-pixel runs folded
to whichever state holds them longest. Absolute pixels, bounded by the plot
width no matter how long the columns are.

Computed once in the layout rather than on demand. Walking the visible index
range is the whole column when the chart is zoomed out, and both the printer and
the overlay want the result on every repaint — which is every pointer move,
since the crosshair reads the cursor. Doing it in the layout is also what makes
the reactivity right: the layout reads the value column, so replacing that
column rebuilds the layout, where a cache filled on demand would have gone stale
behind an unchanged one. (Strips contribute no y bounds, so nothing else in the
layout reads `values`.)
"""
const _NO_SPANS = Tuple{Int,Int,Int}[]

_strip_spans(g, index::Int) = get(g.strip_spans, index, _NO_SPANS)

function _compute_strip_spans(xs::AxisScale, view, s::ChartStripSeries)
    x, values = s.x, s.values
    n = min(length(x), length(values))
    n >= 1 || return Tuple{Int,Int,Int}[]
    i0, i1 = get_visible_range(x, view.x_min, view.x_max)
    i1 = min(i1, n)
    i0 > i1 && return Tuple{Int,Int,Int}[]
    runs = strip_runs(values, i0, i1)
    isempty(runs) && return Tuple{Int,Int,Int}[]
    drawn_end = _strip_end(s, view)
    lefts = Vector{Float64}(undef, length(runs))
    rights = Vector{Float64}(undef, length(runs))
    codes = Vector{Int}(undef, length(runs))
    for (k, (a, b)) in enumerate(runs)
        lefts[k] = to_pixel(xs, Float64(x[a]))
        rights[k] = b < n ? to_pixel(xs, Float64(x[b + 1])) : to_pixel(xs, drawn_end)
        codes[k] = Int(values[a])
    end
    fold_strips(lefts, rights, codes; min_px = 1)
end

# Enough contrast to read a state name against whatever colour that state took.
_strip_label_color(color::StyleColor) =
    (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) > 0.55 ?
    _TEXT : StyleColor(1.0, 1.0, 1.0, 1.0)

function _strip_elements!(out, g, index::Int, s::ChartStripSeries)
    band = _strip_band(g, index)
    band === nothing && return out
    top, bottom = band
    ox, oy = g.plot_x, g.plot_y
    height = max(bottom - top, 1)
    spans = _strip_spans(g, index)
    cycle = g.style.color_cycle
    veiled = g.hovered_index != 0 && g.hovered_index != index

    for (l, r, code) in spans
        color = _veiled(strip_state_color(s, code, cycle), veiled)
        push!(out, s.draw_edges ?
            GraphicsRect(l - ox, top - oy, max(r - l, 1), height; color,
                         border_width=1, border_color=_STRIP_EDGE) :
            GraphicsRect(l - ox, top - oy, max(r - l, 1), height; color))
    end

    # A state names itself inside its own segment when the name fits. No
    # rotation: the backends only honour the translate+scale subset of an affine
    # transform, so a name that does not fit is left out rather than turned.
    if s.show_labels
        for (l, r, code) in spans
            name = strip_state_name(s, code)
            isempty(name) && continue
            tw, th = g.measure_label(name)
            (tw + 6 <= r - l && th + 2 <= height) || continue
            color = strip_state_color(s, code, cycle)
            push!(out, GraphicsText(name, l - ox + (r - l - tw) ÷ 2,
                                    top - oy + (height - th) ÷ 2;
                                    font = g.axis_font, color = _strip_label_color(color)))
        end
    end
    out
end

# ── Overlay ──────────────────────────────────────────────────────────────
#
# What is drawn over the series inside the plot viewport: the crosshair with its
# value readout, and the rubber band while a zoom drag is in progress.

const _CROSSHAIR = StyleColor(0xdc / 255, 0x32 / 255, 0x2f / 255, 0.7)
const _BAND_FILL = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x30 / 255)

# The data point nearest the cursor, within a small halo, so the readout snaps to
# real samples instead of reporting wherever the pointer happens to be. The
# search is over already-decimated geometry, so it costs pixels, not samples.
function _snap_point(g, lx::Int, ly::Int)
    best = nothing; best_d = _HIT_TOLERANCE^2 * 4
    for (index, s) in g.series
        get_chart_series_family(s) === get_chart_axis_family(g.chart.x_axis) || continue
        for (px, py) in _hit_points(g, index, s)
            d = (px - lx)^2 + (py - ly)^2
            d <= best_d && (best_d = d; best = (index, px, py))
        end
    end
    best
end

function _overlay_elements!(out, g, plot::ChartPlot)
    rect = plot.drag_rect
    if rect !== nothing
        rx, ry, rw, rh = rect
        # Fill only, no border: a bordered rect is drawn as the border colour
        # with the fill inset on top of it, so a translucent fill would show the
        # border colour through the whole band rather than around it.
        push!(out, GraphicsRect(rx - g.plot_x, ry - g.plot_y, max(rw, 1), max(rh, 1);
                                color = _BAND_FILL))
    end

    # The selected sample, called out whether or not the pointer is near it.
    # Which callout is the series type's business, not the sample value's: a
    # histogram bin is a triple too, and rings nothing.
    sample = get_selected_sample(g.chart)
    if sample !== nothing
        series = g.chart.series[sample[1]]
        if series isa ChartStripSeries
            _selected_strip!(out, g, sample[1], series, sample[2])
        else
            point = get_chart_sample(series, sample[2])
            if point isa Tuple && length(point) == 2
                sx = round(Int, to_pixel(g.xs, point[1])) - g.plot_x
                sy = round(Int, to_pixel(g.ys, point[2])) - g.plot_y
                color = get_series_color(series.color, sample[1], g.style.color_cycle)
                push!(out, GraphicsCircle(sx, sy, 6; color = color_transparent,
                                          border_width=2, border_color=_SELECTION_EDGE))
                push!(out, GraphicsCircle(sx, sy, 3; color))
            end
        end
    end

    cursor = plot.cursor
    cursor === nothing && return out
    cx = round(Int, to_pixel(g.xs, cursor[1])) - g.plot_x
    cy = round(Int, to_pixel(g.ys, cursor[2])) - g.plot_y
    push!(out, GraphicsLine(cx, 0, cx, g.plot_h; color = _CROSSHAIR, dash=(3, 3)))
    push!(out, GraphicsLine(0, cy, g.plot_w, cy; color = _CROSSHAIR, dash=(3, 3)))

    snapped = _snap_point(g, cx, cy)
    text_color = _or(g.style.title_color, _TEXT)
    if snapped === nothing
        # Inside a band, the y coordinate is a row number and reading it back as
        # a value would be meaningless — the state holding there is the answer.
        strip = _strip_readout(g, cursor[1], cy + g.plot_y)
        label = strip === nothing ?
            string(format_tick(cursor[1]), ", ", format_tick(cursor[2])) : strip
        push!(out, GraphicsText(label, cx + 6, cy - 18; font = g.axis_font, color = text_color))
        return out
    end

    index, px, py = snapped
    color = get_series_color(g.chart.series[index].color, index, g.style.color_cycle)
    push!(out, GraphicsCircle(px, py, 4; color, border_width=1, border_color=_PLOT_BACKGROUND))
    label = string(_series_label(g.chart.series[index]), "  ",
                   format_tick(to_data(g.xs, px + g.plot_x)), ", ",
                   format_tick(to_data(g.ys, py + g.plot_y)))
    # Flip the readout to the other side of the cursor near the right edge so it
    # is never clipped away by the viewport.
    tw, th = g.measure_label(label)
    lx = px + tw + 12 > g.plot_w ? px - tw - 8 : px + 8
    push!(out, GraphicsRect(lx - 4, py - th - 8, tw + 8, th + 6;
                            color = _PLOT_BACKGROUND, radius = 3, border_width=1, border_color=_AXIS))
    push!(out, GraphicsText(label, lx, py - th - 5; font = g.axis_font, color = text_color))
    out
end

# The selected segment, outlined where it is actually drawn: the span it folded
# into if it folded, and out to the drawn end if it is the last one.
# `get_chart_sample` keeps reporting the extent in the data, which does not move
# with the zoom, so the two deliberately differ.
function _selected_strip!(out, g, index::Int, s::ChartStripSeries, k::Integer)
    band = _strip_band(g, index)
    band === nothing && return out
    n = min(length(s.x), length(s.values))
    (1 <= k <= n) || return out
    left = round(Int, to_pixel(g.xs, Float64(s.x[k])))
    right = round(Int, k < n ? to_pixel(g.xs, Float64(s.x[k + 1])) :
                       to_pixel(g.xs, _strip_end(s, g.view)))
    for (sl, sr, _) in _strip_spans(g, index)
        if sl <= left < sr
            left, right = sl, sr
            break
        end
    end
    _outline!(out, left - g.plot_x, band[1] - g.plot_y,
              max(right - left, 1), max(band[2] - band[1], 1))
end

# What the pointer is over inside a band: the strip and the state holding at
# that moment, which is what a strip is read for.
function _strip_readout(g, at::Real, y::Integer)
    for (index, s) in g.series
        s isa ChartStripSeries || continue
        band = _strip_band(g, index)
        band === nothing && continue
        (band[1] <= y <= band[2]) || continue
        k = _strip_sample_at(g, s, at)
        k === nothing && continue
        return string(_series_label(s), "  ", strip_state_name(s, s.values[k]),
                      " @ ", format_tick(Float64(at)))
    end
    nothing
end

_series_elements!(out, g, index::Int, s::ChartLineSeries) = _line_elements!(out, g, index, s)
_series_elements!(out, g, index::Int, s::ChartScatterSeries) = _scatter_elements!(out, g, index, s)
_series_elements!(out, g, index::Int, s::ChartHistogramSeries) = _histogram_elements!(out, g, index, s)
_series_elements!(out, g, index::Int, s::ChartStripSeries) = _strip_elements!(out, g, index, s)
# Bar series are drawn as a group rather than one at a time: how wide a bar is
# and where in its slot it sits both depend on how many other bar series there
# are, so `_bar_elements!` takes the whole set.
_series_elements!(out, g, ::Int, ::Any) = out

# ── Printer ──────────────────────────────────────────────────────────────

# Canvas size: whatever a parent layout allocated, else the projection's own
# fallback. Reading the cells here registers the dependency, so a resize
# reflows without re-projecting.
function _canvas_size(p::ChartPlotToGraphicsCanvas, ctx)
    aw = ctx === nothing ? nothing : ctx.available_width
    ah = ctx === nothing ? nothing : ctx.available_height
    w = aw === nothing ? p.width : something(aw[], p.width)
    h = ah === nothing ? p.height : something(ah[], p.height)
    (max(Int(w), 120), max(Int(h), 80))
end

function print_document(p::ChartPlotToGraphicsCanvas, recursion, plot::ChartPlot, ctx)
    geometry = Cell(@computation begin
        w, h = _canvas_size(p, ctx)
        _layout(p, plot, w, h)
    end)

    elements = CellVector(@computation begin
        g = geometry[]
        g === nothing && return _empty_elements(p, plot, ctx)
        out = Any[]
        _frame_elements!(out, g)

        # A series whose family does not match the x axis is a configuration
        # error, not a crash: it is left out and the frame still draws.
        family = get_chart_axis_family(g.chart.x_axis)
        drawable = [(i, s) for (i, s) in g.series if get_chart_series_family(s) === family]
        series_out = Any[]
        if family === :category
            _bar_elements!(series_out, g, drawable)
        else
            for (index, s) in drawable
                _series_elements!(series_out, g, index, s)
            end
        end
        _overlay_elements!(series_out, g, plot)
        content = GraphicsCanvas(series_out; w = g.plot_w, h = g.plot_h)
        push!(out, GraphicsViewport(g.plot_x, g.plot_y, g.plot_w, g.plot_h, content))
        # Last, so an inside legend sits over the series rather than under them.
        _legend_elements!(out, g)
        out
    end)

    # Width and height are computed rather than fixed so a resize reflows the
    # same canvas object instead of replacing it.
    size_cell = Cell(@computation _canvas_size(p, ctx))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            Cell(@computation Int32(size_cell[][1])),
                            Cell(@computation Int32(size_cell[][2])),
                            Cell(elements), Cell(layout_none), Cell(true),
                            Cell(nothing))
    ChartPlotToGraphicsCanvasIoMap(p, plot, canvas, geometry)
end

# A chart-shaped placeholder for a `ChartNothing`/`ChartInsertion` root, so an
# empty chart still occupies its space and reads as a chart rather than
# vanishing.
function _empty_elements(p::ChartPlotToGraphicsCanvas, plot::ChartPlot, ctx)
    w, h = _canvas_size(p, ctx)
    Any[GraphicsRect(0, 0, w, h; color = _BACKGROUND),
        GraphicsRect(_PAD, _PAD, w - 2 * _PAD, h - 2 * _PAD; color = _PLOT_BACKGROUND, radius = 4,
                     border_width=1, border_color=_AXIS),
        GraphicsText("empty chart", _PAD * 2, h ÷ 2; font = font_ubuntu_regular_14, color = _TEXT)]
end

# A chart part is not a cursor position: there is nowhere in the canvas for a
# selection to land, and no output element a reference should follow. Selection
# is instead expressed by what the reader selects and what the frame highlights,
# so both mappers decline.
map_reference_forward(::ChartPlotToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::ChartPlotToGraphicsCanvas, iomap, reference) = nothing

# ── Reader ───────────────────────────────────────────────────────────────

_in_rect(x, y, rx, ry, rw, rh) = rx <= x < rx + rw && ry <= y < ry + rh

# Which legend item, if any, is under a point.
function _legend_hit(g, x::Integer, y::Integer)
    plan = g.legend
    plan === nothing && return nothing
    _in_rect(x, y, plan.x, plan.y, plan.box_w, plan.box_h) || return nothing
    for (index, ix, iy, iw, ih) in get_legend_item_rects(plan)
        _in_rect(x, y, ix, iy, iw, ih) && return index
    end
    0    # inside the box but between items: consumed, but names no series
end

# Which part of the chart frame a point falls on. The plot area itself is not a
# part — clicks there belong to the view interactions.
function _part_hit(g, x::Integer, y::Integer)
    px, py, pw, ph = g.plot_x, g.plot_y, g.plot_w, g.plot_h
    y < py - g.title_h && return :title
    _in_rect(x, y, px, py + ph, pw, g.h - py - ph) && return :x_axis
    _in_rect(x, y, 0, py, px, ph) && return :y_axis
    nothing
end

"""
    get_chart_part_reference(part, plot) -> Reference

The whole-element reference naming one part of the chart, in the reader's own
(`ChartPlot`) domain. Stage 1 peels the `chart` step off on the way back, so
what reaches the document is a plain `Chart` reference.
"""
function get_chart_part_reference(part::Symbol, plot::ChartPlot)
    chart = plot.chart
    ct = get_reference_node_type(chart)
    part === :title && return @reference ::ChartPlot.chart::ct.title::String
    # Every node of a reference names the type it reaches, terminal included, and
    # an axis or legend can be any of several document types — so the terminal
    # type is read off the object rather than written literally.
    if part === :x_axis
        at = get_reference_node_type(chart.x_axis)
        return @reference ::ChartPlot.chart::ct.x_axis::at
    elseif part === :y_axis
        at = get_reference_node_type(chart.y_axis)
        return @reference ::ChartPlot.chart::ct.y_axis::at
    elseif part === :legend
        lt = get_reference_node_type(chart.legend)
        return @reference ::ChartPlot.chart::ct.legend::lt
    end
    @reference ::ChartPlot
end

function get_chart_series_reference(index::Integer, plot::ChartPlot)
    chart = plot.chart
    ct = get_reference_node_type(chart)
    st = get_reference_node_type(chart.series[index])
    @reference ::ChartPlot.chart::ct.series::CellVector[index]::st
end

# The reader speaks the plot's vocabulary — stage 1 peels the `chart` step off
# on the way back — so a chart-rooted sample path is prefixed rather than
# rebuilt.
function chart_plot_sample_reference(plot::ChartPlot, series_index::Integer, sample_index::Integer)
    chart = plot.chart
    ct = get_reference_node_type(chart)
    inner = make_chart_sample_reference(chart, series_index, sample_index)
    @reference ::ChartPlot.chart::ct.^(inner)
end

function read_intent(p::ChartPlotToGraphicsCanvas, iomap::ChartPlotToGraphicsCanvasIoMap, event)
    g = iomap.geometry
    g === nothing && return nothing
    plot = iomap.input

    if event isa MouseScroll
        return _scroll_intent(g, plot, event)
    elseif event isa MouseDown && event.button === :left
        return _drag_start(g, plot, event)
    elseif event isa MouseUp && event.button === :left
        return _drag_end(g, plot, event)
    elseif event isa Union{KeyDown, KeyPress}
        return _key_intent(g, plot, event)
    elseif event isa MouseMove
        plot.drag_anchor === nothing || return _drag_move(g, plot, event)
        return _hover_intent(g, plot, event.x, event.y)
    elseif event isa MouseLeave
        # A drag that leaves the chart is abandoned, not committed halfway.
        return _compound(_cancel_drag(plot), _clear_hover(plot))
    elseif event isa MousePress && event.button === :left
        # A double click anywhere in the plot means "show me everything again".
        if event.count >= 2 && _in_rect(event.x, event.y, g.plot_x, g.plot_y, g.plot_w, g.plot_h)
            return _set_view(plot, nothing)
        end
        index = _legend_hit(g, event.x, event.y)
        if index isa Int && index > 0
            # Clicking a legend item hides or shows the series it stands for —
            # a content edit, unlike everything else the legend does.
            s = g.chart.series[index]
            return ReplaceReferencedValueOperation(s, "visible", !s.visible)
        elseif index isa Int
            return ReplaceSelectionOperation(get_chart_part_reference(:legend, plot))
        end
        part = _part_hit(g, event.x, event.y)
        part === nothing || return ReplaceSelectionOperation(get_chart_part_reference(part, plot))
        # A click on a data point selects the point; anywhere else on a series'
        # geometry selects the series.
        hit = _sample_hit(g, event.x, event.y)
        hit === nothing ||
            return ReplaceSelectionOperation(chart_plot_sample_reference(plot, hit[1], hit[2]))
        index = _series_hit(g, event.x, event.y)
        index === nothing || return ReplaceSelectionOperation(get_chart_series_reference(index, plot))
    end
    nothing
end

# ── View interaction ─────────────────────────────────────────────────────
#
# Zooming a chart is not zooming a picture. Every gesture here rewrites the data
# window on the plot, and the frame re-derives ticks, labels and decimation from
# it — so zooming in reveals more detail rather than magnifying pixels.

const _ZOOM_STEP = 1.15      # per wheel notch
const _PAN_STEP = 0.1        # fraction of the window per keyboard pan
const _DRAG_MIN = 6          # a rubber band smaller than this is a click, not a zoom

_compound(a, b) = a === nothing ? b : b === nothing ? a :
                  CompoundOperation(Operation[a, b])

# The window, the pointer and the rubber band are the state of the view, not of
# the chart: a write of one is marked as view state, so a history does not record
# a zoom, a hover or a drag. The visibility of a series is the chart's own, and a
# legend click writes it as an edit.
_write_view_state(plot::ChartPlot, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(plot, field, value))

_set_view(plot::ChartPlot, view) = _write_view_state(plot, "view", view)

# Scale a window about a fixed data point, so whatever is under the cursor stays
# under the cursor.
function _zoom_about(view::ChartView, fx::Real, fy::Real, kx::Real, ky::Real)
    ChartView(fx - (fx - view.x_min) * kx, fx + (view.x_max - fx) * kx,
              fy - (fy - view.y_min) * ky, fy + (view.y_max - fy) * ky)
end

_pan_by(view::ChartView, dx::Real, dy::Real) =
    ChartView(view.x_min + dx, view.x_max + dx, view.y_min + dy, view.y_max + dy)

# The wheel zooms; over an axis strip it zooms only that axis, which is how a
# chart offers per-axis zoom without a separate control. Shift turns it into a
# pan, matching the scroll convention everywhere else in the editor.
function _scroll_intent(g, plot::ChartPlot, event::MouseScroll)
    view = resolve_view(plot)
    notches = event.dy != 0 ? event.dy : event.dx
    notches == 0 && return nothing

    over_plot = _in_rect(event.x, event.y, g.plot_x, g.plot_y, g.plot_w, g.plot_h)
    over_x = event.y >= g.plot_y + g.plot_h && g.plot_x <= event.x <= g.plot_x + g.plot_w
    over_y = event.x <= g.plot_x && g.plot_y <= event.y <= g.plot_y + g.plot_h
    (over_plot || over_x || over_y) || return nothing

    if event.modifiers.shift
        frac = _PAN_STEP * notches
        return _set_view(plot, over_y ?
            _pan_by(view, 0.0, (view.y_max - view.y_min) * frac) :
            _pan_by(view, (view.x_max - view.x_min) * frac, 0.0))
    end

    k = _ZOOM_STEP^(-notches)
    fx = to_data(g.xs, clamp(event.x, g.plot_x, g.plot_x + g.plot_w))
    fy = to_data(g.ys, clamp(event.y, g.plot_y, g.plot_y + g.plot_h))
    kx = over_y ? 1.0 : k
    ky = over_x ? 1.0 : k
    _set_view(plot, _zoom_about(view, fx, fy, kx, ky))
end

# Dragging in the plot draws a rubber band and commits it as the new window;
# with Shift it pans instead. There is no precedent for a rubber band in this
# codebase, so the lifecycle mirrors the splitter drag: the anchor goes down on
# press, the rectangle grows on move, and the release either commits or — if the
# band never grew past a few pixels — leaves the window alone.
function _drag_start(g, plot::ChartPlot, event::MouseDown)
    _in_rect(event.x, event.y, g.plot_x, g.plot_y, g.plot_w, g.plot_h) || return nothing
    mode = event.modifiers.shift ? :pan : :zoom
    _write_view_state(plot, "drag_anchor",
                                    (event.x, event.y, mode, resolve_view(plot)))
end

function _drag_move(g, plot::ChartPlot, event::MouseMove)
    anchor = plot.drag_anchor
    anchor === nothing && return nothing
    ax, ay, mode, start_view = anchor
    if mode === :pan
        # Pan against the window the drag started from, so a slow drag does not
        # accumulate rounding.
        dx = (to_data(g.xs, ax) - to_data(g.xs, event.x))
        dy = (to_data(g.ys, ay) - to_data(g.ys, event.y))
        return _set_view(plot, _pan_by(start_view, dx, dy))
    end
    _rect_op(plot, (min(ax, event.x), min(ay, event.y),
                    abs(event.x - ax), abs(event.y - ay)))
end

function _drag_end(g, plot::ChartPlot, event::MouseUp)
    anchor = plot.drag_anchor
    anchor === nothing && return nothing
    ax, ay, mode, _ = anchor
    clear = CompoundOperation(Operation[
        _write_view_state(plot, "drag_anchor", nothing),
        _write_view_state(plot, "drag_rect", nothing)])
    (mode === :zoom && abs(event.x - ax) >= _DRAG_MIN && abs(event.y - ay) >= _DRAG_MIN) || return clear

    x0, x1 = minmax(to_data(g.xs, ax), to_data(g.xs, event.x))
    y0, y1 = minmax(to_data(g.ys, ay), to_data(g.ys, event.y))
    _compound(_set_view(plot, ChartView(x0, x1, y0, y1)), clear)
end

_rect_op(plot::ChartPlot, rect) =
    isequal(plot.drag_rect, rect) ? nothing :
    _write_view_state(plot, "drag_rect", rect)

function _cancel_drag(plot::ChartPlot)
    (plot.drag_anchor === nothing && plot.drag_rect === nothing) && return nothing
    CompoundOperation(Operation[
        _write_view_state(plot, "drag_anchor", nothing),
        _write_view_state(plot, "drag_rect", nothing)])
end

# Keyboard view control. This lives in the reader rather than in a `@gestures`
# block because the window belongs to the plot, and a document gesture only ever
# sees the chart.
function _key_intent(g, plot::ChartPlot, event::KeyDown)
    event.key === :escape && return _cancel_drag(plot)
    # Bare and Alt arrows belong to selection navigation, as everywhere else in
    # the editor, so panning takes Shift and this reader declines the rest.
    event.modifiers.shift || return nothing
    view = resolve_view(plot)
    w = view.x_max - view.x_min
    h = view.y_max - view.y_min
    event.key === :left && return _set_view(plot, _pan_by(view, -w * _PAN_STEP, 0.0))
    event.key === :right && return _set_view(plot, _pan_by(view, w * _PAN_STEP, 0.0))
    event.key === :up && return _set_view(plot, _pan_by(view, 0.0, h * _PAN_STEP))
    event.key === :down && return _set_view(plot, _pan_by(view, 0.0, -h * _PAN_STEP))
    nothing
end

# Zoom and reset arrive as characters rather than named keys.
function _key_intent(g, plot::ChartPlot, event::KeyPress)
    event.char == '0' && return _set_view(plot, nothing)
    view = resolve_view(plot)
    cx = (view.x_min + view.x_max) / 2
    cy = (view.y_min + view.y_max) / 2
    event.char in ('+', '=') &&
        return _set_view(plot, _zoom_about(view, cx, cy, 1 / _ZOOM_STEP, 1 / _ZOOM_STEP))
    event.char == '-' &&
        return _set_view(plot, _zoom_about(view, cx, cy, _ZOOM_STEP, _ZOOM_STEP))
    nothing
end

# Hovering sets two fields: the pointer in data coordinates (the crosshair reads
# it) and a reference to whatever is under it (the frame veils everything else).
function _hover_intent(g, plot::ChartPlot, x::Integer, y::Integer)
    ops = Operation[]
    index = _legend_hit(g, x, y)
    hovered = index isa Int && index > 0 ? get_chart_series_reference(index, plot) : nothing
    isequal(plot.hovered, hovered) ||
        push!(ops, _write_view_state(plot, "hovered", hovered))

    inside = _in_rect(x, y, g.plot_x, g.plot_y, g.plot_w, g.plot_h)
    cursor = inside ? (to_data(g.xs, x), to_data(g.ys, y)) : nothing
    isequal(plot.cursor, cursor) ||
        push!(ops, _write_view_state(plot, "cursor", cursor))

    isempty(ops) ? nothing : length(ops) == 1 ? ops[1] : CompoundOperation(ops)
end

function _clear_hover(plot::ChartPlot)
    (plot.hovered === nothing && plot.cursor === nothing) && return nothing
    CompoundOperation(Operation[
        _write_view_state(plot, "hovered", nothing),
        _write_view_state(plot, "cursor", nothing)])
end

# The series nearest a click inside the plot area. Line and scatter series are
# matched against their already-decimated geometry rather than their raw
# columns, so the search is over pixels and not over samples.
function _series_hit(g, x::Integer, y::Integer)
    _in_rect(x, y, g.plot_x, g.plot_y, g.plot_w, g.plot_h) || return nothing
    lx, ly = x - g.plot_x, y - g.plot_y
    best = nothing; best_d = _HIT_TOLERANCE^2
    for (index, s) in g.series
        get_chart_series_family(s) === get_chart_axis_family(g.chart.x_axis) || continue
        for (px, py) in _hit_points(g, index, s)
            d = (px - lx)^2 + (py - ly)^2
            d <= best_d && (best_d = d; best = index)
        end
    end
    best === nothing || return best
    # A strip claims its whole band, so the empty space before its first sample
    # or past where it ends still means that series.
    _strip_band_hit(g, y)
end

# The strip whose band a pixel row falls in. Bands do not overlap, so the first
# match is the only one.
function _strip_band_hit(g, y::Integer)
    for (index, s) in g.series
        s isa ChartStripSeries || continue
        band = _strip_band(g, index)
        band === nothing && continue
        band[1] <= y <= band[2] && return index
    end
    nothing
end

const _HIT_TOLERANCE = 8

# The sample nearest a click, as `(series_index, sample_index)`.
#
# Sorted line series are binary-searched, so this costs the same on a million
# samples as on a hundred. A folded scatter cloud is excluded: its individual
# points are not drawn, so there is nothing there to have clicked on.
function _sample_hit(g, x::Integer, y::Integer)
    _in_rect(x, y, g.plot_x, g.plot_y, g.plot_w, g.plot_h) || return nothing
    best = nothing; best_d = Inf
    for (index, s) in g.series
        get_chart_series_family(s) === get_chart_axis_family(g.chart.x_axis) || continue
        (s isa ChartLineSeries || s isa ChartScatterSeries) || continue
        sorted = s isa ChartLineSeries && s.sorted
        n = min(length(s.x), length(s.y))
        s isa ChartScatterSeries && n > g.style.scatter_fold_threshold && continue
        i0, i1 = sorted ? get_visible_range(s.x, g.view.x_min, g.view.x_max) : (1, n)
        found = find_nearest_sample(s.x, s.y; xs=g.xs, ys=g.ys, px=x, py=y, i0, i1,
                                    sorted=sorted, tolerance=_HIT_TOLERANCE)
        found === nothing && continue
        found[2] < best_d && (best_d = found[2]; best = (index, found[1]))
    end
    # A point within reach wins: it is a smaller target than a whole band, so
    # the click that could have meant either meant the point.
    best === nothing || return best
    _strip_sample_hit(g, x, y)
end

# The segment a click lands on, as `(series_index, sample_index)`. The index is
# the raw sample's, not the coalesced run's, so a reference to it survives the
# zoom that changes how the runs fold.
function _strip_sample_hit(g, x::Integer, y::Integer)
    for (index, s) in g.series
        s isa ChartStripSeries || continue
        band = _strip_band(g, index)
        band === nothing && continue
        (band[1] <= y <= band[2]) || continue
        k = _strip_sample_at(g, s, to_data(g.xs, x))
        k === nothing || return (index, k)
    end
    nothing
end

# Which sample holds at a time, bounded at the drawn end so a click only counts
# where something is actually painted — past an explicit `x_end` the band is
# empty, and the click means the series instead.
function _strip_sample_at(g, s::ChartStripSeries, at::Real)
    x = s.x
    n = min(length(x), length(s.values))
    n >= 1 || return nothing
    (Float64(at) < Float64(x[1]) || Float64(at) > _strip_end(s, g.view)) && return nothing
    k = searchsortedlast(x, at)
    k < 1 ? nothing : min(k, n)
end

# How many shades a folded scatter cloud is drawn in. Quantizing the density is
# what lets neighbouring cells of equal darkness merge into one band.
const _DENSITY_LEVELS = 8

"""
    _series_points(g, index, series) -> Vector{Tuple{Int,Int}}

The series' decimated pixel points, computed once per layout.
"""
_series_points(g, index::Int, s::ChartLineSeries) =
    get!(() -> _line_points(g, s), g.point_cache, index)

_hit_points(g, index::Int, s::ChartLineSeries) = _series_points(g, index, s)
_hit_points(g, index::Int, s::ChartScatterSeries) =
    get!(() -> _scatter_points(g, s), g.point_cache, index)

function _scatter_points(g, s::ChartScatterSeries)
    out = Tuple{Int,Int}[]
    n = min(length(s.x), length(s.y))
    # A folded cloud draws no individual markers, so there is nothing to snap
    # to — and scanning a million points on every pointer move would not do.
    n > g.style.scatter_fold_threshold && return out
    ox, oy = g.plot_x, g.plot_y
    seen = Set{Tuple{Int,Int}}()
    @inbounds for i in 1:n
        xv = Float64(s.x[i]); yv = Float64(s.y[i])
        (isfinite(xv) && isfinite(yv)) || continue
        pt = (round(Int, to_pixel(g.xs, xv)) - ox, round(Int, to_pixel(g.ys, yv)) - oy)
        pt in seen || (push!(seen, pt); push!(out, pt))
    end
    out
end
_hit_points(g, ::Int, ::Any) = Tuple{Int,Int}[]
