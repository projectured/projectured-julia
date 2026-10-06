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
# A `nothing` style field of a `ChartStyle` means "whatever the theme says";
# `ChartTheme` carries the colors, the fonts and the lengths a chart draws with
# when its style names none of its own.

_or(value, fallback) = value === nothing ? fallback : value

# The colours of the series: the cycle of the style of the chart, or the series
# colours of the theme when the style names none.
_get_color_cycle(style, theme_values) = _or(style.color_cycle, theme_values.series_colors)

# The width of `text` in `font` and the height of the line that holds it.
function _get_text_size(measure::TextMeasure, text::AbstractString, font::StyleFont)
    line = compute_line_box(measure, text, font)
    (line.width, line.height)
end

# Hovering one series fades the others, so the one under the pointer reads
# clearly without anything being hidden.
_veiled(color::StyleColor, on::Bool, veil::Real) =
    on ? StyleColor(color.red, color.green, color.blue, color.alpha * veil) : color

# The colour a series draws in: its own or the cycle's, faded when the pointer is
# on some *other* series.
function _draw_color(g, index::Int, own)
    color = get_series_color(own, index, _get_color_cycle(g.style, g.theme_values))
    _veiled(color, g.lit_index != 0 && g.lit_index != index, g.theme_values.veil_alpha)
end

"""
    ChartPlotToGraphicsCanvas(; measure, width=760, height=460, minimum_width=120,
                              minimum_height=80, theme=nothing)

The chart renderer. `measure::TextMeasure` is how tick and title text is sized:
`FontFileMeasure()`, as every backend draws, or a `FixedMeasure` in a test.

`width`/`height` are the fallback canvas size, used when the printer context
carries no allocation from a parent layout. `minimum_width`/`minimum_height` are
the least size that the chart draws at, whatever the parent offers: a chart in
a cell of a table takes a small one.

`theme` is a [`ChartTheme`](@ref), scaled or not, or `nothing` for the default
values; `style` holds every value of the theme as one `NamedTuple`, read once at
each print with `unwrap_cell`, and the plan of a print carries it as
`theme_values`, beside the `ChartStyle` of the chart, `style`.

A plain struct rather than an `@projection`: `measure` is fixed at
construction and needs no reactive field.
"""
struct ChartPlotToGraphicsCanvas <: Projection
    measure::TextMeasure
    width::Int
    height::Int
    minimum_width::Int
    minimum_height::Int
    style::Any
end

ChartPlotToGraphicsCanvas(; measure::TextMeasure, width::Integer=760, height::Integer=460,
                          minimum_width::Integer=120, minimum_height::Integer=80, theme=nothing) =
    ChartPlotToGraphicsCanvas(measure, Int(width), Int(height), Int(minimum_width), Int(minimum_height),
                              make_theme_values_field(ChartTheme, theme))

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
# the axis actually spans. `tick_spacing` is the target pixel distance between
# two ticks.
function _axis_ticks(axis, lo::Real, hi::Real, span_px::Real, tick_spacing::Real)
    target = clamp(round(Int, span_px / tick_spacing), 2, 12)
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
function _x_ticks_labels(p::ChartPlotToGraphicsCanvas, axis, view, span_px, font, t)
    if axis isa ChartCategoryAxis
        cats = axis.categories
        n = length(cats)
        (n == 0 || !axis.show_labels) && return (Float64[], String[])
        widest = maximum((first(compute_text_extent(p.measure, String(c), font)) for c in cats); init=0)
        k = label_step(n, span_px, widest + t.padding)
        idx = [i for i in 1:k:n if view.x_min <= i <= view.x_max]
        (Float64.(idx), String[String(cats[i]) for i in idx])
    else
        ticks = _axis_ticks(axis, view.x_min, view.x_max, span_px, t.tick_spacing)
        step = _tick_step(ticks)
        (ticks, _axis_shows_labels(axis) ? [format_tick(tick, step) for tick in ticks] : String[])
    end
end

# Which series a reference points into, or 0. Used for both the veil of the light and
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

_series_label(s) = hasproperty(s, :label) ? String(s.label) : ""

"""
    _legend_items(chart, series) -> Vector{Tuple{Int,String,Any}}

What the legend lists, as `(series_index, label, swatch_color)`.

A line, scatter, bar or histogram series is one entry in its own colour. A pie
series is an entry for each slice, in the colour of the slice. A strip
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
function _legend_items(chart::Chart, series, t)
    cycle = _get_color_cycle(chart.style, t)
    items = Tuple{Int,String,Any}[]
    states = Tuple{Int,String,Any}[]
    for (index, s) in series
        if s isa ChartStripSeries
            push!(items, (index, _series_label(s), t.strip_swatch))
            for code in 1:length(s.states)
                label = strip_state_name(s, code)
                color = strip_state_color(s, code, cycle)
                any(it -> it[2] == label && it[3] == color, states) && continue
                push!(states, (0, label, color))
            end
        elseif s isa ChartPieSeries
            # A pie is one colour for each slice: an entry for each, under its series.
            for (k, category) in enumerate(s.categories)
                own = (s.colors === nothing || k > length(s.colors)) ? nothing : s.colors[k]
                push!(items, (index, string(category), get_series_color(own, k, cycle)))
            end
        else
            push!(items, (index, _series_label(s), get_series_color(s.color, index, cycle)))
        end
    end
    append!(items, states)
end

# The legend's items and the box that holds them, before it is positioned, in
# series order unless the legend asks for a dictionary sort. `font` is the
# legend's own font, which may differ from the axis font the frame draws with.
function _legend_plan(p::ChartPlotToGraphicsCanvas, chart::Chart, series,
                      font::StyleFont, w::Int, h::Int, t)
    legend = chart.legend
    legend isa ChartLegend || return nothing
    legend.visible || return nothing
    items = _legend_items(chart, series, t)
    isempty(items) && return nothing
    legend.sort && sort!(items; by = it -> it[2])

    sizes = Tuple{Int,Int}[_get_text_size(p.measure, it[2], font) for it in items]
    horizontal = legend.position in (:above, :below) ||
                 (legend.position === :inside && legend.anchor in (:north, :south))
    area_w = horizontal ? w - 2 * t.padding : w ÷ 3
    area_h = horizontal ? h ÷ 3 : h - 2 * t.padding
    box = compute_legend_layout(sizes; horizontal, area_w, area_h, swatch=t.swatch,
                                gap=t.legend_gap, line_gap=t.legend_line_gap, pad=t.legend_padding)
    (; position = legend.position, anchor = legend.anchor, border = legend.border,
       font, items, sizes, box, box_w = box.box_w, box_h = box.box_h,
       gap = t.legend_gap, x = 0, y = 0)
end

# Put the box where `position` and `anchor` say. An outside legend is anchored
# within the strip already reserved for it; an inside one within the plot
# rectangle itself.
function _place_legend(plan, plot_x, plot_y, plot_w, plot_h, w, h, top, bottom, left, right, t)
    plan === nothing && return nothing
    bw, bh = plan.box_w, plan.box_h
    pad = t.padding
    if plan.position === :inside
        dx, dy = get_anchor_offset(plan.anchor, plot_w - 2 * pad, plot_h - 2 * pad, bw, bh)
        x, y = plot_x + pad + dx, plot_y + pad + dy
    elseif plan.position === :above
        dx, _ = get_anchor_offset(plan.anchor, plot_w, bh, bw, bh)
        x, y = plot_x + dx, top - bh - pad
    elseif plan.position === :below
        dx, _ = get_anchor_offset(plan.anchor, plot_w, bh, bw, bh)
        x, y = plot_x + dx, h - bottom + pad
    elseif plan.position === :left
        _, dy = get_anchor_offset(plan.anchor, bw, plot_h, bw, bh)
        x, y = pad, plot_y + dy
    else
        _, dy = get_anchor_offset(plan.anchor, bw, plot_h, bw, bh)
        x, y = w - right + pad, plot_y + dy
    end
    merge(plan, (; x, y))
end

"""
    get_legend_item_rects(legend, pad=6) -> Vector{Tuple{Int,Int,Int,Int,Int}}

Each drawn legend item as `(series_index, x, y, w, h)` in canvas coordinates —
what the printer draws into and what the reader hit-tests against, so the two
can never disagree about where an item is. `pad` is the legend's own padding,
the theme's `legend_padding`.
"""
function get_legend_item_rects(plan, pad::Integer = get_theme_defaults(ChartTheme).legend_padding)
    out = Tuple{Int,Int,Int,Int,Int}[]
    plan === nothing && return out
    box = plan.box
    for k in 1:min(box.shown, length(plan.items))
        col = (k - 1) ÷ box.rows
        row = (k - 1) % box.rows
        x = plan.x + pad + col * (box.col_w + plan.gap)
        y = plan.y + pad + row * box.row_h
        push!(out, (plan.items[k][1], x, y, box.col_w, box.row_h))
    end
    out
end

function _legend_elements!(out, g)
    plan = g.legend
    plan === nothing && return out
    style = g.style
    t = g.theme_values
    text_color = _or(style.title_color, t.text_color)
    box = plan.box

    # Opaque, because a bordered rect paints the border colour underneath its
    # fill: a translucent legend background would take on the border's colour.
    push!(out, GraphicsRect(plan.x, plan.y, plan.box_w, plan.box_h;
                            color = t.plot_background, radius = t.radius,
                            border_width = plan.border ? t.border_width : 0,
                            border_color = plan.border ? t.axis : nothing))

    rects = get_legend_item_rects(plan, t.legend_padding)
    for (k, (index, x, y, item_w, row_h)) in enumerate(rects)
        _, label, color = plan.items[k]
        cy = y + row_h ÷ 2
        # The legend is where a selected or lit series is called out: it is
        # the one place every series has a fixed, findable spot. An entry that
        # names no series has nothing to call out.
        if index != 0
            inset = t.highlight_inset
            if index == g.selected_index
                push!(out, GraphicsRect(x - inset, y, item_w + 2inset, row_h; color = t.selected_fill, radius = t.radius))
            elseif index == g.lit_index
                push!(out, GraphicsRect(x - inset, y, item_w + 2inset, row_h; color = t.hover_fill, radius = t.radius))
            end
        end
        push!(out, GraphicsRect(x, cy - 4, t.swatch, 8; color, radius = t.swatch_radius))
        # `plan.font` is `legend_font`, the font `g.measure_legend_label` is bound to.
        line = g.measure_legend_label(label)
        th = line.height
        push!(out, GraphicsText(label, x + t.swatch + t.legend_gap, cy - th ÷ 2 + line.text_y;
                                font = plan.font, color = text_color))
    end

    # Whatever did not fit is accounted for rather than silently dropped.
    if box.truncated
        hidden = length(plan.items) - box.shown
        col = box.shown ÷ box.rows
        row = box.shown % box.rows
        x = plan.x + t.legend_padding + col * (box.col_w + t.legend_gap)
        y = plan.y + t.legend_padding + row * box.row_h
        line = g.measure_legend_label("… and $hidden more")
        push!(out, GraphicsText("… and $hidden more", x, y + line.text_y;
                                font = plan.font, color = text_color))
    end
    out
end

# The whole frame in one pass: ranges, then ticks, then the margins the measured
# tick labels imply, then the plot rectangle and the two scales.
function _layout(p::ChartPlotToGraphicsCanvas, plot::ChartPlot, w::Int, h::Int, t)
    chart = plot.chart
    chart isa Chart || return nothing
    style = chart.style
    title_font = _or(style.title_font, t.title_font)
    axis_font = _or(style.axis_font, t.axis_font)
    legend_font = _or(style.legend_font, t.legend_font)

    view = resolve_view(plot)
    x_axis, y_axis = chart.x_axis, chart.y_axis
    series = _visible_series(chart)

    title = chart.title
    if isempty(title)
        title_h = 0
        title_text_y = 0
    else
        title_line = compute_line_box(p.measure, title, title_font)
        title_h = title_line.height + t.padding ÷ 2
        title_text_y = title_line.text_y
    end

    y_title = _axis_shows_title(y_axis) ? _axis_title(y_axis) : ""
    if isempty(y_title)
        y_title_h = 0
        y_title_text_y = 0
    else
        y_title_line = compute_line_box(p.measure, y_title, axis_font)
        y_title_h = y_title_line.height + t.axis_title_gap
        y_title_text_y = y_title_line.text_y
    end
    x_title = _axis_shows_title(x_axis) ? _axis_title(x_axis) : ""
    if isempty(x_title)
        x_title_h = 0
        x_title_text_y = 0
    else
        x_title_line = compute_line_box(p.measure, x_title, axis_font)
        x_title_h = x_title_line.height + t.axis_title_gap
        x_title_text_y = x_title_line.text_y
    end

    # Provisional plot extent, used only to pick a tick density. The ticks then
    # decide the real margins, and those give the final extent.
    prov_w = max(w - 2 * t.padding - 60, 40)
    prov_h = max(h - 2 * t.padding - title_h - y_title_h - x_title_h - 24, 40)

    # Row-label mode: when the chart is nothing but strips, the y axis is the
    # list of strips, so it carries their labels instead of numbers. Any other
    # series visible — or none at all — and the numeric path runs untouched.
    strip_rows, strip_count = _strip_rows(series, chart)
    strip_only = strip_count >= 1 && all(s -> s isa ChartStripSeries, (s for (_, s) in series))

    if strip_only
        yticks = Float64[Float64(strip_rows[i]) for (i, _) in series]
        ylabels = _axis_shows_labels(y_axis) ? [_series_label(s) for (_, s) in series] : String[]
    else
        yticks = _axis_ticks(y_axis, view.y_min, view.y_max, prov_h, t.tick_spacing)
        ylabels = _axis_shows_labels(y_axis) ?
            [format_tick(tick, _tick_step(yticks)) for tick in yticks] : String[]
    end
    xticks, xlabels = _x_ticks_labels(p, x_axis, view, prov_w, axis_font, t)
    # A chart of pie series has no axes: no ticks and no labels.
    pie = !isempty(series) && all(s -> s isa ChartPieSeries, (s for (_, s) in series))
    if pie
        yticks, ylabels = Float64[], String[]
        xticks, xlabels = empty(xticks), String[]
    end

    # Measure each label once, here, and carry the boxes forward — the frame
    # needs them again when it places the text.
    ysizes = LineBox[compute_line_box(p.measure, l, axis_font) for l in ylabels]
    xsizes = LineBox[compute_line_box(p.measure, l, axis_font) for l in xlabels]
    label_h = compute_line_box(p.measure, "0", axis_font).height
    ylabel_w = isempty(ysizes) ? 0 : maximum(sz.width for sz in ysizes)
    xlabel_last_w = isempty(xsizes) ? 0 : last(xsizes).width

    left = t.padding + ylabel_w + (isempty(ylabels) ? 0 : t.label_gap) + t.tick_length
    right = t.padding + xlabel_last_w ÷ 2
    top = t.padding + title_h + y_title_h
    bottom = t.padding + x_title_h + (isempty(xlabels) ? 0 : label_h + t.label_gap) + t.tick_length

    # An outside legend reserves a strip, shrinking the plot; an inside one
    # overlays it and takes nothing.
    legend = _legend_plan(p, chart, series, legend_font, w, h, t)
    if legend !== nothing && legend.position !== :inside
        legend.position === :above && (top += legend.box_h + t.padding)
        legend.position === :below && (bottom += legend.box_h + t.padding)
        legend.position === :left && (left += legend.box_w + t.padding)
        legend.position === :right && (right += legend.box_w + t.padding)
    end

    plot_x = left
    plot_y = top
    plot_w = max(w - left - right, 20)
    plot_h = max(h - top - bottom, 20)
    legend = _place_legend(legend, plot_x, plot_y, plot_w, plot_h, w, h, top, bottom, left, right, t)

    xlog = x_axis isa ChartAxis && x_axis.log
    ylog = y_axis isa ChartAxis && y_axis.log
    xs = AxisScale(view.x_min, view.x_max, plot_x, plot_x + plot_w; log=xlog)
    ys = AxisScale(view.y_min, view.y_max, plot_y + plot_h, plot_y; log=ylog)

    selected_index = _reference_series_index(chart, chart.selection)
    selected_part = get_chart_part_index(chart, chart.selection)
    whole_selected = chart.selection isa EmptyReference

    measure_label = label -> compute_line_box(p.measure, label, axis_font)
    # The legend draws with its own font, which may differ from the axis font
    # `measure_label` is bound to.
    measure_legend_label = label -> compute_line_box(p.measure, label, legend_font)
    # Decimated series geometry is wanted by the printer once per repaint and by
    # the reader on every pointer move, so it is memoized here — inside the
    # layout, which already dies and is rebuilt whenever the data, the window or
    # the size changes.
    point_cache = Dict{Int,Vector{Tuple{Int,Int}}}()
    # Strip spans, computed here rather than on demand: see `_strip_spans`.
    strip_spans = Dict{Int,Vector{Tuple{Int,Int,Int}}}(
        i => _compute_strip_spans(xs, view, s)
        for (i, s) in series if s isa ChartStripSeries && haskey(strip_rows, i))

    (; w, h, chart, style, theme_values = t, view, series, legend,
       selected_index, selected_part, whole_selected,
       measure_label, measure_legend_label,
       plot_x, plot_y, plot_w, plot_h, xs, ys,
       point_cache, strip_spans, strip_rows, strip_count, strip_only, pie,
       xticks, yticks, xlabels, ylabels, xsizes, ysizes, label_h,
       title, title_font, axis_font, legend_font, title_h, title_text_y,
       x_title, y_title, x_title_h, y_title_h, x_title_text_y, y_title_text_y)
end

# ── Pie ──────────────────────────────────────────────────────────────────

# The slices of the first visible pie series, in the coordinates of the plot: a
# polygon of each arc and the centre, from the top, clockwise, in the colour of
# the slice. A slice of no positive, finite value is not drawn.
function _pie_elements!(out, g)
    isempty(g.series) && return out
    _, s = first(g.series)
    values = Float64[(v isa Real && isfinite(v) && v > 0) ? Float64(v) : 0.0 for v in s.values]
    total = sum(values; init = 0.0)
    total > 0 || return out
    cx, cy = g.plot_w / 2, g.plot_h / 2
    radius = max(1.0, min(g.plot_w, g.plot_h) / 2 - 2)
    cycle = _get_color_cycle(g.style, g.theme_values)
    angle = -π / 2
    for (k, value) in enumerate(values)
        value > 0 || continue
        span = 2π * value / total
        steps = max(2, ceil(Int, span / (π / 30)))
        points = Tuple{Int,Int}[(round(Int, cx), round(Int, cy))]
        for j in 0:steps
            a = angle + span * j / steps
            push!(points, (round(Int, cx + radius * cos(a)), round(Int, cy + radius * sin(a))))
        end
        own = (s.colors === nothing || k > length(s.colors)) ? nothing : s.colors[k]
        push!(out, GraphicsPolygon(points; color = get_series_color(own, k, cycle)))
        angle += span
    end
    out
end

# ── Frame elements ───────────────────────────────────────────────────────

function _frame_elements!(out, g)
    style = g.style
    t = g.theme_values
    grid_color = _or(style.grid_color, t.grid)
    text_color = _or(style.title_color, t.text_color)
    px, py, pw, ph = g.plot_x, g.plot_y, g.plot_w, g.plot_h

    push!(out, GraphicsRect(0, 0, g.w, g.h; color = _or(style.background, t.background)))
    push!(out, GraphicsRect(px, py, pw, ph; color = _or(style.plot_background, t.plot_background)))

    chart = g.chart
    grid_x = _axis_grid(chart.x_axis)
    grid_y = _axis_grid(chart.y_axis)

    # In row-label mode the y ticks name the strips rather than measuring
    # anything, so a gridline through each would just underline the bands.
    if grid_y !== :none && !g.strip_only
        for tick in g.yticks
            y = round(Int, to_pixel(g.ys, tick))
            (py <= y <= py + ph) || continue
            push!(out, GraphicsLine(px, y, px + pw, y; color = grid_color, dash=t.grid_dash))
        end
    end
    if grid_x !== :none
        for tick in g.xticks
            x = round(Int, to_pixel(g.xs, tick))
            (px <= x <= px + pw) || continue
            push!(out, GraphicsLine(x, py, x, py + ph; color = grid_color, dash=t.grid_dash))
        end
    end

    # The two axis lines, drawn over the grid. A pie has none.
    if !g.pie
        push!(out, GraphicsLine(px, py + ph, px + pw, py + ph; color = t.axis))
        push!(out, GraphicsLine(px, py, px, py + ph; color = t.axis))
    end

    # Tick marks and their labels.
    for i in eachindex(g.ylabels)
        y = round(Int, to_pixel(g.ys, g.yticks[i]))
        (py - 1 <= y <= py + ph + 1) || continue
        push!(out, GraphicsLine(px - t.tick_length, y, px, y; color = t.axis))
        line = g.ysizes[i]
        tw, th = line.width, line.height
        push!(out, GraphicsText(g.ylabels[i], px - t.tick_length - t.label_gap - tw, y - th ÷ 2 + line.text_y;
                                font = g.axis_font, color = text_color))
    end
    for i in eachindex(g.xlabels)
        x = round(Int, to_pixel(g.xs, g.xticks[i]))
        (px - 1 <= x <= px + pw + 1) || continue
        push!(out, GraphicsLine(x, py + ph, x, py + ph + t.tick_length; color = t.axis))
        line = g.xsizes[i]
        push!(out, GraphicsText(g.xlabels[i], x - line.width ÷ 2, py + ph + t.tick_length + t.label_gap + line.text_y;
                                font = g.axis_font, color = text_color))
    end

    _selection_elements!(out, g)

    isempty(g.title) ||
        push!(out, GraphicsText(g.title, px, t.padding + g.title_text_y; font = g.title_font, color = text_color))
    # No rotated text: the backends only honour the translate+scale subset of an
    # affine transform, so the y-axis title sits above the axis rather than
    # running up its side.
    isempty(g.y_title) ||
        push!(out, GraphicsText(g.y_title, px, t.padding + g.title_h + g.y_title_text_y;
                                font = g.axis_font, color = text_color))
    isempty(g.x_title) ||
        push!(out, GraphicsText(g.x_title, px + pw ÷ 2, g.h - t.padding - g.x_title_h + 2 + g.x_title_text_y;
                                font = g.axis_font, color = text_color))
    out
end

# What a selection looks like. Every part of a chart is a document that can be
# selected, so every part has a region the projection can call out — the title's
# line, either axis' label strip, the legend's box, a series' legend row — and
# the whole chart gets a frame of its own.
function _selection_elements!(out, g)
    px, py, pw, ph = g.plot_x, g.plot_y, g.plot_w, g.plot_h
    t = g.theme_values
    if g.whole_selected
        _outline!(out, 1, 1, g.w - 2, g.h - 2, t.selected_edge, t.selected_width)
        return out
    end
    part = g.selected_part
    if part == 1 && !isempty(g.title)
        line = g.measure_label(g.title)
        tw, th = line.width, line.height
        inset, margin = t.highlight_inset, t.title_highlight_margin
        push!(out, GraphicsRect(px - inset, t.padding - margin, tw + 2inset, g.title_h + 2margin;
                                color = t.selected_fill, radius = t.radius))
    elseif part == 2
        push!(out, GraphicsRect(px, py + ph + t.tick_length, pw, g.h - (py + ph + t.tick_length) - t.padding ÷ 2;
                                color = t.selected_fill, radius = t.radius))
    elseif part == 3
        push!(out, GraphicsRect(t.padding ÷ 2, py, px - t.tick_length - t.padding ÷ 2, ph;
                                color = t.selected_fill, radius = t.radius))
    elseif part == 4 && g.legend !== nothing
        plan = g.legend
        inset = t.highlight_inset
        _outline!(out, plan.x - inset, plan.y - inset, plan.box_w + 2inset, plan.box_h + 2inset,
                 t.selected_edge, t.selected_width)
    end
    out
end

# An outline drawn as its four edges. A rect with a border paints the border
# colour across the whole shape and insets the fill on top, so it cannot express
# "outline only" over content that has to stay visible.
function _outline!(out, x::Integer, y::Integer, w::Integer, h::Integer, color::StyleColor, width::Integer)
    push!(out, GraphicsLine(x, y, x + w, y; color, width))
    push!(out, GraphicsLine(x, y + h, x + w, y + h; color, width))
    push!(out, GraphicsLine(x, y, x, y + h; color, width))
    push!(out, GraphicsLine(x + w, y, x + w, y + h; color, width))
    out
end

# ── Series elements ──────────────────────────────────────────────────────

# A line style as the primitive's (on, off) pixel pattern. `:dashdot` would need
# a four-element pattern, which the primitive does not carry, so it is not among
# the styles offered; anything unrecognised draws solid.
_dash_pattern(style::Symbol, t) =
    style === :dotted ? t.dotted_line_dash :
    style === :dashed ? t.dashed_line_dash : nothing

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
    t = g.theme_values
    color = _draw_color(g, index, s.color)
    pts = _series_points(g, index, s)
    isempty(pts) && return out

    if s.draw_style === :pins
        baseline = round(Int, to_pixel(g.ys, 0.0)) - g.plot_y
        for (x, ytop, ybot) in build_pins_segments(pts, baseline)
            push!(out, GraphicsLine(x, ytop, x, ybot; color, width=max(s.line_width, 1),
                                    dash=_dash_pattern(s.line_style, t)))
        end
    elseif s.draw_style !== :none
        shaped = s.draw_style === :linear ? pts : step_points(pts, s.draw_style)
        length(shaped) >= 2 &&
            push!(out, GraphicsPolyline(shaped; color, width=max(s.line_width, 1),
                                        dash=_dash_pattern(s.line_style, t)))
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
                                color = _or(chart.bar_baseline_color, g.theme_values.axis)))
    end
    out
end

# ── Histograms ───────────────────────────────────────────────────────────

function _histogram_elements!(out, g, index::Int, s::ChartHistogramSeries)
    style = g.style
    t = g.theme_values
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
            push!(out, GraphicsPolyline(pts; color, width=t.histogram_outline_width))
        end
    else
        for (l, r, lo, hi) in bars
            ytop = to_pixel(g.ys, hi) - oy
            ybot = to_pixel(g.ys, lo == hi ? 0.0 : lo) - oy
            y0, y1 = min(ytop, ybot, baseline), max(ytop, ybot, baseline)
            push!(out, GraphicsRect(l, round(Int, y0), max(r - l, 1),
                                    max(round(Int, y1 - y0), 1); color,
                                    border_width=t.border_width, border_color=t.axis))
        end
    end

    # Under/overflow cells span from the axis edge to the outermost bin, drawn
    # translucent so they read as "everything beyond here" rather than as data.
    if s.show_overflow
        faint = StyleColor(color.red, color.green, color.blue, color.alpha * t.overflow_alpha)
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
_strip_label_color(color::StyleColor, text_color::StyleColor, light::StyleColor) =
    (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue) > 0.55 ?
    text_color : light

function _strip_elements!(out, g, index::Int, s::ChartStripSeries)
    band = _strip_band(g, index)
    band === nothing && return out
    top, bottom = band
    ox, oy = g.plot_x, g.plot_y
    height = max(bottom - top, 1)
    spans = _strip_spans(g, index)
    cycle = _get_color_cycle(g.style, g.theme_values)
    veiled = g.lit_index != 0 && g.lit_index != index
    t = g.theme_values

    for (l, r, code) in spans
        color = _veiled(strip_state_color(s, code, cycle), veiled, t.veil_alpha)
        push!(out, s.draw_edges ?
            GraphicsRect(l - ox, top - oy, max(r - l, 1), height; color,
                         border_width=t.border_width, border_color=t.strip_edge) :
            GraphicsRect(l - ox, top - oy, max(r - l, 1), height; color))
    end

    # A state names itself inside its own segment when the name fits. No
    # rotation: the backends only honour the translate+scale subset of an affine
    # transform, so a name that does not fit is left out rather than turned.
    if s.show_labels
        for (l, r, code) in spans
            name = strip_state_name(s, code)
            isempty(name) && continue
            line = g.measure_label(name)
            tw, th = line.width, line.height
            (tw + 6 <= r - l && th + 2 <= height) || continue
            color = strip_state_color(s, code, cycle)
            push!(out, GraphicsText(name, l - ox + (r - l - tw) ÷ 2,
                                    top - oy + (height - th) ÷ 2 + line.text_y;
                                    font = g.axis_font,
                                    color = _strip_label_color(color, t.text_color, t.strip_contrast_text)))
        end
    end
    out
end

# ── Overlay ──────────────────────────────────────────────────────────────
#
# What is drawn over the series inside the plot viewport: the crosshair with its
# value readout, and the rubber band while a zoom drag is in progress.

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
    t = g.theme_values
    rect = plot.drag_rect
    if rect !== nothing
        rx, ry, rw, rh = rect
        # Fill only, no border: a bordered rect is drawn as the border colour
        # with the fill inset on top of it, so a translucent fill would show the
        # border colour through the whole band rather than around it.
        push!(out, GraphicsRect(rx - g.plot_x, ry - g.plot_y, max(rw, 1), max(rh, 1);
                                color = t.band_fill))
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
                color = get_series_color(series.color, sample[1], _get_color_cycle(g.style, g.theme_values))
                push!(out, GraphicsCircle(sx, sy, 6; color = color_transparent,
                                          border_width=t.selected_width, border_color=t.selected_edge))
                push!(out, GraphicsCircle(sx, sy, 3; color))
            end
        end
    end

    cursor = plot.cursor
    cursor === nothing && return out
    cx = round(Int, to_pixel(g.xs, cursor[1])) - g.plot_x
    cy = round(Int, to_pixel(g.ys, cursor[2])) - g.plot_y
    push!(out, GraphicsLine(cx, 0, cx, g.plot_h; color = t.crosshair, dash=t.crosshair_dash))
    push!(out, GraphicsLine(0, cy, g.plot_w, cy; color = t.crosshair, dash=t.crosshair_dash))

    snapped = _snap_point(g, cx, cy)
    text_color = _or(g.style.title_color, t.text_color)
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
    color = get_series_color(g.chart.series[index].color, index, _get_color_cycle(g.style, g.theme_values))
    push!(out, GraphicsCircle(px, py, 4; color, border_width=t.border_width, border_color=t.plot_background))
    label = string(_series_label(g.chart.series[index]), "  ",
                   format_tick(to_data(g.xs, px + g.plot_x)), ", ",
                   format_tick(to_data(g.ys, py + g.plot_y)))
    # Flip the readout to the other side of the cursor near the right edge so it
    # is never clipped away by the viewport.
    line = g.measure_label(label)
    tw, th = line.width, line.height
    lx = px + tw + 12 > g.plot_w ? px - tw - 8 : px + 8
    push!(out, GraphicsRect(lx - 4, py - th - 8, tw + 8, th + 6;
                            color = t.plot_background, radius = t.radius,
                            border_width=t.border_width, border_color=t.axis))
    push!(out, GraphicsText(label, lx, py - th - 5 + line.text_y; font = g.axis_font, color = text_color))
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
              max(right - left, 1), max(band[2] - band[1], 1), g.theme_values.selected_edge, g.theme_values.selected_width)
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

# The extent on one axis, by the child rule: the projection's own size, cut at the
# maximum of the range, and at least its minimum. An exact range gives the chart
# its extent, a bounded one caps it, and a free one leaves it its own size.
function _get_chart_extent(minimum, maximum, natural)
    upper = maximum === nothing ? nothing : maximum[]
    lower = minimum === nothing ? nothing : minimum[]
    extent = upper === nothing ? natural : min(natural, Int(upper))
    lower === nothing ? extent : max(extent, Int(lower))
end

# Canvas size: the extent on each axis, and never less than the chart can draw
# in. Reading the cells here registers the dependency, so a resize reflows
# without re-projecting.
function _canvas_size(p::ChartPlotToGraphicsCanvas, ctx)
    ctx === nothing && return (max(p.width, p.minimum_width), max(p.height, p.minimum_height))
    w = _get_chart_extent(ctx.minimum_width, ctx.maximum_width, p.width)
    h = _get_chart_extent(ctx.minimum_height, ctx.maximum_height, p.height)
    (max(Int(w), p.minimum_width), max(Int(h), p.minimum_height))
end

function print_document(p::ChartPlotToGraphicsCanvas, recursion, plot::ChartPlot, ctx)
    t = unwrap_cell(p.style)
    geometry = Cell(@computation begin
        w, h = _canvas_size(p, ctx)
        _layout(p, plot, w, h, t)
    end)

    elements = CellVector(@computation begin
        g = geometry[]
        g === nothing && return _empty_elements(p, plot, ctx, t)
        # The series that the pointer is on lights, and the others are veiled. The
        # element pass reads it, which each move of the cursor runs, and the
        # layout does not.
        g = merge(g, (lit_index = _reference_series_index(g.chart, getfield(plot, :mouse_target)[]),))
        out = Any[]
        _frame_elements!(out, g)

        # A series whose family does not match the x axis is a configuration
        # error, not a crash: it is left out and the frame still draws.
        family = get_chart_axis_family(g.chart.x_axis)
        drawable = [(i, s) for (i, s) in g.series if get_chart_series_family(s) === family]
        series_out = Any[]
        if g.pie
            _pie_elements!(series_out, g)
        elseif family === :category
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
function _empty_elements(p::ChartPlotToGraphicsCanvas, plot::ChartPlot, ctx, t)
    w, h = _canvas_size(p, ctx)
    Any[GraphicsRect(0, 0, w, h; color = t.background),
        GraphicsRect(t.padding, t.padding, w - 2 * t.padding, h - 2 * t.padding; color = t.plot_background,
                     radius = t.placeholder_radius, border_width=t.border_width, border_color=t.axis),
        GraphicsText("empty chart", t.padding * 2, h ÷ 2; font = t.axis_font, color = t.text_color)]
end

# A chart part is not a cursor position: there is nowhere in the canvas for a
# selection to land, and no output element a reference should follow. Selection
# is instead expressed by what the reader selects and what the frame highlights,
# so a reference maps forward to nothing.
map_reference_forward(::ChartPlotToGraphicsCanvas, iomap, reference) = nothing

# A point maps back to the part drawn at it, with the hit tests of the reader of
# a click, in its order: a legend item to its series and the rest of the legend
# to the legend, a part of the frame to that part, a data point to the point, a
# series line to its series. Any other point of the plot area maps to the plot
# at that point, which the cursor readout reads.
function map_reference_backward(::ChartPlotToGraphicsCanvas, iomap, reference)
    point = find_reference_point(reference)
    (point === nothing || !(iomap isa ChartPlotToGraphicsCanvasIoMap)) && return nothing
    g = iomap.geometry
    g === nothing && return nothing
    plot, x, y = iomap.input, point.x, point.y
    # A click arrives only on what the chart drew; a point past its box is nothing
    # of the chart, whatever the frame tests say of it.
    canvas = iomap.output
    canvas isa GraphicsCanvas && canvas.w > 0 && canvas.h > 0 &&
        !_in_rect(x, y, Int(canvas.x), Int(canvas.y), Int(canvas.w), Int(canvas.h)) && return nothing
    index = _legend_hit(g, x, y)
    index isa Int && return index > 0 ? get_chart_series_reference(index, plot) :
                                        get_chart_part_reference(:legend, plot)
    part = _part_hit(g, x, y)
    part === nothing || return get_chart_part_reference(part, plot)
    hit = _sample_hit(g, x, y)
    hit === nothing || return chart_plot_sample_reference(plot, hit[1], hit[2])
    index = _series_hit(g, x, y)
    index === nothing || return get_chart_series_reference(index, plot)
    _in_rect(x, y, g.plot_x, g.plot_y, g.plot_w, g.plot_h) || return nothing
    ConcreteReference(PointReferenceStep(x, y))
end

# ── Reader ───────────────────────────────────────────────────────────────

_in_rect(x, y, rx, ry, rw, rh) = rx <= x < rx + rw && ry <= y < ry + rh

# Which legend item, if any, is under a point.
function _legend_hit(g, x::Integer, y::Integer)
    plan = g.legend
    plan === nothing && return nothing
    _in_rect(x, y, plan.x, plan.y, plan.box_w, plan.box_h) || return nothing
    for (index, ix, iy, iw, ih) in get_legend_item_rects(plan, g.theme_values.legend_padding)
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
    elseif event isa Union{KeyDown, KeyPress}
        return _key_intent(g, plot, event)
    elseif event isa DragMove
        # The drag comes by the path of the plot, also off the plot.
        return _drag_move(g, plot, event)
    elseif event isa DragEnd
        return _drag_end(g, plot, event)
    elseif event isa DragCancel
        return _cancel_drag(plot)
    elseif event isa MouseMove
        return _track_cursor(g, plot, event.x, event.y)
    elseif event isa MouseClick && event.button === :left
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
# a zoom, a readout or a drag. The visibility of a series is the chart's own, and a
# legend click writes it as an edit.
_write_view_state(plot::ChartPlot, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(plot, field, value))

# A view that the plot holds is not written again, so a move to the point of the
# last move writes no cell.
_set_view(plot::ChartPlot, view) =
    isequal(plot.view, view) ? nothing : _write_view_state(plot, "view", view)

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
# press and starts the drag of the plot, the rectangle grows on each `DragMove`,
# and `DragEnd` either commits or — if the band never grew past a few pixels —
# leaves the window alone. The anchor keeps the view of the press as the plot
# holds it, so `DragCancel` puts back a pan.
function _drag_start(g, plot::ChartPlot, event::MouseDown)
    _in_rect(event.x, event.y, g.plot_x, g.plot_y, g.plot_w, g.plot_h) || return nothing
    mode = event.modifiers.shift ? :pan : :zoom
    # The pointer keeps the arrow of the press while the drag is on.
    CompoundOperation(Operation[
        _write_view_state(plot, "drag_anchor",
                          (event.x, event.y, mode, resolve_view(plot), g.xs, g.ys, plot.view)),
        StartDragOperation(EmptyReference(), nothing),
        make_screen_pointer_shape_operation(:arrow)])
end

function _drag_move(g, plot::ChartPlot, event::DragMove)
    anchor = plot.drag_anchor
    anchor === nothing && return nothing
    ax, ay, mode, start_view, xs, ys = anchor
    if mode === :pan
        # Pan against the window and the scales the drag started from, so a slow
        # drag does not accumulate rounding, and a move to the point of the last
        # move gives the same window, which is not written again.
        dx = (to_data(xs, ax) - to_data(xs, event.x))
        dy = (to_data(ys, ay) - to_data(ys, event.y))
        return _set_view(plot, _pan_by(start_view, dx, dy))
    end
    _rect_op(plot, (min(ax, event.x), min(ay, event.y),
                    abs(event.x - ax), abs(event.y - ay)))
end

function _drag_end(g, plot::ChartPlot, event::DragEnd)
    anchor = plot.drag_anchor
    anchor === nothing && return nothing
    ax, ay, mode, _ = anchor
    clear = CompoundOperation(Operation[
        _write_view_state(plot, "drag_anchor", nothing),
        _write_view_state(plot, "drag_rect", nothing),
        make_screen_pointer_shape_operation(nothing)])
    (mode === :zoom && abs(event.x - ax) >= _DRAG_MIN && abs(event.y - ay) >= _DRAG_MIN) || return clear

    x0, x1 = minmax(to_data(g.xs, ax), to_data(g.xs, event.x))
    y0, y1 = minmax(to_data(g.ys, ay), to_data(g.ys, event.y))
    _compound(_set_view(plot, ChartView(x0, x1, y0, y1)), clear)
end

_rect_op(plot::ChartPlot, rect) =
    isequal(plot.drag_rect, rect) ? nothing :
    _write_view_state(plot, "drag_rect", rect)

# The end of a drag with no change: a pan puts back the view of the press.
function _cancel_drag(plot::ChartPlot)
    anchor = plot.drag_anchor
    (anchor === nothing && plot.drag_rect === nothing) && return nothing
    clear = CompoundOperation(Operation[
        _write_view_state(plot, "drag_anchor", nothing),
        _write_view_state(plot, "drag_rect", nothing),
        make_screen_pointer_shape_operation(nothing)])
    (anchor !== nothing && anchor[3] === :pan) || return clear
    _compound(_set_view(plot, anchor[7]), clear)
end

# Keyboard view control. This lives in the reader rather than in a `@gestures`
# block because the window belongs to the plot, and a document gesture only ever
# sees the chart.
function _key_intent(g, plot::ChartPlot, event::KeyDown)
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

# A move writes the pointer in data coordinates, which the crosshair reads, only
# when it changes. A move off the plot area clears it, such as the move to
# `(-1, -1)` that a container gives to the plot that the pointer leaves. What is
# under the pointer is the mouse target of the plot.
function _track_cursor(g, plot::ChartPlot, x::Integer, y::Integer)
    _in_rect(x, y, g.plot_x, g.plot_y, g.plot_w, g.plot_h) || return _clear_cursor(plot)
    cursor = (to_data(g.xs, x), to_data(g.ys, y))
    isequal(plot.cursor, cursor) ? nothing : _write_view_state(plot, "cursor", cursor)
end

function _clear_cursor(plot::ChartPlot)
    plot.cursor === nothing && return nothing
    _write_view_state(plot, "cursor", nothing)
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
