"""
    ChartPlotToGraphicsModule

ChartPlot → Graphics: the chart renderer. Everything a chart shows — the plot
frame, gridlines, ticks and their labels, the axis titles, the series geometry —
is composed here out of the existing graphics primitives. There is no plotting
library underneath and no rasterization step; a chart is vector output like
every other projection, so it stays selectable and resolution-independent.

**Layout.** One computed cell (`geometry`) derives the whole frame from the
chart, the view window and the available size: the data ranges, the plot
rectangle, the tick positions and their measured labels. Axis margins fall out
of measuring the labels, so the two-pass measure-then-remeasure dance a
retained-mode toolkit needs does not arise — the margins are just a cell that
depends on the ticks.

**Cost.** Series geometry goes through `ChartGeometry`'s decimation, so the
number of graphics elements is bounded by the size of the plot rectangle rather
than by the length of the columns. A million-sample series and a
thousand-sample one produce the same amount of output at the same zoom.

The plot area is a `GraphicsViewport` purely to clip; the data-to-pixel mapping
is computed from the view window rather than carried as an affine transform, so
zooming in re-derives ticks and decimation instead of magnifying pixels.
"""
module ChartPlotToGraphicsModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ChartModule: Chart, ChartNothing, ChartInsertion, ChartSeries,
                      ChartAxis, ChartCategoryAxis, ChartLegend, ChartStyle,
                      ChartLineSeries, ChartScatterSeries, ChartBarSeries,
                      ChartHistogramSeries,
                      chart_series_family, chart_axis_family,
                      series_color, series_symbol
import ..ChartPlotModule: ChartPlot, ChartView
import ..ChartGeometryModule: AxisScale, to_pixel, to_data,
                              column_bounds, merge_bounds, pad_range,
                              nice_ticks, log_ticks, format_tick,
                              visible_range, decimate_minmax, step_points, pins_segments
import ..GraphicsModule: GraphicsCanvas, GraphicsRect, GraphicsLine, GraphicsText,
                         GraphicsCircle, GraphicsPolyline, GraphicsViewport,
                         layout_none
import ..ColorModule: StyleColor,
                      color_solarized_background_lighter, color_solarized_background_light,
                      color_solarized_content_dark, color_solarized_content_darker,
                      color_solarized_blue
import ..FontModule: StyleFont, font_ubuntu_regular_14, font_ubuntu_bold_16
import ..IoMapModule: IoMap, var"@iomap"

export ChartPlotToGraphicsCanvas, ChartPlotToGraphicsCanvasIoMap

# ── Theme defaults ───────────────────────────────────────────────────────
# A `nothing` style field means "whatever the theme says"; these are that.

const _BACKGROUND = color_solarized_background_lighter
const _PLOT_BACKGROUND = StyleColor(1.0, 1.0, 1.0, 1.0)
const _AXIS = color_solarized_content_dark
const _GRID = StyleColor(0.0, 0.0, 0.0, 0.10)
const _TEXT = color_solarized_content_darker

# Frame metrics, in logical pixels.
const _PAD = 8            # breathing room around the whole chart
const _TICK = 4           # length of a tick mark outside the plot frame
const _LABEL_GAP = 3      # between a tick mark and its label
const _TICK_TARGET_PX = 70   # aim for roughly one tick per this many pixels

_or(value, fallback) = value === nothing ? fallback : value

"""
    ChartPlotToGraphicsCanvas(; measure, width=760, height=460)

The chart renderer. `measure(text, font) -> (w, h)` is how tick and title text
is sized; pass `truetype_measure_text` for a backend-free pipeline or
`sdl_measure_text` when running against a live SDL window.

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

_series_x_bounds(s::ChartLineSeries) = column_bounds(s.x)
_series_x_bounds(s::ChartScatterSeries) = column_bounds(s.x)
_series_x_bounds(::Any) = nothing

_series_y_bounds(s::ChartLineSeries) = column_bounds(s.y)
_series_y_bounds(s::ChartScatterSeries) = column_bounds(s.y)
_series_y_bounds(::Any) = nothing

# The data extent of everything drawn, before padding or axis overrides.
function _data_bounds(series)
    xb = nothing; yb = nothing
    for (_, s) in series
        xb = merge_bounds(xb, _series_x_bounds(s))
        yb = merge_bounds(yb, _series_y_bounds(s))
    end
    (xb, yb)
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
    xb, yb = _data_bounds(series)
    x0, x1 = _fit_range(xb, chart.x_axis, 0.02)
    y0, y1 = _fit_range(yb, chart.y_axis, 0.08)
    ChartView(x0, x1, y0, y1)
end

# ── Layout ───────────────────────────────────────────────────────────────

# Ticks for one axis over the visible window, at a density suited to the pixels
# the axis actually spans.
function _axis_ticks(axis, lo::Real, hi::Real, span_px::Real)
    target = clamp(round(Int, span_px / _TICK_TARGET_PX), 2, 12)
    (axis isa ChartAxis && axis.log) ? log_ticks(lo, hi) : nice_ticks(lo, hi, target)
end

_tick_step(ticks) = length(ticks) >= 2 ? abs(ticks[2] - ticks[1]) : 0.0

_axis_title(axis) = axis isa ChartAxis || axis isa ChartCategoryAxis ? axis.title : ""
_axis_shows_title(axis) = (axis isa ChartAxis || axis isa ChartCategoryAxis) && axis.show_title
_axis_shows_labels(axis) = (axis isa ChartAxis || axis isa ChartCategoryAxis) && axis.show_labels
_axis_grid(axis) = axis isa ChartAxis ? axis.grid : :major

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

    yticks = _axis_ticks(y_axis, view.y_min, view.y_max, prov_h)
    xticks = _axis_ticks(x_axis, view.x_min, view.x_max, prov_w)
    ystep, xstep = _tick_step(yticks), _tick_step(xticks)

    ylabels = _axis_shows_labels(y_axis) ? [format_tick(t, ystep) for t in yticks] : String[]
    xlabels = _axis_shows_labels(x_axis) ? [format_tick(t, xstep) for t in xticks] : String[]

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

    plot_x = left
    plot_y = top
    plot_w = max(w - left - right, 20)
    plot_h = max(h - top - bottom, 20)

    xlog = x_axis isa ChartAxis && x_axis.log
    ylog = y_axis isa ChartAxis && y_axis.log
    xs = AxisScale(view.x_min, view.x_max, plot_x, plot_x + plot_w; log=xlog)
    ys = AxisScale(view.y_min, view.y_max, plot_y + plot_h, plot_y; log=ylog)

    (; w, h, chart, style, view, series,
       plot_x, plot_y, plot_w, plot_h, xs, ys,
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

    push!(out, GraphicsRect(0, 0, g.w, g.h, _or(style.background, _BACKGROUND)))
    push!(out, GraphicsRect(px, py, pw, ph, _or(style.plot_background, _PLOT_BACKGROUND)))

    chart = g.chart
    grid_x = _axis_grid(chart.x_axis)
    grid_y = _axis_grid(chart.y_axis)

    if grid_y !== :none
        for t in g.yticks
            y = round(Int, to_pixel(g.ys, t))
            (py <= y <= py + ph) || continue
            push!(out, GraphicsLine(px, y, px + pw, y, grid_color; dash=(2, 3)))
        end
    end
    if grid_x !== :none
        for t in g.xticks
            x = round(Int, to_pixel(g.xs, t))
            (px <= x <= px + pw) || continue
            push!(out, GraphicsLine(x, py, x, py + ph, grid_color; dash=(2, 3)))
        end
    end

    # The two axis lines, drawn over the grid.
    push!(out, GraphicsLine(px, py + ph, px + pw, py + ph, _AXIS))
    push!(out, GraphicsLine(px, py, px, py + ph, _AXIS))

    # Tick marks and their labels.
    for i in eachindex(g.ylabels)
        y = round(Int, to_pixel(g.ys, g.yticks[i]))
        (py - 1 <= y <= py + ph + 1) || continue
        push!(out, GraphicsLine(px - _TICK, y, px, y, _AXIS))
        tw, th = g.ysizes[i]
        push!(out, GraphicsText(g.ylabels[i], px - _TICK - _LABEL_GAP - tw, y - th ÷ 2,
                                g.axis_font, text_color))
    end
    for i in eachindex(g.xlabels)
        x = round(Int, to_pixel(g.xs, g.xticks[i]))
        (px - 1 <= x <= px + pw + 1) || continue
        push!(out, GraphicsLine(x, py + ph, x, py + ph + _TICK, _AXIS))
        tw, _ = g.xsizes[i]
        push!(out, GraphicsText(g.xlabels[i], x - tw ÷ 2, py + ph + _TICK + _LABEL_GAP,
                                g.axis_font, text_color))
    end

    isempty(g.title) ||
        push!(out, GraphicsText(g.title, px, _PAD, g.title_font, text_color))
    # No rotated text: the backends only honour the translate+scale subset of an
    # affine transform, so the y-axis title sits above the axis rather than
    # running up its side.
    isempty(g.y_title) ||
        push!(out, GraphicsText(g.y_title, px, _PAD + g.title_h, g.axis_font, text_color))
    isempty(g.x_title) ||
        push!(out, GraphicsText(g.x_title, px + pw ÷ 2, g.h - _PAD - g.x_title_h + 2,
                                g.axis_font, text_color))
    out
end

# ── Series elements ──────────────────────────────────────────────────────

# Marker shapes we can draw exactly with the primitives that exist. A filled
# polygon primitive does not exist yet, so diamonds/triangles/stars are absent
# rather than approximated out of line segments.
function _marker!(out, shape::Symbol, x::Int, y::Int, size::Int, color::StyleColor)
    r = max(size ÷ 2, 1)
    if shape === :circle
        push!(out, GraphicsCircle(x, y, r, color))
    elseif shape === :dot
        push!(out, GraphicsCircle(x, y, max(r ÷ 2, 1), color))
    elseif shape === :square
        push!(out, GraphicsRect(x - r, y - r, 2r, 2r, color))
    elseif shape === :plus
        push!(out, GraphicsLine(x - r, y, x + r, y, color))
        push!(out, GraphicsLine(x, y - r, x, y + r, color))
    elseif shape === :cross
        push!(out, GraphicsLine(x - r, y - r, x + r, y + r, color))
        push!(out, GraphicsLine(x - r, y + r, x + r, y - r, color))
    elseif shape === :hline
        push!(out, GraphicsLine(x - r, y, x + r, y, color))
    elseif shape === :vline
        push!(out, GraphicsLine(x, y - r, x, y + r, color))
    end
    out
end

# Pixel points for a line series over the visible window, already decimated and
# translated into the viewport's local frame.
function _line_points(g, s::ChartLineSeries)
    x, y = s.x, s.y
    (length(x) == 0 || length(y) == 0) && return Tuple{Int,Int}[]
    i0, i1 = visible_range(x, g.view.x_min, g.view.x_max; sorted=s.sorted)
    pts = decimate_minmax(x, y, g.xs, g.ys, i0, i1)
    ox, oy = g.plot_x, g.plot_y
    [(px - ox, py - oy) for (px, py) in pts]
end

function _line_elements!(out, g, index::Int, s::ChartLineSeries)
    style = g.style
    color = series_color(s.color, index, style.color_cycle)
    pts = _line_points(g, s)
    isempty(pts) && return out

    if s.draw_style === :pins
        baseline = round(Int, to_pixel(g.ys, 0.0)) - g.plot_y
        for (x, ytop, ybot) in pins_segments(pts, baseline)
            push!(out, GraphicsLine(x, ytop, x, ybot, color; width=max(s.line_width, 1)))
        end
    elseif s.draw_style !== :none
        shaped = s.draw_style === :linear ? pts : step_points(pts, s.draw_style)
        length(shaped) >= 2 &&
            push!(out, GraphicsPolyline(shaped, color; width=max(s.line_width, 1)))
    end

    shape = series_symbol(s.symbol, index, style.symbol_cycle)
    # Markers only while they still read as individual points; past that they
    # merge into a smear and the line already carries the shape.
    if shape !== :none && length(pts) <= style.marker_limit
        for (x, y) in pts
            _marker!(out, shape, x, y, s.symbol_size, color)
        end
    end
    out
end

_series_elements!(out, g, index::Int, s::ChartLineSeries) = _line_elements!(out, g, index, s)
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
    geometry = ComputedCell(() -> begin
        w, h = _canvas_size(p, ctx)
        _layout(p, plot, w, h)
    end)

    elements = CellVector(() -> begin
        g = geometry[]
        g === nothing && return _empty_elements(p, plot, ctx)
        out = Any[]
        _frame_elements!(out, g)

        series_out = Any[]
        for (index, s) in g.series
            if chart_series_family(s) === chart_axis_family(g.chart.x_axis)
                _series_elements!(series_out, g, index, s)
            end
        end
        content = GraphicsCanvas(0, 0, g.plot_w, g.plot_h,
                                 CellVector(Cell[Cell(e) for e in series_out]),
                                 layout_none, true)
        push!(out, GraphicsViewport(g.plot_x, g.plot_y, g.plot_w, g.plot_h, content))
        out
    end)

    # Width and height are computed rather than fixed so a resize reflows the
    # same canvas object instead of replacing it.
    size_cell = ComputedCell(() -> _canvas_size(p, ctx))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            ComputedCell(() -> Int32(size_cell[][1])),
                            ComputedCell(() -> Int32(size_cell[][2])),
                            Cell(elements), Cell(layout_none), Cell(true),
                            Cell(nothing))
    ChartPlotToGraphicsCanvasIoMap(p, plot, canvas, geometry)
end

# A chart-shaped placeholder for a `ChartNothing`/`ChartInsertion` root, so an
# empty chart still occupies its space and reads as a chart rather than
# vanishing.
function _empty_elements(p::ChartPlotToGraphicsCanvas, plot::ChartPlot, ctx)
    w, h = _canvas_size(p, ctx)
    Any[GraphicsRect(0, 0, w, h, _BACKGROUND),
        GraphicsRect(_PAD, _PAD, w - 2 * _PAD, h - 2 * _PAD, _PLOT_BACKGROUND, 4;
                     border_width=1, border_color=_AXIS),
        GraphicsText("empty chart", _PAD * 2, h ÷ 2, font_ubuntu_regular_14, _TEXT)]
end

# Selection mapping is added with the selectable chart parts; until then a
# selection has nowhere in the canvas to land.
map_reference_forward(::ChartPlotToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::ChartPlotToGraphicsCanvas, iomap, reference) = nothing

end # module
