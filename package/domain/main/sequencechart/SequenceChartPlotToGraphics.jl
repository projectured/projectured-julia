"""
    SequenceChartPlotToGraphicsModule

SequenceChartPlot → Graphics: the sequence chart renderer. Lanes, the
occurrences on them, the arrows between those, the state bands, and the time
scale alongside — all composed out of the existing graphics primitives, so a
sequence chart is vector output like every other projection and stays selectable
and resolution-independent.

**Three cells, not one.** The work splits by what invalidates it:

1. `timeline` — the cumulative pass that assigns every event a coordinate. It
   depends on the times and the mapping and nothing else, so panning, hovering
   or resizing never re-runs it.
2. `geometry` — the frame: the window, the lane positions, which events and
   arrows are visible, their decimated shapes, the ticks and their measured
   labels. It depends on the data and the size, and deliberately **not** on the
   pointer.
3. `elements` — the drawable list, which reads the geometry *and* the pointer
   state. Hover, selection and the cursor readout live only here, so moving the
   mouse rebuilds the overlay rather than re-deciding the layout.

That last split is the one worth keeping: hover on a dense chart changes at
pointer-move frequency, and re-deriving a layout over a hundred thousand arrows
at that rate is the difference between a chart that tracks the mouse and one
that lags behind it.

**Cost.** Events are decimated to at most one per lane per pixel and arrows to
the pixels they actually cover, so the element count is bounded by the size of
the chart rather than by the length of the trace.

**Tolerance.** A kind index that names nothing, an endpoint row that is out of
range, a lane column shorter than the event table — none of these throw. They
are drawn as far as they make sense and skipped where they do not, because a
chart is often being watched while something upstream is still writing it.
"""
module SequenceChartPlotToGraphicsModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..SequenceChartModule: SequenceChart, SequenceChartNothing, SequenceChartInsertion,
                              SequenceChartAxis, SequenceChartEvents, SequenceChartArrows,
                              SequenceChartBandSeries, SequenceChartEventKind,
                              SequenceChartArrowKind, SequenceChartStyle,
                              event_count, arrow_count, axis_display_order,
                              event_axis, event_kind, event_label,
                              arrow_kind, arrow_label,
                              arrow_source_axis, arrow_target_axis,
                              band_state_name,
                              event_reference, arrow_reference, band_reference,
                              axis_reference, selected_event, selected_arrow
import ..SequenceChartPlotModule: SequenceChartPlot, SequenceChartView
import ..SequenceChartGeometryModule: FlowFrame, flow_point, flow_rect,
                                      frame_flow_span, frame_cross_span,
                                      timeline_coordinates, default_nonlinear_focus,
                                      time_to_coordinate, coordinate_to_time,
                                      visible_event_range, visible_arrows,
                                      flow_ticks, honest_tick_label, tick_common_prefix,
                                      zero_time_spans, axis_cross_positions,
                                      arc_geometry, arc_height, split_arrow, arrow_route,
                                      decimate_events, arrow_coverage_dedup, band_intervals
import ..ChartGeometryModule: AxisScale, to_pixel, to_data
import ..ChartModule: series_color
import ..ChartPlotToGraphicsModule: marker_polygon
import ..GraphicsModule: GraphicsCanvas, GraphicsRect, GraphicsLine, GraphicsText,
                         GraphicsCircle, GraphicsPolyline, GraphicsPolygon,
                         GraphicsSpline, GraphicsViewport, layout_none
import ..ColorModule: StyleColor,
                      color_solarized_background_lighter, color_solarized_background_light,
                      color_solarized_content_dark, color_solarized_content_darker,
                      color_solarized_blue
import ..FontModule: StyleFont, font_ubuntu_regular_14, font_ubuntu_bold_16
import ..IoMapModule: IoMap, var"@iomap"
import ..EventModule: MousePress, MouseMove, MouseLeave, MouseScroll
import ..OperationModule: Operation, ReplaceSelectionOperation,
                          ReplaceReferencedValueOperation, CompoundOperation
import ..ReferenceModule: get_reference_node_type
import ..ReferenceBuilderModule: var"@reference"
import ..ReferenceCaseModule: var"@reference_case"

export SequenceChartPlotToGraphicsCanvas, SequenceChartPlotToGraphicsCanvasIoMap,
       resolve_window, lane_cross_position,
       event_hit, arrow_hit, band_hit, lane_hit, sequence_chart_reference

# ── Theme defaults ───────────────────────────────────────────────────────
# A `nothing` style field means "whatever the theme says"; these are that.

const _BACKGROUND = color_solarized_background_lighter
const _BODY_BACKGROUND = StyleColor(1.0, 1.0, 1.0, 1.0)
const _AXIS = color_solarized_content_dark
const _TEXT = color_solarized_content_darker
const _GUTTER = StyleColor(1.0, 1.0, 0.94, 1.0)
const _GUTTER_BORDER = StyleColor(0.0, 0.0, 0.0, 0.25)
const _HAIRLINE = StyleColor(0.0, 0.0, 0.0, 0.14)
const _ZERO_TIME = StyleColor(0.0, 0.0, 0.0, 0.055)
const _ARROW = color_solarized_blue
const _EVENT = StyleColor(0xd3 / 255, 0x36 / 255, 0x82 / 255, 1.0)

# Frame metrics, in logical pixels.
const _PAD = 8              # breathing room around the whole chart
const _GUTTER_PAD = 3       # inside a gutter, above and below its text
const _LABEL_GAP = 4        # between a lane and its label
const _TICK_TARGET_PX = 100 # aim for roughly one tick per this many pixels
const _LANE_MIN_SPACING = 16
const _LANE_OFFSET = 14     # from the body edge to the first lane
const _BAND_HEIGHT = 12     # a state strip's thickness

_or(value, fallback) = value === nothing ? fallback : value

"""
    SequenceChartPlotToGraphicsCanvas(; measure, width=900, height=520)

The sequence chart renderer. `measure(text, font) -> (w, h)` is how tick, lane
and arrow text is sized; pass `truetype_measure_text` for a backend-free
pipeline or `sdl_measure_text` when running against a live SDL window.

`width`/`height` are the fallback canvas size, used when the printer context
carries no allocation from a parent layout.

A plain struct rather than an `@projection`: `measure` is a `Function`, and a
`Function` in a reactive field would be read as a thunk and called.
"""
struct SequenceChartPlotToGraphicsCanvas <: Projection
    measure::Function
    width::Int
    height::Int
end

SequenceChartPlotToGraphicsCanvas(; measure::Function, width::Integer=900,
                                  height::Integer=520) =
    SequenceChartPlotToGraphicsCanvas(measure, Int(width), Int(height))

@iomap struct SequenceChartPlotToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    timeline::Cell     # the coordinate of every event, one cumulative pass
    geometry::Cell     # the laid-out frame: window, lanes, ticks, shapes
end

# ── The timeline pass ────────────────────────────────────────────────────

# The coordinate of every event, plus the times it was derived from. Kept in its
# own cell because it is the only O(n) pass over the whole trace, and nothing
# about looking at the chart should re-run it.
function _timeline(chart)
    chart isa SequenceChart || return nothing
    events = chart.events
    n = event_count(events)
    times = Float64[Float64(events.times[i]) for i in 1:n]
    timeline = chart.timeline
    coordinates = timeline_coordinates(times, events.ordinals, timeline.mode;
                                       focus=timeline.nonlinear_focus,
                                       minimum=timeline.nonlinear_minimum)
    (; times, coordinates)
end

# ── The window ───────────────────────────────────────────────────────────

"""
    resolve_window(plot, coordinates) -> (lo, hi)

The coordinate window actually shown: the plot's own, or the whole trace when it
is fitting.

A window is stored relative to an anchor event, so this is where that becomes an
absolute pair. An anchor that has gone out of range — the event it named was
filtered away — falls back to fitting rather than showing an empty stretch of
nothing.

`follow_end` keeps the span but pins its end to the newest event, which is what
lets a chart track a trace that is still being written.
"""
function resolve_window(plot::SequenceChartPlot, coordinates)
    n = length(coordinates)
    n == 0 && return (0.0, 1.0)
    full_lo = coordinates[1]
    full_hi = coordinates[n]
    full_hi > full_lo || (full_hi = full_lo + 1.0)

    view = plot.view
    if view === nothing
        plot.follow_end || return (full_lo, full_hi)
        return (full_lo, full_hi)
    end
    (1 <= view.anchor <= n) || return (full_lo, full_hi)
    span = view.span > 0 ? view.span : (full_hi - full_lo)
    plot.follow_end && return (full_hi - span, full_hi)
    lo = coordinates[view.anchor] + view.offset
    (lo, lo + span)
end

# ── Layout ───────────────────────────────────────────────────────────────

# The whole frame in one pass: the window, the lane positions, what is visible,
# the shapes, and the ticks with their measured labels.
#
# Deliberately independent of the pointer: hover, selection and the cursor are
# read by the element pass instead, so moving the mouse never lands here.
function _layout(p::SequenceChartPlotToGraphicsCanvas, plot::SequenceChartPlot,
                 timeline, w::Int, h::Int)
    chart = plot.chart
    chart isa SequenceChart || return nothing
    timeline === nothing && return nothing
    style = chart.style
    label_font = _or(style.label_font, font_ubuntu_regular_14)
    axis_font = _or(style.axis_label_font, font_ubuntu_regular_14)
    title_font = font_ubuntu_bold_16

    times, coordinates = timeline.times, timeline.coordinates
    vertical = chart.orientation === :vertical
    lo, hi = resolve_window(plot, coordinates)
    hi > lo || (hi = lo + 1.0)

    title = chart.title
    title_h = isempty(title) ? 0 : p.measure(title, title_font)[2] + _PAD ÷ 2

    order = axis_display_order(chart)
    labels = String[String(chart.axes[i].label) for i in order]
    label_sizes = Tuple{Int,Int}[p.measure(l, axis_font) for l in labels]
    label_w = isempty(label_sizes) ? 0 : maximum(sz[1] for sz in label_sizes)
    label_h = p.measure("0", axis_font)[2]

    gutter = chart.gutter
    gutter_h = gutter.visible ? label_h + 2 * _GUTTER_PAD : 0

    # The lane labels take a strip beside the body when time runs across, and a
    # header band above it when time runs down — in both cases outside the body,
    # so they stay put while the content scrolls.
    if vertical
        left = _PAD
        right = _PAD
        top = _PAD + title_h + label_h + _LABEL_GAP + gutter_h
        bottom = _PAD + gutter_h
    else
        left = _PAD + label_w + _LABEL_GAP
        right = _PAD
        top = _PAD + title_h + gutter_h
        bottom = _PAD + gutter_h
    end

    body_x = left
    body_y = top
    body_w = max(w - left - right, 40)
    body_h = max(h - top - bottom, 40)
    # The frame is **local** to the body: everything it places is drawn inside a
    # viewport positioned at (body_x, body_y), which adds that origin back. The
    # chrome outside the viewport adds it explicitly instead.
    frame = FlowFrame(chart.orientation, 0, 0, body_w, body_h)

    flow_lo, flow_hi = frame_flow_span(frame)
    cross_lo, cross_hi = frame_cross_span(frame)
    scale = AxisScale(lo, hi, flow_lo, flow_hi)

    # A lane carrying a band needs room for the strip as well as the line.
    band_heights = Float64[_lane_band_height(chart.axes[i]) for i in order]
    lanes = axis_cross_positions(length(order), band_heights, cross_lo, cross_hi;
                                 spacing=style.axis_spacing,
                                 minimum_spacing=_LANE_MIN_SPACING,
                                 offset=_LANE_OFFSET)
    # Lane identity → cross position, so an event finds its lane by the index it
    # actually carries rather than by where it happens to be drawn.
    lane_of = Dict{Int,Float64}()
    for (position, identity) in zip(lanes, order)
        lane_of[identity] = position
    end

    events = chart.events
    arrows = chart.arrows
    i0, i1 = visible_event_range(coordinates, lo, hi)
    visible_events = decimate_events(coordinates, events.axes, scale, i0, i1;
                                     kinds=events.kinds,
                                     separation=max(style.event_radius, 1))
    # Only events whose kind is switched on, and whose lane exists.
    visible_events = Int[i for i in visible_events
                         if _event_visible(chart, events, i) && haskey(lane_of, event_axis(events, i))]

    horizon = abs(flow_hi - flow_lo) * max(style.split_horizon_viewports, 1)
    horizon_coordinates = horizon / max(abs(scale.p1 - scale.p0), 1) * (hi - lo)
    candidates = visible_arrows(coordinates, arrows.sources, arrows.targets, lo, hi;
                                horizon=horizon_coordinates)
    shapes = _arrow_shapes(chart, events, arrows, coordinates, scale, lane_of,
                           candidates, horizon, style)

    ticks = flow_ticks(times, coordinates, scale, chart.timeline.mode;
                       target_px=_TICK_TARGET_PX)
    neighbourhood = _tick_neighbourhood(times, coordinates, scale, ticks)
    raw_labels = String[honest_tick_label(t, neighbourhood) for (_, t) in ticks]
    prefix, tick_labels = tick_common_prefix(raw_labels)

    zero_spans = style.zero_time_shading ? zero_time_spans(times, coordinates, lo, hi) :
                                           Tuple{Float64,Float64}[]

    bands = _band_shapes(chart, order, lane_of, times, coordinates, lo, hi)

    (; w, h, chart, style, plot, frame, vertical, scale, lo, hi,
       times, coordinates, order, lanes, lane_of, labels, label_sizes,
       label_w, label_h, label_font, axis_font, title, title_font, title_h,
       gutter_h, ticks, tick_labels, prefix, zero_spans,
       visible_events, shapes, bands,
       body_x, body_y, body_w, body_h,
       measure = p.measure)
end

_lane_band_height(axis::SequenceChartAxis) = length(axis.bands) > 0 ? Float64(_BAND_HEIGHT) : 0.0

# How much time one tick's pixel stands for — what decides how many digits a
# tick label may honestly show.
function _tick_neighbourhood(times, coordinates, scale::AxisScale, ticks)
    length(ticks) >= 2 || return 0.0
    (c0, t0) = ticks[1]
    (c1, t1) = ticks[2]
    pixels = abs(to_pixel(scale, c1) - to_pixel(scale, c0))
    pixels > 0 || return 0.0
    abs(t1 - t0) / pixels / 2
end

# ── Arrow shapes ─────────────────────────────────────────────────────────

# Each visible arrow reduced to what the renderer draws: the route it takes, the
# pixel coordinates of its ends, and whether it had to be split. Computing this
# once here keeps the drawing pass a straight walk and gives the reader the same
# geometry to hit-test against.
function _arrow_shapes(chart, events, arrows, coordinates, scale, lane_of,
                       candidates, horizon, style)
    shapes = Any[]
    flows = Tuple{Float64,Float64}[]
    crosses = Tuple{Float64,Float64}[]
    kept = Int[]
    n = length(coordinates)

    for k in candidates
        kind = _arrow_kind_document(chart, arrow_kind(arrows, k))
        (kind === nothing || kind.visible) || continue
        source = Int(arrows.sources[k]); target = Int(arrows.targets[k])
        (1 <= source <= n && 1 <= target <= n) || continue
        source_lane = arrow_source_axis(arrows, events, k)
        target_lane = arrow_target_axis(arrows, events, k)
        (haskey(lane_of, source_lane) && haskey(lane_of, target_lane)) || continue

        f0 = to_pixel(scale, coordinates[source])
        f1 = to_pixel(scale, coordinates[target])
        c0 = lane_of[source_lane]
        c1 = lane_of[target_lane]
        push!(kept, k)
        push!(flows, (f0, f1))
        push!(crosses, (c0, c1))
    end

    surviving = arrow_coverage_dedup(kept, flows, crosses)
    positions = Dict{Int,Int}(k => i for (i, k) in enumerate(kept))

    for k in surviving
        index = positions[k]
        f0, f1 = flows[index]
        c0, c1 = crosses[index]
        kind = _arrow_kind_document(chart, arrow_kind(arrows, k))
        route = arrow_route(kind === nothing ? :auto : kind.route, c0 == c1)
        split = split_arrow(f0, f1, horizon, style.split_stub_px)
        height = route === :arc ?
            arc_height(Int(arrows.targets[k]) - Int(arrows.sources[k]), abs(c1 - c0) == 0 ?
                       Float64(style.arc_min_height) * 2 : abs(c1 - c0);
                       minimum=style.arc_min_height, buckets=style.arc_height_buckets) : 0.0
        push!(shapes, (; index=k, route, f0, f1, c0, c1, split, height, kind))
    end
    shapes
end

# ── Band shapes ──────────────────────────────────────────────────────────

function _band_shapes(chart, order, lane_of, times, coordinates, lo, hi)
    out = Any[]
    for identity in order
        axis = chart.axes[identity]
        haskey(lane_of, identity) || continue
        cross = lane_of[identity]
        for j in 1:length(axis.bands)
            band = axis.bands[j]
            intervals = band_intervals(band.times, band.values, band.events,
                                       times, coordinates, lo, hi)
            isempty(intervals) && continue
            push!(out, (; axis=identity, band=j, cross, intervals, document=band))
        end
    end
    out
end

# ── Kind lookup ──────────────────────────────────────────────────────────
#
# A kind index that names nothing is not an error: an upstream domain may be
# mid-write, or a chart may simply not classify its events. It falls back to the
# domain's default mark rather than throwing.

function _event_kind_document(chart, index::Integer)
    (1 <= index <= length(chart.event_kinds)) || return nothing
    chart.event_kinds[index]
end

function _arrow_kind_document(chart, index::Integer)
    (1 <= index <= length(chart.arrow_kinds)) || return nothing
    chart.arrow_kinds[index]
end

_event_visible(chart, events, i::Integer) =
    let kind = _event_kind_document(chart, event_kind(events, i))
        kind === nothing || kind.visible
    end

_kind_color(kind, index::Integer, cycle, fallback) =
    kind === nothing ? fallback :
        (kind.color === nothing ? series_color(nothing, index, cycle) : kind.color)

# ── Elements ─────────────────────────────────────────────────────────────

# The chart's frame: background, title, the gutters with their ticks, the lane
# labels. Everything here lives outside the scrolling body, so it stays put.
function _frame_elements!(out, g)
    style = g.style
    push!(out, GraphicsRect(0, 0, g.w, g.h, _or(style.background, _BACKGROUND)))
    push!(out, GraphicsRect(round(Int, g.body_x), round(Int, g.body_y),
                            round(Int, g.body_w), round(Int, g.body_h),
                            _BODY_BACKGROUND))

    text_color = _or(style.tick_color, _TEXT)
    isempty(g.title) ||
        push!(out, GraphicsText(g.title, _PAD, _PAD, g.title_font, text_color))

    _gutter_elements!(out, g)
    _lane_label_elements!(out, g)
    out
end

# The time scale: a strip at each end of the body with a label at every tick, and
# the shared leading digits pulled out into a prefix so the labels show only what
# actually varies.
function _gutter_elements!(out, g)
    gutter = g.chart.gutter
    gutter.visible || return out
    style = g.style
    background = _or(style.gutter_background, _GUTTER)
    text_color = _or(style.tick_color, _TEXT)
    height = g.gutter_h

    for (strip_x, strip_y, strip_w, strip_h) in _gutter_rects(g, height)
        push!(out, GraphicsRect(round(Int, strip_x), round(Int, strip_y),
                                round(Int, strip_w), round(Int, strip_h),
                                background; border_width=1, border_color=_GUTTER_BORDER))
    end

    isempty(g.prefix) ||
        push!(out, GraphicsText(g.prefix, round(Int, g.body_x), _PAD + g.title_h,
                                g.axis_font, text_color))

    # Both strips carry the labels: a reader following an arrow across the chart
    # should not have to travel back to one edge to find out when it happened.
    for (index, (coordinate, _)) in enumerate(g.ticks)
        index <= length(g.tick_labels) || break
        label = g.tick_labels[index]
        isempty(label) && continue
        text = isempty(g.prefix) ? label : string("+", label)
        flow = to_pixel(g.scale, coordinate)
        size = g.measure(text, g.axis_font)
        if g.vertical
            y = round(Int, flow + g.body_y - size[2] / 2)
            push!(out, GraphicsText(text, round(Int, g.body_x - size[1] - _LABEL_GAP),
                                    y, g.axis_font, text_color))
            push!(out, GraphicsText(text, round(Int, g.body_x + g.body_w + _LABEL_GAP),
                                    y, g.axis_font, text_color))
        else
            x = round(Int, flow + g.body_x - size[1] / 2)
            push!(out, GraphicsText(text, x,
                                    round(Int, g.body_y - height + _GUTTER_PAD),
                                    g.axis_font, text_color))
            push!(out, GraphicsText(text, x,
                                    round(Int, g.body_y + g.body_h + _GUTTER_PAD),
                                    g.axis_font, text_color))
        end
    end
    out
end

# The two strips a gutter occupies, one at each end of the body.
function _gutter_rects(g, height::Integer)
    height <= 0 && return ()
    if g.vertical
        ((g.body_x - height, g.body_y, height, g.body_h),
         (g.body_x + g.body_w, g.body_y, height, g.body_h))
    else
        ((g.body_x, g.body_y - height, g.body_w, height),
         (g.body_x, g.body_y + g.body_h, g.body_w, height))
    end
end

# A lane's name, beside its line when time runs across and above the body when
# time runs down. Horizontal in both cases — the backends do not rotate text.
function _lane_label_elements!(out, g)
    text_color = _or(g.style.axis_color, _TEXT)
    for (position, identity) in enumerate(g.order)
        position <= length(g.lanes) || break
        label = g.labels[position]
        isempty(label) && continue
        size = g.label_sizes[position]
        cross = g.lanes[position]
        if g.vertical
            push!(out, GraphicsText(label, round(Int, cross + g.body_x - size[1] / 2),
                                    round(Int, g.body_y - g.label_h - _LABEL_GAP),
                                    g.axis_font, text_color))
        else
            push!(out, GraphicsText(label, round(Int, g.body_x - size[1] - _LABEL_GAP),
                                    round(Int, cross + g.body_y - size[2] / 2),
                                    g.axis_font, text_color))
        end
    end
    out
end

# The body: what scrolls and what is clipped. Drawn back to front — the stretches
# where the clock stands still, the hairlines, the lanes, the bands, the arrows,
# then the events on top of the arrows that connect them.
function _body_elements!(out, g)
    _zero_time_elements!(out, g)
    _hairline_elements!(out, g)
    _lane_elements!(out, g)
    _band_elements!(out, g)
    _arrow_elements!(out, g)
    _event_elements!(out, g)
    out
end

# Where the clock stands still. Under any mapping but :time these stretches have
# width, and width normally reads as duration — so without marking them the
# picture would lie about how long things took.
function _zero_time_elements!(out, g)
    cross_lo, cross_hi = frame_cross_span(g.frame)
    for (c0, c1) in g.zero_spans
        f0 = to_pixel(g.scale, c0); f1 = to_pixel(g.scale, c1)
        f1 - f0 >= 1 || continue
        x, y, w, h = flow_rect(g.frame, f0, cross_lo, f1 - f0, cross_hi - cross_lo)
        push!(out, GraphicsRect(round(Int, x), round(Int, y),
                                round(Int, w), round(Int, h), _ZERO_TIME))
    end
    out
end

function _hairline_elements!(out, g)
    g.chart.gutter.hairlines || return out
    cross_lo, cross_hi = frame_cross_span(g.frame)
    for (coordinate, _) in g.ticks
        flow = to_pixel(g.scale, coordinate)
        x0, y0 = flow_point(g.frame, flow, cross_lo)
        x1, y1 = flow_point(g.frame, flow, cross_hi)
        push!(out, GraphicsLine(round(Int, x0), round(Int, y0),
                                round(Int, x1), round(Int, y1), _HAIRLINE, 1, (2, 3)))
    end
    out
end

function _lane_elements!(out, g)
    flow_lo, flow_hi = frame_flow_span(g.frame)
    default = _or(g.style.axis_color, _AXIS)
    for (position, identity) in enumerate(g.order)
        position <= length(g.lanes) || break
        axis = g.chart.axes[identity]
        axis.visible || continue
        cross = g.lanes[position]
        x0, y0 = flow_point(g.frame, flow_lo, cross)
        x1, y1 = flow_point(g.frame, flow_hi, cross)
        push!(out, GraphicsLine(round(Int, x0), round(Int, y0),
                                round(Int, x1), round(Int, y1),
                                _or(axis.color, default), 1, nothing))
    end
    out
end

# A state strip: one filled rectangle per held value, with the value's name
# inside when it fits. The strip sits just off the lane so the lane's own events
# stay legible.
function _band_elements!(out, g)
    cycle = g.style.color_cycle
    for band in g.bands
        document = band.document
        for (c0, c1, value, index) in band.intervals
            f0 = to_pixel(g.scale, c0); f1 = to_pixel(g.scale, c1)
            width = f1 - f0
            width >= 1 || continue
            color = _band_color(document, value, cycle)
            x, y, w, h = flow_rect(g.frame, f0, band.cross - _BAND_HEIGHT - 2,
                                   width, _BAND_HEIGHT)
            push!(out, GraphicsRect(round(Int, x), round(Int, y),
                                    round(Int, w), round(Int, h), color))
            g.style.band_labels || continue
            name = band_state_name(document, value)
            isempty(name) && continue
            size = g.measure(name, g.axis_font)
            size[1] + 6 <= w || continue
            push!(out, GraphicsText(name, round(Int, x + (w - size[1]) / 2),
                                    round(Int, y + (h - size[2]) / 2),
                                    g.axis_font, _TEXT))
        end
    end
    out
end

function _band_color(band::SequenceChartBandSeries, value::Real, cycle)
    colors = band.colors
    index = round(Int, value) + 1
    if colors !== nothing && 1 <= index <= length(colors)
        return colors[index]
    end
    color = series_color(nothing, max(index, 1), cycle)
    StyleColor(color.red, color.green, color.blue, 0.45)
end

# The arrows. A same-lane arrow arcs off its lane, because a straight line along
# a lane would be invisible inside it; a long one is drawn as two stubs, because
# at that length the line says nothing its ends do not.
function _arrow_elements!(out, g)
    style = g.style
    cycle = style.color_cycle
    for shape in g.shapes
        kind = shape.kind
        color = _kind_color(kind, shape.index, cycle, _ARROW)
        dash = _line_dash(kind === nothing ? :solid : kind.line_style)
        head = kind === nothing ? true : kind.arrowhead
        if shape.route === :arc
            _arc_elements!(out, g, shape, color, dash, head)
        elseif shape.split === nothing
            x0, y0 = flow_point(g.frame, shape.f0, shape.c0)
            x1, y1 = flow_point(g.frame, shape.f1, shape.c1)
            push!(out, GraphicsPolyline([(round(Int, x0), round(Int, y0)),
                                         (round(Int, x1), round(Int, y1))],
                                        color; width=style.arrow_width, dash=dash,
                                        end_arrow=head, arrow_size=style.arrowhead_size))
        else
            _split_elements!(out, g, shape, color, dash, head)
        end
        (kind !== nothing && kind.elided) && _elided_marker!(out, g, shape, color)
        _arrow_label!(out, g, shape, color)
    end
    out
end

function _arc_elements!(out, g, shape, color, dash, head)
    points = arc_geometry(shape.f0, shape.f1, shape.c0, shape.height)
    placed = [(round(Int, x), round(Int, y))
              for (x, y) in (flow_point(g.frame, f, c) for (f, c) in points)]
    push!(out, GraphicsSpline(placed, color; kind=:bezier, width=g.style.arrow_width,
                              dash=dash, end_arrow=head,
                              arrow_size=g.style.arrowhead_size))
    out
end

# A split arrow: each end keeps a stub of its own. The anchored end draws solid
# and the continuing end dotted, so the pair reads as "this goes on past the
# edge" rather than as two unrelated marks.
function _split_elements!(out, g, shape, color, dash, head)
    near, far = shape.split
    x0, y0 = flow_point(g.frame, near[1], shape.c0)
    x1, y1 = flow_point(g.frame, near[2], shape.c0)
    push!(out, GraphicsPolyline([(round(Int, x0), round(Int, y0)),
                                 (round(Int, x1), round(Int, y1))],
                                color; width=g.style.arrow_width, dash=dash))
    x2, y2 = flow_point(g.frame, far[2], shape.c1)
    x3, y3 = flow_point(g.frame, far[1], shape.c1)
    push!(out, GraphicsPolyline([(round(Int, x2), round(Int, y2)),
                                 (round(Int, x3), round(Int, y3))],
                                color; width=g.style.arrow_width, dash=(2, 3),
                                end_arrow=head, arrow_size=g.style.arrowhead_size))
    out
end

# The mark that says a chain of hidden steps was summarised into this one arrow.
# Without it a filtered chart would claim a directness it does not have.
function _elided_marker!(out, g, shape, color)
    mid_flow = (shape.f0 + shape.f1) / 2
    mid_cross = (shape.c0 + shape.c1) / 2
    points = Tuple{Int,Int}[]
    for (offset, side) in ((-4, -3), (-1, 3), (2, -3), (5, 3))
        x, y = flow_point(g.frame, mid_flow + offset, mid_cross + side)
        push!(points, (round(Int, x), round(Int, y)))
    end
    push!(out, GraphicsPolyline(points, color; width=1))
    out
end

function _arrow_label!(out, g, shape, color)
    g.style.arrow_labels || return out
    label = arrow_label(g.chart.arrows, shape.index)
    (label === nothing || isempty(label)) && return out
    mid_flow = (shape.f0 + shape.f1) / 2
    mid_cross = (shape.c0 + shape.c1) / 2
    size = g.measure(label, g.axis_font)
    x, y = flow_point(g.frame, mid_flow, mid_cross)
    # An arrow can sit against an edge of the window while its label does not
    # fit there; nudging the text back inside keeps it readable rather than
    # letting the viewport cut it in half.
    x = clamp(x - size[1] / 2, 0, max(g.body_w - size[1], 0))
    y = clamp(y - size[2] - 3, 0, max(g.body_h - size[2], 0))
    push!(out, GraphicsText(label, round(Int, x), round(Int, y), g.axis_font, _TEXT))
    out
end

_line_dash(style::Symbol) =
    style === :dashed ? (5, 3) : style === :dotted ? (2, 2) : nothing

function _event_elements!(out, g)
    events = g.chart.events
    style = g.style
    cycle = style.color_cycle
    radius = style.event_radius
    for i in g.visible_events
        lane = event_axis(events, i)
        haskey(g.lane_of, lane) || continue
        kind_index = event_kind(events, i)
        kind = _event_kind_document(g.chart, kind_index)
        color = _kind_color(kind, max(kind_index, 1), cycle, _EVENT)
        flow = to_pixel(g.scale, g.coordinates[i])
        x, y = flow_point(g.frame, flow, g.lane_of[lane])
        symbol = kind === nothing ? :circle : kind.symbol
        _mark!(out, symbol, round(Int, x), round(Int, y), radius, color)
        style.event_labels || continue
        label = event_label(events, i)
        (label === nothing || isempty(label)) && continue
        size = g.measure(label, g.axis_font)
        push!(out, GraphicsText(label, round(Int, x + radius + 2),
                                round(Int, y + radius), g.axis_font, _TEXT))
    end
    out
end

# An event's mark. The shapes come from the chart slice's marker vocabulary, so
# the two domains stay recognisably one family.
function _mark!(out, symbol::Symbol, x::Int, y::Int, radius::Int, color)
    if symbol === :circle || symbol === :dot
        push!(out, GraphicsCircle(x, y, radius, color))
    elseif symbol === :square
        push!(out, GraphicsRect(x - radius, y - radius, 2 * radius, 2 * radius, color))
    else
        points = marker_polygon(symbol, x, y, radius)
        if points === nothing
            push!(out, GraphicsCircle(x, y, radius, color))
        else
            push!(out, GraphicsPolygon(points, color))
        end
    end
    out
end

# ── Overlay ──────────────────────────────────────────────────────────────
#
# What is selected and what is under the pointer. Kept out of the layout on
# purpose: these change at pointer-move frequency, and re-deriving a frame over
# a long trace that often is the difference between a chart that follows the
# mouse and one that trails it.

const _SELECTION = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.9)
const _HOVER = StyleColor(0x26 / 255, 0x8b / 255, 0xd2 / 255, 0.45)

# Which occurrence and arrow a reference names, once the plot's own `chart` step
# is off. Selection arrives already in the plot's vocabulary, so both are peeled
# the same way.
function _overlay_rows(g, plot)
    chart = g.chart
    chart isa SequenceChart || return (0, 0, 0, 0)
    (_row_of(plot.hovered, :events), _row_of(plot.hovered, :arrows),
     _row_of(plot.selection, :events), _row_of(plot.selection, :arrows))
end

function _row_of(reference, table::Symbol)
    reference === nothing && return 0
    @reference_case reference begin
        ::SequenceChartPlot.chart.events.row(k) => (table === :events ? k : 0)
        ::SequenceChartPlot.chart.arrows.row(k) => (table === :arrows ? k : 0)
        __ => 0
    end
end

function _overlay_elements!(out, g, plot)
    hovered_event, hovered_arrow, selected_event_row, selected_arrow_row =
        _overlay_rows(g, plot)

    # A selected occurrence gets a ring around it rather than a different fill:
    # the mark's own colour carries its kind, and overwriting that to say
    # "selected" would cost the reader the very thing they selected it to see.
    for (row, color) in ((selected_event_row, _SELECTION), (hovered_event, _HOVER))
        row == 0 && continue
        _event_ring!(out, g, row, color)
    end
    for (row, color) in ((selected_arrow_row, _SELECTION), (hovered_arrow, _HOVER))
        row == 0 && continue
        _arrow_highlight!(out, g, row, color)
    end
    _cursor_elements!(out, g, plot)
    out
end

function _event_ring!(out, g, row::Integer, color)
    (1 <= row <= length(g.coordinates)) || return out
    lane = event_axis(g.chart.events, row)
    position = get(g.lane_of, lane, nothing)
    position === nothing && return out
    flow = to_pixel(g.scale, g.coordinates[row])
    x, y = flow_point(g.frame, flow, position)
    radius = g.style.event_radius + 4
    # Transparent fill, so the mark underneath still shows through the ring.
    push!(out, GraphicsCircle(round(Int, x), round(Int, y), radius,
                              StyleColor(0.0, 0.0, 0.0, 0.0);
                              border_width=2, border_color=color))
    out
end

function _arrow_highlight!(out, g, row::Integer, color)
    for shape in g.shapes
        shape.index == row || continue
        if shape.route === :arc
            points = arc_geometry(shape.f0, shape.f1, shape.c0, shape.height)
            placed = [(round(Int, x), round(Int, y))
                      for (x, y) in (flow_point(g.frame, f, c) for (f, c) in points)]
            push!(out, GraphicsSpline(placed, color; kind=:bezier, width=3))
        else
            x0, y0 = flow_point(g.frame, shape.f0, shape.c0)
            x1, y1 = flow_point(g.frame, shape.f1, shape.c1)
            push!(out, GraphicsPolyline([(round(Int, x0), round(Int, y0)),
                                         (round(Int, x1), round(Int, y1))],
                                        color; width=3))
        end
        break
    end
    out
end

# The pointer's own line through the chart, so the eye can carry a moment across
# every lane at once — the same job the tick hairlines do, for a time that has no
# tick.
function _cursor_elements!(out, g, plot)
    cursor = plot.cursor
    cursor === nothing && return out
    g.chart.gutter.cursor_readout || return out
    coordinate = time_to_coordinate(g.times, g.coordinates, cursor)
    flow = to_pixel(g.scale, coordinate)
    cross_lo, cross_hi = frame_cross_span(g.frame)
    x0, y0 = flow_point(g.frame, flow, cross_lo)
    x1, y1 = flow_point(g.frame, flow, cross_hi)
    push!(out, GraphicsLine(round(Int, x0), round(Int, y0),
                            round(Int, x1), round(Int, y1), _SELECTION, 1, (3, 3)))
    out
end

# The two readouts in the gutter: the time under the pointer, and the extent of
# the window. Both are chrome, so they go in the outer canvas where the body's
# clipping cannot reach them.
function _readout_elements!(out, g, plot)
    gutter = g.chart.gutter
    gutter.visible || return out
    text_color = _or(g.style.tick_color, _TEXT)

    if gutter.cursor_readout && plot.cursor !== nothing
        text = honest_tick_label(plot.cursor, _cursor_neighbourhood(g))
        size = g.measure(text, g.axis_font)
        flow = to_pixel(g.scale, time_to_coordinate(g.times, g.coordinates, plot.cursor))
        if g.vertical
            y = round(Int, flow + g.body_y - size[2] / 2)
            push!(out, GraphicsRect(round(Int, g.body_x - size[1] - _LABEL_GAP - 2), y - 1,
                                    size[1] + 4, size[2] + 2, _SELECTION))
            push!(out, GraphicsText(text, round(Int, g.body_x - size[1] - _LABEL_GAP),
                                    y, g.axis_font, _BODY_BACKGROUND))
        else
            x = round(Int, flow + g.body_x - size[1] / 2)
            y = round(Int, g.body_y - g.gutter_h + _GUTTER_PAD)
            push!(out, GraphicsRect(x - 2, y - 1, size[1] + 4, size[2] + 2, _SELECTION))
            push!(out, GraphicsText(text, x, y, g.axis_font, _BODY_BACKGROUND))
        end
    end

    if gutter.range_readout
        span = coordinate_to_time(g.times, g.coordinates, g.hi) -
               coordinate_to_time(g.times, g.coordinates, g.lo)
        text = string(honest_tick_label(coordinate_to_time(g.times, g.coordinates, g.lo),
                                        _cursor_neighbourhood(g)),
                      " … Δ", honest_tick_label(span, _cursor_neighbourhood(g)))
        size = g.measure(text, g.axis_font)
        push!(out, GraphicsText(text, round(Int, g.w - size[1] - _PAD),
                                _PAD, g.axis_font, text_color))
    end
    out
end

# How much time one pixel stands for — the bound on how many digits a readout
# may honestly show.
function _cursor_neighbourhood(g)
    pixels = abs(g.scale.p1 - g.scale.p0)
    pixels > 0 || return 0.0
    t_lo = coordinate_to_time(g.times, g.coordinates, g.lo)
    t_hi = coordinate_to_time(g.times, g.coordinates, g.hi)
    abs(t_hi - t_lo) / pixels / 2
end

# ── Printer ──────────────────────────────────────────────────────────────

# Canvas size: whatever a parent layout allocated, else the projection's own
# fallback. Reading the cells here registers the dependency, so a resize
# reflows without re-projecting.
function _canvas_size(p::SequenceChartPlotToGraphicsCanvas, ctx)
    aw = ctx === nothing ? nothing : ctx.available_width
    ah = ctx === nothing ? nothing : ctx.available_height
    w = aw === nothing ? p.width : something(aw[], p.width)
    h = ah === nothing ? p.height : something(ah[], p.height)
    (max(Int(w), 160), max(Int(h), 100))
end

function print_document(p::SequenceChartPlotToGraphicsCanvas, recursion,
                        plot::SequenceChartPlot, ctx)
    # One cumulative pass over the trace, isolated so that looking at the chart
    # never re-runs it.
    timeline = ComputedCell(() -> _timeline(plot.chart))

    geometry = ComputedCell(() -> begin
        w, h = _canvas_size(p, ctx)
        _layout(p, plot, timeline[], w, h)
    end)

    elements = ComputedCellVector(() -> begin
        g = geometry[]
        g === nothing && return _empty_elements(p, plot, ctx)
        out = Any[]
        _frame_elements!(out, g)

        body = Any[]
        _body_elements!(body, g)
        # Hover and selection are read *here* rather than in the layout, so
        # moving the pointer over a dense chart rebuilds this list and nothing
        # else. They draw last, over everything they call out.
        _overlay_elements!(body, g, plot)
        _readout_elements!(out, g, plot)

        # Cross scrolling is a translation of the body, not a relayout: which
        # lanes are in view changes nothing about the flow axis, the decimation
        # or the shapes.
        offset = plot.cross_offset
        content = GraphicsCanvas(g.vertical ? -offset : 0, g.vertical ? 0 : -offset,
                                 round(Int, g.body_w), round(Int, g.body_h),
                                 CellVector(Cell[Cell(e) for e in body]),
                                 layout_none, true)
        push!(out, GraphicsViewport(round(Int, g.body_x), round(Int, g.body_y),
                                    round(Int, g.body_w), round(Int, g.body_h), content))
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
    SequenceChartPlotToGraphicsCanvasIoMap(p, plot, canvas, timeline, geometry)
end

# A chart-shaped placeholder for an empty or not-yet-typed root, so it still
# occupies its space and reads as a chart rather than vanishing.
function _empty_elements(p::SequenceChartPlotToGraphicsCanvas, plot::SequenceChartPlot, ctx)
    w, h = _canvas_size(p, ctx)
    Any[GraphicsRect(0, 0, w, h, _BACKGROUND),
        GraphicsRect(_PAD, _PAD, w - 2 * _PAD, h - 2 * _PAD, _BODY_BACKGROUND, 4;
                     border_width=1, border_color=_AXIS),
        GraphicsText("empty sequence chart", _PAD * 2, h ÷ 2,
                     font_ubuntu_regular_14, _TEXT)]
end

"""
    lane_cross_position(geometry, identity) -> Float64 | nothing

Where a lane sits on the cross axis, by lane identity. Exposed because the
reader hit-tests against the same positions the printer drew.
"""
lane_cross_position(g, identity::Integer) = get(g.lane_of, Int(identity), nothing)

# A chart part is not a cursor position: there is nowhere in the canvas for a
# selection to land, and no output element a reference should follow. Selection
# is instead expressed by what the reader selects and what the overlay
# highlights, so both mappers decline.
map_reference_forward(::SequenceChartPlotToGraphicsCanvas, iomap, reference) = nothing
map_reference_backward(::SequenceChartPlotToGraphicsCanvas, iomap, reference) = nothing

# ── Hit testing ──────────────────────────────────────────────────────────
#
# Against the same laid-out frame the printer drew, so the two can never
# disagree about where anything is. Canvas coordinates come in; the body's
# origin and the cross scroll come off first.

_in_rect(x, y, rx, ry, rw, rh) = rx <= x < rx + rw && ry <= y < ry + rh

# Canvas point → body-local (flow, cross).
function _local_flow_cross(g, plot, x::Real, y::Real)
    lx = Float64(x) - g.body_x
    ly = Float64(y) - g.body_y
    offset = Float64(plot.cross_offset)
    g.vertical ? (ly, lx + offset) : (lx, ly + offset)
end

_in_body(g, x::Real, y::Real) = _in_rect(x, y, g.body_x, g.body_y, g.body_w, g.body_h)

"""
    event_hit(geometry, plot, x, y) -> row | nothing

Which occurrence is under a canvas point, within a few pixels. Only the events
actually drawn are candidates, so a click can never select something that
decimation left out.
"""
function event_hit(g, plot, x::Real, y::Real)
    flow, cross = _local_flow_cross(g, plot, x, y)
    events = g.chart.events
    tolerance = g.style.event_radius + 3
    best = nothing
    best_distance = Inf
    for i in g.visible_events
        lane = event_axis(events, i)
        position = get(g.lane_of, lane, nothing)
        position === nothing && continue
        ef = to_pixel(g.scale, g.coordinates[i])
        distance = hypot(ef - flow, position - cross)
        (distance <= tolerance && distance < best_distance) || continue
        best = i; best_distance = distance
    end
    best
end

"""
    arrow_hit(geometry, plot, x, y) -> row | nothing

Which arrow is under a canvas point. Distance to the segment for a direct
arrow, and to the chord for an arc — close enough at the tolerance a pointer
works at, and far cheaper than sampling the curve.
"""
function arrow_hit(g, plot, x::Real, y::Real)
    flow, cross = _local_flow_cross(g, plot, x, y)
    best = nothing
    best_distance = Inf
    for shape in g.shapes
        distance = if shape.route === :arc
            # An arc leaves its lane and comes back; measuring to its apex band
            # rather than to the lane keeps a click on the curve from selecting
            # the lane underneath instead.
            hypot((shape.f0 + shape.f1) / 2 - flow,
                  (shape.c0 - shape.height) - cross)
        else
            _segment_distance(flow, cross, shape.f0, shape.c0, shape.f1, shape.c1)
        end
        (distance <= 5 && distance < best_distance) || continue
        best = shape.index; best_distance = distance
    end
    best
end

function _segment_distance(px, py, x0, y0, x1, y1)
    dx = x1 - x0; dy = y1 - y0
    length_squared = dx * dx + dy * dy
    length_squared == 0 && return hypot(px - x0, py - y0)
    t = clamp(((px - x0) * dx + (py - y0) * dy) / length_squared, 0.0, 1.0)
    hypot(px - (x0 + t * dx), py - (y0 + t * dy))
end

"""
    band_hit(geometry, plot, x, y) -> (axis, band, row) | nothing

Which state-band sample is under a canvas point.
"""
function band_hit(g, plot, x::Real, y::Real)
    flow, cross = _local_flow_cross(g, plot, x, y)
    for band in g.bands
        top = band.cross - _BAND_HEIGHT - 2
        (top <= cross <= top + _BAND_HEIGHT) || continue
        for (c0, c1, _, index) in band.intervals
            f0 = to_pixel(g.scale, c0); f1 = to_pixel(g.scale, c1)
            (f0 <= flow <= f1) || continue
            return (band.axis, band.band, index)
        end
    end
    nothing
end

"""
    lane_hit(geometry, plot, x, y) -> identity | nothing

Which lane a canvas point falls nearest, counting the label strip as part of the
lane so a click on a name selects it.
"""
function lane_hit(g, plot, x::Real, y::Real)
    _, cross = _local_flow_cross(g, plot, x, y)
    best = nothing
    best_distance = Inf
    for (position, identity) in enumerate(g.order)
        position <= length(g.lanes) || break
        distance = abs(g.lanes[position] - cross)
        (distance <= 8 && distance < best_distance) || continue
        best = identity; best_distance = distance
    end
    best
end

# In the label strip beside (or above) the body, a lane is picked by proximity
# alone, since there is no line there to be near.
function _label_strip_lane(g, x::Real, y::Real)
    if g.vertical
        (g.body_y - g.label_h - _LABEL_GAP <= y < g.body_y) || return nothing
        cross = Float64(x) - g.body_x
    else
        (g.body_x - g.label_w - _LABEL_GAP <= x < g.body_x) || return nothing
        cross = Float64(y) - g.body_y
    end
    best = nothing; best_distance = Inf
    for (position, identity) in enumerate(g.order)
        position <= length(g.lanes) || break
        distance = abs(g.lanes[position] - cross)
        distance < best_distance && (best = identity; best_distance = distance)
    end
    best_distance <= 20 ? best : nothing
end

# ── Reader ───────────────────────────────────────────────────────────────

"""
    sequence_chart_reference(plot, inner) -> Reference

Lift a chart-rooted reference into the plot's own vocabulary, which is what the
first stage then peels back off.
"""
function sequence_chart_reference(plot::SequenceChartPlot, inner)
    inner === nothing && return nothing
    ct = get_reference_node_type(plot.chart)
    @reference ::SequenceChartPlot.chart::ct.^(inner)
end

_select(plot, inner) = begin
    reference = sequence_chart_reference(plot, inner)
    reference === nothing ? nothing : ReplaceSelectionOperation(reference)
end

# Clicking picks the most specific thing under the pointer. The order is the one
# OMNeT++ settled on and for the same reason: an occurrence is a point and an
# arrow is a line, so where both are within reach the point was almost certainly
# what was aimed at.
function read_intent(p::SequenceChartPlotToGraphicsCanvas, iomap,
                     gesture::MousePress)
    g = iomap.geometry
    g === nothing && return nothing
    plot = iomap.input
    chart = plot.chart
    x, y = gesture.x, gesture.y

    # Double-click returns to the whole trace: the reliable way out of a zoom,
    # and the one people reach for without being told.
    if gesture.count >= 2 && _in_body(g, x, y)
        plot.view === nothing && return nothing
        return ReplaceReferencedValueOperation(plot, "view", nothing)
    end

    if _in_body(g, x, y)
        row = event_hit(g, plot, x, y)
        row === nothing || return _select(plot, event_reference(chart, row))
        arrow = arrow_hit(g, plot, x, y)
        arrow === nothing || return _select(plot, arrow_reference(chart, arrow))
        band = band_hit(g, plot, x, y)
        band === nothing || return _select(plot, band_reference(chart, band...))
        lane = lane_hit(g, plot, x, y)
        lane === nothing || return _select(plot, axis_reference(chart, lane))
        return nothing
    end

    lane = _label_strip_lane(g, x, y)
    lane === nothing || return _select(plot, axis_reference(chart, lane))
    nothing
end

# Hovering names what is under the pointer and reads the time there. Both are
# overlay state: they are written to the plot, and only the element pass reads
# them, so a pointer move never re-runs the layout.
function read_intent(p::SequenceChartPlotToGraphicsCanvas, iomap,
                     gesture::MouseMove)
    g = iomap.geometry
    g === nothing && return nothing
    plot = iomap.input
    chart = plot.chart
    x, y = gesture.x, gesture.y

    hovered = nothing
    if _in_body(g, x, y)
        row = event_hit(g, plot, x, y)
        if row !== nothing
            hovered = sequence_chart_reference(plot, event_reference(chart, row))
        else
            arrow = arrow_hit(g, plot, x, y)
            arrow === nothing ||
                (hovered = sequence_chart_reference(plot, arrow_reference(chart, arrow)))
        end
    end

    cursor = nothing
    if _in_body(g, x, y) && chart.gutter.cursor_readout
        flow, _ = _local_flow_cross(g, plot, x, y)
        cursor = coordinate_to_time(g.times, g.coordinates, to_data(g.scale, flow))
    end

    operations = Any[]
    isequal(plot.hovered, hovered) ||
        push!(operations, ReplaceReferencedValueOperation(plot, "hovered", hovered))
    isequal(plot.cursor, cursor) ||
        push!(operations, ReplaceReferencedValueOperation(plot, "cursor", cursor))
    isempty(operations) && return nothing
    length(operations) == 1 ? operations[1] : CompoundOperation(operations)
end

# Leaving clears both, so a stale readout never outlives the pointer.
function read_intent(p::SequenceChartPlotToGraphicsCanvas, iomap, gesture::MouseLeave)
    plot = iomap.input
    (plot.hovered === nothing && plot.cursor === nothing) && return nothing
    CompoundOperation(Any[
        ReplaceReferencedValueOperation(plot, "hovered", nothing),
        ReplaceReferencedValueOperation(plot, "cursor", nothing)])
end

# The wheel zooms about the pointer, so whatever is under it stays under it —
# the only zoom that lets someone drive toward a detail rather than hunt for it
# again afterwards. Shift makes it pan instead. Over the lane labels it scrolls
# the lanes, which is the one thing the cross axis can do.
function read_intent(p::SequenceChartPlotToGraphicsCanvas, iomap, gesture::MouseScroll)
    g = iomap.geometry
    g === nothing && return nothing
    plot = iomap.input
    x, y = gesture.x, gesture.y
    steps = gesture.dy != 0 ? gesture.dy : gesture.dx
    steps == 0 && return nothing

    if _label_strip_lane(g, x, y) !== nothing
        return ReplaceReferencedValueOperation(plot, "cross_offset",
                                               max(plot.cross_offset - 20 * steps, 0))
    end
    _in_body(g, x, y) || return nothing

    span = g.hi - g.lo
    if gesture.modifiers.shift
        return _window_operation(g, plot, g.lo + span * 0.15 * -steps, span)
    end
    flow, _ = _local_flow_cross(g, plot, x, y)
    focus = to_data(g.scale, flow)
    factor = steps > 0 ? (0.85 ^ steps) : (1 / 0.85) ^ (-steps)
    new_span = span * factor
    # Keep the coordinate under the pointer where it was.
    fraction = span == 0 ? 0.5 : (focus - g.lo) / span
    _window_operation(g, plot, focus - fraction * new_span, new_span)
end

# A window is stored relative to an event, so committing one means choosing the
# anchor: the first event at or after the window's start, falling back to the
# last event. Anchoring to an occurrence is what keeps the view still when the
# trace grows behind it.
function _window_operation(g, plot::SequenceChartPlot, lo::Real, span::Real)
    coordinates = g.coordinates
    n = length(coordinates)
    n == 0 && return nothing
    span > 0 || return nothing
    anchor = clamp(searchsortedfirst(coordinates, Float64(lo)), 1, n)
    view = SequenceChartView(anchor, Float64(lo) - coordinates[anchor], Float64(span))
    ReplaceReferencedValueOperation(plot, "view", view)
end

end # module
