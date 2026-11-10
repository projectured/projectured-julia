# Fragment of `SequenceChartModule`.
#
# SequenceChartPlot → Graphics: the sequence chart renderer. Lanes, the
# occurrences on them, the arrows between those, the state bands, and the time
# scale alongside — all composed out of the existing graphics primitives, so a
# sequence chart is vector output like every other projection and stays selectable
# and resolution-independent.
#
# **Three cells, not one.** The work splits by what invalidates it:
#
# 1. `timeline` — the cumulative pass that assigns every event a coordinate. It
#    depends on the times and the mapping and nothing else, so panning, hovering
#    or resizing never re-runs it.
# 2. `geometry` — the frame: the window, the lane positions, which events and
#    arrows are visible, their decimated shapes, the ticks and their measured
#    labels. It depends on the data and the size, and deliberately **not** on the
#    pointer.
# 3. `elements` — the drawable list, which reads the geometry *and* the pointer
#    state. Hover, selection and the cursor readout live only here, so moving the
#    mouse rebuilds the overlay rather than re-deciding the layout.
#
# That last split is the one worth keeping: hover on a dense chart changes at
# pointer-move frequency, and re-deriving a layout over a hundred thousand arrows
# at that rate is the difference between a chart that tracks the mouse and one
# that lags behind it.
#
# **Cost.** Events are decimated to at most one per lane per pixel and arrows to
# the pixels they actually cover, so the element count is bounded by the size of
# the chart rather than by the length of the trace.
#
# **Tolerance.** A kind index that names nothing, an endpoint row that is out of
# range, a lane column shorter than the event table — none of these throw. They
# are drawn as far as they make sense and skipped where they do not, because a
# chart is often being watched while something upstream is still writing it.

_or(value, fallback) = value === nothing ? fallback : value

"""
    SequenceChartPlotToGraphicsCanvas(; measure, width=900, height=520, theme=nothing)

The sequence chart renderer. `measure::TextMeasure` is how tick, lane and arrow
text is sized: `FontFileMeasure()`, as every backend draws, or a `FixedMeasure`
in a test.

`width`/`height` are the fallback canvas size, used when the printer context
carries no allocation from a parent layout.

`theme` is a `SequenceChartTheme`, scaled or not, or `nothing` for the default
values. A chart's own `SequenceChartStyle`, and a kind's own color, still take
priority over it; the theme only replaces what neither names.

A plain struct rather than an `@projection`: `measure` is fixed at
construction and needs no reactive field.
"""
struct SequenceChartPlotToGraphicsCanvas <: Projection
    measure::TextMeasure
    width::Int
    height::Int
    style::Any
end

SequenceChartPlotToGraphicsCanvas(; measure::TextMeasure, width::Integer=900,
                                  height::Integer=520, theme=nothing) =
    SequenceChartPlotToGraphicsCanvas(measure, Int(width), Int(height),
                                      make_theme_values_field(SequenceChartTheme, theme))

@iomap struct SequenceChartPlotToGraphicsCanvasIoMap
    projection::Any
    input::Any
    output::Any
    timeline::Cell     # the coordinate of every event, one cumulative pass
    geometry::Cell     # the laid-out frame: window, lanes, ticks, shapes
    toolbar::Cell      # the print of the buttons while they show, or nothing
    right_scroll_bar::Cell   # the print of the bar along the right edge of the body while it is there, or nothing
    bottom_scroll_bar::Cell  # the print of the bar along the bottom edge of the body while it is there, or nothing
end

# ── The timeline pass ────────────────────────────────────────────────────

# The coordinate of every event, plus the times it was derived from. Kept in its
# own cell because it is the only O(n) pass over the whole trace, and nothing
# about looking at the chart should re-run it.
function _timeline(chart)
    chart isa SequenceChart || return nothing
    events = chart.events
    n = get_event_count(events)
    times = Float64[Float64(events.times[i]) for i in 1:n]
    timeline = chart.timeline
    coordinates = get_timeline_coordinates(times, events.ordinals, timeline.mode;
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
                 timeline, w::Int, h::Int, t)
    chart = plot.chart
    chart isa SequenceChart || return nothing
    timeline === nothing && return nothing
    style = chart.style
    label_font = _or(style.label_font, t.label_font)
    axis_font = _or(style.axis_label_font, t.axis_font)
    title_font = t.title_font

    times, coordinates = timeline.times, timeline.coordinates
    vertical = chart.orientation === :vertical
    lo, hi = resolve_window(plot, coordinates)
    hi > lo || (hi = lo + 1.0)

    title = chart.title
    title_h = isempty(title) ? 0 : compute_line_box(p.measure, title, title_font).height + t.padding ÷ 2

    order = get_axis_display_order(chart)
    labels = String[String(chart.axes[i].label) for i in order]
    label_sizes = LineBox[compute_line_box(p.measure, l, axis_font) for l in labels]
    label_w = isempty(label_sizes) ? 0 : maximum(sz.width for sz in label_sizes)
    label_h = compute_line_box(p.measure, "0", axis_font).height

    gutter = chart.gutter
    gutter_h = gutter.visible ? label_h + 2 * t.gutter_padding : 0

    # The lane labels take a strip beside the body when time runs across, and a
    # header band above it when time runs down — in both cases outside the body,
    # so they stay put while the content scrolls.
    if vertical
        left = t.padding
        right = t.padding
        top = t.padding + title_h + label_h + t.label_gap + gutter_h
        bottom = t.padding + gutter_h
    else
        left = t.padding + label_w + t.label_gap
        right = t.padding
        top = t.padding + title_h + gutter_h
        bottom = t.padding + gutter_h
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
    band_heights = Float64[_lane_band_height(chart.axes[i], t.band_height) for i in order]
    lanes = get_axis_cross_positions(length(order), band_heights, cross_lo, cross_hi;
                                 spacing=style.axis_spacing,
                                 minimum_spacing=t.lane_spacing,
                                 offset=t.lane_offset)
    # How far the lanes can scroll: the last lane and the margin after it, past
    # the body.
    cross_room = isempty(lanes) ? 0.0 : max(0.0, lanes[end] + t.lane_offset - cross_hi)
    # Lane identity → cross position, so an event finds its lane by the index it
    # actually carries rather than by where it happens to be drawn.
    lane_of = Dict{Int,Float64}()
    for (position, identity) in zip(lanes, order)
        lane_of[identity] = position
    end

    events = chart.events
    arrows = chart.arrows
    i0, i1 = get_visible_event_range(coordinates, lo, hi)
    visible_events = decimate_events(coordinates, events.axes; scale, i0, i1,
                                     kinds=events.kinds,
                                     separation=max(style.event_radius, 1))
    # Only events whose kind is switched on, and whose lane exists.
    visible_events = Int[i for i in visible_events
                         if _event_visible(chart, events, i) && haskey(lane_of, get_event_axis(events, i))]

    horizon = abs(flow_hi - flow_lo) * max(style.split_horizon_viewports, 1)
    horizon_coordinates = horizon / max(abs(scale.p1 - scale.p0), 1) * (hi - lo)
    candidates = get_visible_arrows(coordinates, arrows.sources, arrows.targets; lo, hi,
                                    horizon=horizon_coordinates)
    shapes = _arrow_shapes(chart, events, arrows, coordinates, scale, lane_of,
                           candidates, horizon, style)

    ticks = flow_ticks(times, coordinates; scale, mode = chart.timeline.mode,
                       target_px=t.tick_spacing)
    neighbourhood = _tick_neighbourhood(times, coordinates, scale, ticks)
    raw_labels = String[get_honest_tick_label(tick_time, neighbourhood) for (_, tick_time) in ticks]
    prefix, tick_labels = tick_common_prefix(raw_labels)

    zero_spans = style.zero_time_shading ? get_zero_time_spans(times, coordinates, lo, hi) :
                                           Tuple{Float64,Float64}[]

    bands = _band_shapes(chart, order, lane_of, times, coordinates, lo, hi)

    (; w, h, chart, style, plot, frame, vertical, scale, lo, hi,
       times, coordinates, order, lanes, lane_of, cross_room, labels, label_sizes,
       label_w, label_h, label_font, axis_font, title, title_font, title_h,
       gutter_h, ticks, tick_labels, prefix, zero_spans,
       visible_events, shapes, bands,
       body_x, body_y, body_w, body_h,
       measure = p.measure,
       background = t.background, body_background = t.body_background,
       axis = t.axis, text_color = t.text_color, title_color = t.title_color,
       gutter = t.gutter, gutter_border = t.gutter_border,
       hairline = t.hairline, zero_time = t.zero_time,
       arrow = t.arrow, event = t.event, series_colors = t.series_colors,
       selected = t.selected, hover = t.hover, band_fill = t.band_fill,
       padding = t.padding, gutter_padding = t.gutter_padding,
       label_gap = t.label_gap, band_height = t.band_height,
       radius = t.radius, line_width = t.line_width,
       border_width = t.border_width, ring_width = t.ring_width,
       ring_margin = t.ring_margin, selected_width = t.selected_width,
       band_overlay_alpha = t.band_overlay_alpha,
       hairline_dash = t.hairline_dash, cursor_dash = t.cursor_dash,
       dashed_arrow_dash = t.dashed_arrow_dash, dotted_arrow_dash = t.dotted_arrow_dash,
       continuation_dash = t.continuation_dash)
end

_lane_band_height(axis::SequenceChartAxis, band_height) = length(axis.bands) > 0 ? Float64(band_height) : 0.0

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
        kind = _arrow_kind_document(chart, get_arrow_kind(arrows, k))
        (kind === nothing || kind.visible) || continue
        source = Int(arrows.sources[k]); target = Int(arrows.targets[k])
        (1 <= source <= n && 1 <= target <= n) || continue
        source_lane = get_arrow_source_axis(arrows, events, k)
        target_lane = get_arrow_target_axis(arrows, events, k)
        (haskey(lane_of, source_lane) && haskey(lane_of, target_lane)) || continue

        f0 = to_pixel(scale, coordinates[source])
        f1 = to_pixel(scale, coordinates[target])
        c0 = lane_of[source_lane]
        c1 = lane_of[target_lane]
        push!(kept, k)
        push!(flows, (f0, f1))
        push!(crosses, (c0, c1))
    end

    surviving = deduplicate_arrow_coverage(kept, flows, crosses)
    positions = Dict{Int,Int}(k => i for (i, k) in enumerate(kept))

    for k in surviving
        index = positions[k]
        f0, f1 = flows[index]
        c0, c1 = crosses[index]
        kind = _arrow_kind_document(chart, get_arrow_kind(arrows, k))
        route = get_arrow_route(kind === nothing ? :auto : kind.route, c0 == c1)
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
            intervals = get_band_intervals(band.times, band.values; events=band.events,
                                           event_times=times, coordinates, lo, hi)
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
    let kind = _event_kind_document(chart, get_event_kind(events, i))
        kind === nothing || kind.visible
    end

_kind_color(kind, index::Integer, cycle, fallback) =
    kind === nothing ? fallback :
        (kind.color === nothing ? get_series_color(nothing, index, cycle) : kind.color)

# ── Elements ─────────────────────────────────────────────────────────────

# The chart's frame: background, title, the gutters with their ticks, the lane
# labels. Everything here lives outside the scrolling body, so it stays put.
function _frame_elements!(out, g)
    style = g.style
    push!(out, GraphicsRect(0, 0, g.w, g.h; color = _or(style.background, g.background)))
    push!(out, GraphicsRect(round(Int, g.body_x), round(Int, g.body_y),
                            round(Int, g.body_w), round(Int, g.body_h);
                            color = g.body_background))

    isempty(g.title) || begin
        title_line = compute_line_box(g.measure, g.title, g.title_font)
        push!(out, GraphicsText(g.title, g.padding, g.padding + title_line.text_y;
                                font = g.title_font, color = _or(style.tick_color, g.title_color)))
    end

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
    background = _or(style.gutter_background, g.gutter)
    text_color = _or(style.tick_color, g.text_color)
    height = g.gutter_h

    for (strip_x, strip_y, strip_w, strip_h) in _gutter_rects(g, height)
        push!(out, GraphicsRect(round(Int, strip_x), round(Int, strip_y),
                                round(Int, strip_w), round(Int, strip_h);
                                color = background, border_width=g.border_width, border_color=g.gutter_border))
    end

    isempty(g.prefix) || begin
        prefix_line = compute_line_box(g.measure, g.prefix, g.axis_font)
        push!(out, GraphicsText(g.prefix, round(Int, g.body_x), g.padding + g.title_h + prefix_line.text_y;
                                font = g.axis_font, color = text_color))
    end

    # Both strips carry the labels: a reader following an arrow across the chart
    # should not have to travel back to one edge to find out when it happened.
    for (index, (coordinate, _)) in enumerate(g.ticks)
        index <= length(g.tick_labels) || break
        label = g.tick_labels[index]
        isempty(label) && continue
        text = isempty(g.prefix) ? label : string("+", label)
        flow = to_pixel(g.scale, coordinate)
        line = compute_line_box(g.measure, text, g.axis_font)
        if g.vertical
            y = round(Int, flow + g.body_y - line.height / 2) + line.text_y
            push!(out, GraphicsText(text, round(Int, g.body_x - line.width - g.label_gap),
                                    y; font = g.axis_font, color = text_color))
            push!(out, GraphicsText(text, round(Int, g.body_x + g.body_w + g.label_gap),
                                    y; font = g.axis_font, color = text_color))
        else
            x = round(Int, flow + g.body_x - line.width / 2)
            push!(out, GraphicsText(text, x,
                                    round(Int, g.body_y - height + g.gutter_padding) + line.text_y;
                                    font = g.axis_font, color = text_color))
            push!(out, GraphicsText(text, x,
                                    round(Int, g.body_y + g.body_h + g.gutter_padding) + line.text_y;
                                    font = g.axis_font, color = text_color))
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
    text_color = _or(g.style.axis_color, g.text_color)
    for (position, identity) in enumerate(g.order)
        position <= length(g.lanes) || break
        label = g.labels[position]
        isempty(label) && continue
        line = g.label_sizes[position]
        cross = g.lanes[position]
        if g.vertical
            push!(out, GraphicsText(label, round(Int, cross + g.body_x - line.width / 2),
                                    round(Int, g.body_y - g.label_h - g.label_gap) + line.text_y;
                                    font = g.axis_font, color = text_color))
        else
            push!(out, GraphicsText(label, round(Int, g.body_x - line.width - g.label_gap),
                                    round(Int, cross + g.body_y - line.height / 2) + line.text_y;
                                    font = g.axis_font, color = text_color))
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
                                round(Int, w), round(Int, h); color = g.zero_time))
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
                                round(Int, x1), round(Int, y1);
                                color = g.hairline, width = g.line_width, dash = g.hairline_dash))
    end
    out
end

function _lane_elements!(out, g)
    flow_lo, flow_hi = frame_flow_span(g.frame)
    default = _or(g.style.axis_color, g.axis)
    for (position, identity) in enumerate(g.order)
        position <= length(g.lanes) || break
        axis = g.chart.axes[identity]
        axis.visible || continue
        cross = g.lanes[position]
        x0, y0 = flow_point(g.frame, flow_lo, cross)
        x1, y1 = flow_point(g.frame, flow_hi, cross)
        push!(out, GraphicsLine(round(Int, x0), round(Int, y0),
                                round(Int, x1), round(Int, y1);
                                color = _or(axis.color, default), width = g.line_width))
    end
    out
end

# A state strip: one filled rectangle per held value, with the value's name
# inside when it fits. The strip sits just off the lane so the lane's own events
# stay legible.
function _band_elements!(out, g)
    cycle = _or(g.style.color_cycle, g.series_colors)
    for band in g.bands
        document = band.document
        for (c0, c1, value, index) in band.intervals
            f0 = to_pixel(g.scale, c0); f1 = to_pixel(g.scale, c1)
            width = f1 - f0
            width >= 1 || continue
            color = _band_color(document, value, cycle, g.band_overlay_alpha)
            x, y, w, h = flow_rect(g.frame, f0, band.cross - g.band_height - 2,
                                   width, g.band_height)
            push!(out, GraphicsRect(round(Int, x), round(Int, y),
                                    round(Int, w), round(Int, h); color))
            g.style.band_labels || continue
            name = get_band_state_name(document, value)
            isempty(name) && continue
            line = compute_line_box(g.measure, name, g.label_font)
            line.width + 6 <= w || continue
            push!(out, GraphicsText(name, round(Int, x + (w - line.width) / 2),
                                    round(Int, y + (h - line.height) / 2) + line.text_y;
                                    font = g.label_font, color = g.text_color))
        end
    end
    out
end

function _band_color(band::SequenceChartBandSeries, value::Real, cycle, overlay_alpha::Real)
    colors = band.colors
    index = round(Int, value) + 1
    if colors !== nothing && 1 <= index <= length(colors)
        return colors[index]
    end
    color = get_series_color(nothing, max(index, 1), cycle)
    StyleColor(color.red, color.green, color.blue, overlay_alpha)
end

# The arrows. A same-lane arrow arcs off its lane, because a straight line along
# a lane would be invisible inside it; a long one is drawn as two stubs, because
# at that length the line says nothing its ends do not.
function _arrow_elements!(out, g)
    style = g.style
    cycle = _or(style.color_cycle, g.series_colors)
    for shape in g.shapes
        kind = shape.kind
        color = _kind_color(kind, shape.index, cycle, g.arrow)
        dash = _line_dash(kind === nothing ? :solid : kind.line_style, g)
        head = kind === nothing ? true : kind.arrowhead
        if shape.route === :arc
            _arc_elements!(out, g, shape, color, dash, head)
        elseif shape.split === nothing
            x0, y0 = flow_point(g.frame, shape.f0, shape.c0)
            x1, y1 = flow_point(g.frame, shape.f1, shape.c1)
            push!(out, GraphicsPolyline([(round(Int, x0), round(Int, y0)),
                                         (round(Int, x1), round(Int, y1))];
                                        color, width=style.arrow_width, dash=dash,
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
    points = get_arc_geometry(shape.f0, shape.f1, shape.c0, shape.height)
    placed = [(round(Int, x), round(Int, y))
              for (x, y) in (flow_point(g.frame, f, c) for (f, c) in points)]
    push!(out, GraphicsSpline(placed; color, kind=:bezier, width=g.style.arrow_width,
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
                                 (round(Int, x1), round(Int, y1))];
                                color, width=g.style.arrow_width, dash=dash))
    x2, y2 = flow_point(g.frame, far[2], shape.c1)
    x3, y3 = flow_point(g.frame, far[1], shape.c1)
    push!(out, GraphicsPolyline([(round(Int, x2), round(Int, y2)),
                                 (round(Int, x3), round(Int, y3))];
                                color, width=g.style.arrow_width, dash=g.continuation_dash,
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
    push!(out, GraphicsPolyline(points; color, width=g.line_width))
    out
end

function _arrow_label!(out, g, shape, color)
    g.style.arrow_labels || return out
    label = get_arrow_label(g.chart.arrows, shape.index)
    (label === nothing || isempty(label)) && return out
    mid_flow = (shape.f0 + shape.f1) / 2
    mid_cross = (shape.c0 + shape.c1) / 2
    line = compute_line_box(g.measure, label, g.label_font)
    x, y = flow_point(g.frame, mid_flow, mid_cross)
    # An arrow can sit against an edge of the window while its label does not
    # fit there; nudging the text back inside keeps it readable rather than
    # letting the viewport cut it in half.
    x = clamp(x - line.width / 2, 0, max(g.body_w - line.width, 0))
    y = clamp(y - line.height - 3, 0, max(g.body_h - line.height, 0))
    push!(out, GraphicsText(label, round(Int, x), round(Int, y) + line.text_y; font = g.label_font, color = g.text_color))
    out
end

_line_dash(style::Symbol, g) =
    style === :dashed ? g.dashed_arrow_dash : style === :dotted ? g.dotted_arrow_dash : nothing

function _event_elements!(out, g)
    events = g.chart.events
    style = g.style
    cycle = _or(style.color_cycle, g.series_colors)
    radius = style.event_radius
    for i in g.visible_events
        lane = get_event_axis(events, i)
        haskey(g.lane_of, lane) || continue
        kind_index = get_event_kind(events, i)
        kind = _event_kind_document(g.chart, kind_index)
        color = _kind_color(kind, max(kind_index, 1), cycle, g.event)
        flow = to_pixel(g.scale, g.coordinates[i])
        x, y = flow_point(g.frame, flow, g.lane_of[lane])
        symbol = kind === nothing ? :circle : kind.symbol
        _mark!(out, symbol, round(Int, x), round(Int, y), radius, color)
        style.event_labels || continue
        label = get_event_label(events, i)
        (label === nothing || isempty(label)) && continue
        push!(out, GraphicsText(label, round(Int, x + radius + 2),
                                round(Int, y + radius); font = g.label_font, color = g.text_color))
    end
    out
end

# An event's mark. The shapes come from the chart slice's marker vocabulary, so
# the two domains stay recognisably one family.
function _mark!(out, symbol::Symbol, x::Int, y::Int, radius::Int, color)
    if symbol === :circle || symbol === :dot
        push!(out, GraphicsCircle(x, y, radius; color))
    elseif symbol === :square
        push!(out, GraphicsRect(x - radius, y - radius, 2 * radius, 2 * radius; color))
    else
        points = build_marker_polygon(symbol, x, y, radius)
        if points === nothing
            push!(out, GraphicsCircle(x, y, radius; color))
        else
            push!(out, GraphicsPolygon(points; color))
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

# Which occurrence and arrow a reference names, once the plot's own `chart` step
# is off. Selection arrives already in the plot's vocabulary, so both are peeled
# the same way.
function _overlay_rows(g, plot)
    chart = g.chart
    chart isa SequenceChart || return (0, 0, 0, 0)
    target = getfield(plot, :mouse_target)[]
    (_row_of(target, :events), _row_of(target, :arrows),
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
    lit_event, lit_arrow, selected_event_row, selected_arrow_row =
        _overlay_rows(g, plot)

    # A selected occurrence gets a ring around it rather than a different fill:
    # the mark's own colour carries its kind, and overwriting that to say
    # "selected" would cost the reader the very thing they selected it to see.
    for (row, color) in ((selected_event_row, g.selected), (lit_event, g.hover))
        row == 0 && continue
        _event_ring!(out, g, row, color)
    end
    for (row, color) in ((selected_arrow_row, g.selected), (lit_arrow, g.hover))
        row == 0 && continue
        _arrow_highlight!(out, g, row, color)
    end
    _cursor_elements!(out, g, plot)
    out
end

function _event_ring!(out, g, row::Integer, color)
    (1 <= row <= length(g.coordinates)) || return out
    lane = get_event_axis(g.chart.events, row)
    position = get(g.lane_of, lane, nothing)
    position === nothing && return out
    flow = to_pixel(g.scale, g.coordinates[row])
    x, y = flow_point(g.frame, flow, position)
    radius = g.style.event_radius + g.ring_margin
    # Transparent fill, so the mark underneath still shows through the ring.
    push!(out, GraphicsCircle(round(Int, x), round(Int, y), radius;
                              color = color_transparent,
                              border_width=g.ring_width, border_color=color))
    out
end

function _arrow_highlight!(out, g, row::Integer, color)
    for shape in g.shapes
        shape.index == row || continue
        if shape.route === :arc
            points = get_arc_geometry(shape.f0, shape.f1, shape.c0, shape.height)
            placed = [(round(Int, x), round(Int, y))
                      for (x, y) in (flow_point(g.frame, f, c) for (f, c) in points)]
            push!(out, GraphicsSpline(placed; color, kind=:bezier, width=g.selected_width))
        else
            x0, y0 = flow_point(g.frame, shape.f0, shape.c0)
            x1, y1 = flow_point(g.frame, shape.f1, shape.c1)
            push!(out, GraphicsPolyline([(round(Int, x0), round(Int, y0)),
                                         (round(Int, x1), round(Int, y1))];
                                        color, width=g.selected_width))
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
                            round(Int, x1), round(Int, y1);
                            color = g.selected, width = g.line_width, dash = g.cursor_dash))
    out
end

# The two readouts in the gutter: the time under the pointer, and the extent of
# the window, which ends at `right`. Both are chrome, so they go in the outer canvas
# where the body's clipping cannot reach them.
function _readout_elements!(out, g, plot, right)
    gutter = g.chart.gutter
    gutter.visible || return out
    text_color = _or(g.style.tick_color, g.text_color)

    if gutter.cursor_readout && plot.cursor !== nothing
        text = get_honest_tick_label(plot.cursor, _cursor_neighbourhood(g))
        line = compute_line_box(g.measure, text, g.axis_font)
        flow = to_pixel(g.scale, time_to_coordinate(g.times, g.coordinates, plot.cursor))
        if g.vertical
            y = round(Int, flow + g.body_y - line.height / 2)
            push!(out, GraphicsRect(round(Int, g.body_x - line.width - g.label_gap - 2), y - 1,
                                    line.width + 4, line.height + 2; color = g.selected))
            push!(out, GraphicsText(text, round(Int, g.body_x - line.width - g.label_gap),
                                    y + line.text_y; font = g.axis_font, color = g.body_background))
        else
            x = round(Int, flow + g.body_x - line.width / 2)
            y = round(Int, g.body_y - g.gutter_h + g.gutter_padding)
            push!(out, GraphicsRect(x - 2, y - 1, line.width + 4, line.height + 2; color = g.selected))
            push!(out, GraphicsText(text, x, y + line.text_y; font = g.axis_font, color = g.body_background))
        end
    end

    if gutter.range_readout
        span = convert_coordinate_to_time(g.times, g.coordinates, g.hi) -
               convert_coordinate_to_time(g.times, g.coordinates, g.lo)
        text = string(get_honest_tick_label(convert_coordinate_to_time(g.times, g.coordinates, g.lo),
                                        _cursor_neighbourhood(g)),
                      " … Δ", get_honest_tick_label(span, _cursor_neighbourhood(g)))
        line = compute_line_box(g.measure, text, g.axis_font)
        push!(out, GraphicsText(text, round(Int, right - line.width),
                                g.padding + line.text_y; font = g.axis_font, color = text_color))
    end
    out
end

# How much time one pixel stands for — the bound on how many digits a readout
# may honestly show.
function _cursor_neighbourhood(g)
    pixels = abs(g.scale.p1 - g.scale.p0)
    pixels > 0 || return 0.0
    t_lo = convert_coordinate_to_time(g.times, g.coordinates, g.lo)
    t_hi = convert_coordinate_to_time(g.times, g.coordinates, g.hi)
    abs(t_hi - t_lo) / pixels / 2
end

# ── Printer ──────────────────────────────────────────────────────────────

# The extent on one axis, by the child rule: the projection's own size, cut at the
# maximum of the range, and at least its minimum. An exact range gives the chart
# its extent, a bounded one caps it, and a free one leaves it its own size.
function _get_sequence_chart_extent(minimum, maximum, natural)
    upper = maximum === nothing ? nothing : maximum[]
    lower = minimum === nothing ? nothing : minimum[]
    extent = upper === nothing ? natural : min(natural, Int(upper))
    lower === nothing ? extent : max(extent, Int(lower))
end

# Canvas size: the extent on each axis, and never less than the chart can draw
# in. Reading the cells here registers the dependency, so a resize reflows
# without re-projecting.
function _canvas_size(p::SequenceChartPlotToGraphicsCanvas, ctx)
    ctx === nothing && return (max(p.width, 160), max(p.height, 100))
    w = _get_sequence_chart_extent(ctx.minimum_width, ctx.maximum_width, p.width)
    h = _get_sequence_chart_extent(ctx.minimum_height, ctx.maximum_height, p.height)
    (max(Int(w), 160), max(Int(h), 100))
end

function print_document(p::SequenceChartPlotToGraphicsCanvas, recursion,
                        plot::SequenceChartPlot, ctx)
    # Read once for the whole print: every helper below takes this tuple rather
    # than reading `p.style` again, so a theme costs one read per print, not one
    # per computed cell.
    t = unwrap_cell(p.style)

    # One cumulative pass over the trace, isolated so that looking at the chart
    # never re-runs it.
    timeline = Cell(@computation _timeline(plot.chart))

    geometry = Cell(@computation begin
        w, h = _canvas_size(p, ctx)
        _layout(p, plot, timeline[], w, h, t)
    end)
    _bind_scroll_bars!(plot, geometry)

    # The buttons print while the pointer is over the chart, and a bar while its
    # thumb is less than the whole track, through the recursion, which
    # `make_sequence_chart_projection` gives a printer of each. Each wish is a cell
    # of its own, so a move between the parts of the chart does not print them
    # again.
    wants_toolbar = Cell(@computation _is_sequence_chart_toolbar_wanted(plot, geometry[]))
    toolbar = Cell(@computation wants_toolbar[] ?
        print_child(recursion, plot.toolbar,
                    with_free_axis(with_free_axis(make_child_context(ctx, FieldReferenceStep("toolbar")),
                                                  :x), :y)) : nothing)
    # A bar is as long as its edge of the body, and as thick as its printer makes
    # it. The bar along the bottom stops before the bar along the right edge.
    right_field = Cell(@computation _get_right_scroll_bar_field(geometry[]))
    right_bar = Cell(@computation getproperty(plot, Symbol(right_field[])))
    wants_right = Cell(@computation _is_sequence_chart_scroll_bar_wanted(right_bar[], geometry[]))
    right_length = Cell(@computation (g = geometry[]; g === nothing ? 0 : round(Int, g.body_h)))
    right = Cell(@computation wants_right[] ?
        print_child(recursion, right_bar[],
                    with_exact_size(make_child_context(ctx, FieldReferenceStep(right_field[]));
                                    width = nothing, height = right_length)) : nothing)
    bottom_field = Cell(@computation _get_bottom_scroll_bar_field(geometry[]))
    bottom_bar = Cell(@computation getproperty(plot, Symbol(bottom_field[])))
    wants_bottom = Cell(@computation _is_sequence_chart_scroll_bar_wanted(bottom_bar[], geometry[]))
    bottom_length = Cell(@computation (g = geometry[]; bar = right[];
        g === nothing ? 0 : round(Int, g.body_w) - (bar === nothing ? 0 : Int(bar.output.w))))
    bottom = Cell(@computation wants_bottom[] ?
        print_child(recursion, bottom_bar[],
                    with_exact_size(make_child_context(ctx, FieldReferenceStep(bottom_field[]));
                                    width = bottom_length, height = nothing)) : nothing)

    elements = CellVector(@computation begin
        g = geometry[]
        g === nothing && return _empty_elements(p, plot, ctx, t)
        out = Any[]
        _frame_elements!(out, g)

        body = Any[]
        _body_elements!(body, g)
        # Hover and selection are read *here* rather than in the layout, so
        # moving the pointer over a dense chart rebuilds this list and nothing
        # else. They draw last, over everything they call out.
        _overlay_elements!(body, g, plot)
        # The buttons keep their corner, so a second click finds them; the range
        # readout ends left of them while they show.
        parts = _find_shown_sequence_chart_parts(g, plot, toolbar[], right[], bottom[])
        buttons = findfirst(part -> part.field == "toolbar", parts)
        readout_right = buttons === nothing ? g.w - g.padding : parts[buttons].x - g.label_gap
        _readout_elements!(out, g, plot, readout_right)

        # Cross scrolling is a translation of the body, not a relayout: which
        # lanes are in view changes nothing about the flow axis, the decimation
        # or the shapes.
        offset = plot.cross_offset
        content = GraphicsCanvas(body; x = g.vertical ? -offset : 0,
                                 y = g.vertical ? 0 : -offset,
                                 w = round(Int, g.body_w), h = round(Int, g.body_h))
        push!(out, GraphicsViewport(round(Int, g.body_x), round(Int, g.body_y),
                                    round(Int, g.body_w), round(Int, g.body_h), content))
        # The band of a zoom drag, over the body.
        rect = plot.drag_rect
        if rect !== nothing
            # Fill only, no border: a bordered rect is drawn as the border colour
            # with the fill inset on top of it, so a translucent fill would show
            # the border colour through the whole band rather than around it.
            push!(out, GraphicsRect(rect[1], rect[2], max(rect[3], 1), max(rect[4], 1); color = g.band_fill))
        end
        # The bars, and the buttons over everything.
        for part in reverse(parts)
            push!(out, GraphicsViewport(part.x, part.y, part.w, part.h, part.iomap.output))
        end
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
    SequenceChartPlotToGraphicsCanvasIoMap(p, plot, canvas, timeline, geometry, toolbar, right, bottom)
end

# A chart-shaped placeholder for an empty or not-yet-typed root, so it still
# occupies its space and reads as a chart rather than vanishing.
function _empty_elements(p::SequenceChartPlotToGraphicsCanvas, plot::SequenceChartPlot, ctx, t)
    w, h = _canvas_size(p, ctx)
    Any[GraphicsRect(0, 0, w, h; color = t.background),
        GraphicsRect(t.padding, t.padding, w - 2 * t.padding, h - 2 * t.padding;
                     color = t.body_background, radius = t.radius,
                     border_width=t.border_width, border_color=t.axis),
        GraphicsText("empty sequence chart", t.padding * 2, h ÷ 2;
                     font = t.axis_font, color = t.text_color)]
end

"""
    get_lane_cross_position(geometry, identity) -> Float64 | nothing

Where a lane sits on the cross axis, by lane identity. Exposed because the
reader hit-tests against the same positions the printer drew.
"""
get_lane_cross_position(g, identity::Integer) = get(g.lane_of, Int(identity), nothing)

# A chart part is not a cursor position: there is nowhere in the canvas for a
# selection to land, and no output element a reference should follow. Selection
# is instead expressed by what the reader selects and what the overlay
# highlights, so a reference maps forward to nothing.
map_reference_forward(::SequenceChartPlotToGraphicsCanvas, iomap, reference) = nothing

# A point maps back to the part drawn at it, with the hit tests of the reader of
# a click, in its order: a button or a bar, in the body an event, an arrow, a band
# or a lane, and else the plot at that point, which the cursor readout reads;
# beside the body, the lane of the label strip.
function map_reference_backward(::SequenceChartPlotToGraphicsCanvas, iomap, reference)
    point = find_reference_point(reference)
    point === nothing && return nothing
    g = iomap.geometry
    g === nothing && return nothing
    plot, x, y = iomap.input, point.x, point.y
    chart = plot.chart
    # The buttons and the bars are on top of every part: a point on them is the
    # part of them there.
    shown = find_drawn_child_at(_find_shown_sequence_chart_parts(iomap), x, y)
    shown === nothing || return map_drawn_child_point(plot, shown, x, y)
    if _in_body(g, x, y)
        part = _find_sequence_chart_part(g, plot, x, y)
        part === nothing || return part
        band = find_band_hit(g, plot, x, y)
        band === nothing ||
            return lift_sequence_chart_reference(plot, get_band_reference(chart; band...))
        lane = find_lane_hit(g, plot, x, y)
        lane === nothing ||
            return lift_sequence_chart_reference(plot, get_axis_reference(chart, lane))
        return ConcreteReference(PointReferenceStep(x, y))
    end
    lane = _label_strip_lane(g, x, y)
    lane === nothing ? nothing : lift_sequence_chart_reference(plot, get_axis_reference(chart, lane))
end

# The event or the arrow drawn at `(x, y)` of the body, as a reference from the
# plot, or `nothing`.
function _find_sequence_chart_part(g, plot, x::Integer, y::Integer)
    chart = plot.chart
    row = find_event_hit(g, plot, x, y)
    row === nothing || return lift_sequence_chart_reference(plot, get_event_reference(chart, row))
    arrow = find_arrow_hit(g, plot, x, y)
    arrow === nothing ? nothing :
        lift_sequence_chart_reference(plot, get_arrow_reference(chart, arrow))
end

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
    find_event_hit(geometry, plot, x, y) -> row | nothing

Which occurrence is under a canvas point, within a few pixels. Only the events
actually drawn are candidates, so a click can never select something that
decimation left out.
"""
function find_event_hit(g, plot, x::Real, y::Real)
    flow, cross = _local_flow_cross(g, plot, x, y)
    events = g.chart.events
    tolerance = g.style.event_radius + 3
    best = nothing
    best_distance = Inf
    for i in g.visible_events
        lane = get_event_axis(events, i)
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
    find_arrow_hit(geometry, plot, x, y) -> row | nothing

Which arrow is under a canvas point. Distance to the segment for a direct
arrow, and to the chord for an arc — close enough at the tolerance a pointer
works at, and far cheaper than sampling the curve.
"""
function find_arrow_hit(g, plot, x::Real, y::Real)
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
    find_band_hit(geometry, plot, x, y) -> (axis = …, band = …, row = …) | nothing

Which state-band sample is under a canvas point.
"""
function find_band_hit(g, plot, x::Real, y::Real)
    flow, cross = _local_flow_cross(g, plot, x, y)
    for band in g.bands
        top = band.cross - g.band_height - 2
        (top <= cross <= top + g.band_height) || continue
        for (c0, c1, _, index) in band.intervals
            f0 = to_pixel(g.scale, c0); f1 = to_pixel(g.scale, c1)
            (f0 <= flow <= f1) || continue
            return (axis = band.axis, band = band.band, row = index)
        end
    end
    nothing
end

"""
    find_lane_hit(geometry, plot, x, y) -> identity | nothing

Which lane a canvas point falls nearest, counting the label strip as part of the
lane so a click on a name selects it.
"""
function find_lane_hit(g, plot, x::Real, y::Real)
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
        (g.body_y - g.label_h - g.label_gap <= y < g.body_y) || return nothing
        cross = Float64(x) - g.body_x
    else
        (g.body_x - g.label_w - g.label_gap <= x < g.body_x) || return nothing
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
    lift_sequence_chart_reference(plot, inner) -> Reference

Lift a chart-rooted reference into the plot's own vocabulary, which is what the
first stage then peels back off.
"""
function lift_sequence_chart_reference(plot::SequenceChartPlot, inner)
    inner === nothing && return nothing
    ct = get_reference_node_type(plot.chart)
    @reference ::SequenceChartPlot.chart::ct.^(inner)
end

_make_selection_operation(plot, inner) = begin
    reference = lift_sequence_chart_reference(plot, inner)
    reference === nothing ? nothing : ReplaceSelectionOperation(reference)
end

# The gestures of the plot, in the order of what is drawn on top: the buttons and
# the bars first, in their frame, then the gestures of the view and the selection.
function read_intent(p::SequenceChartPlotToGraphicsCanvas, iomap::SequenceChartPlotToGraphicsCanvasIoMap, event)
    g = iomap.geometry
    g === nothing && return nothing
    plot = iomap.input
    # The buttons and the bars are on top: a press, a release, a click, a dwell and
    # a right click on them go to them, in their frame.
    parts = _find_shown_sequence_chart_parts(iomap)
    if event isa Union{MouseDown, MouseUp, MouseClick, MouseDwell}
        part = find_drawn_child_at(parts, event.x, event.y)
        part === nothing || return _read_sequence_chart_part_event(g, plot, part, event)
    end

    if event isa MouseScroll
        return _read_scroll(g, plot, event)
    elseif event isa MouseDown && event.button in (:left, :middle)
        return _drag_start(g, plot, event)
    elseif event isa Union{KeyDown, KeyPress}
        return _key_intent(g, plot, event)
    elseif event isa Union{DragMove, DragEnd, DragCancel}
        # The drag comes by the path of the plot, also off the body: the drag of the
        # thumb of a bar, which the plot keeps, or a band or a pan.
        bar = _read_sequence_chart_scroll_bar_drag(g, plot, event)
        bar === nothing || return bar
        event isa DragMove && return _drag_move(g, plot, event)
        event isa DragEnd && return _drag_end(g, plot, event)
        return _cancel_drag(plot)
    elseif event isa MouseMove
        return _read_move(g, plot, parts, event)
    elseif is_outward_gesture(event)
        # A dwell and a right click go to the part at their point, and then out to
        # the plot, whose menu holds the view actions.
        return read_child_part_gesture(iomap, event)
    elseif event isa MouseClick
        return _read_click(g, plot, event)
    end
    nothing
end

# A left click picks the most specific thing under the pointer. The order is the
# one the reference tool settled on and for the same reason: an occurrence is a
# point and an arrow is a line, so where both are within reach the point was almost
# certainly what was aimed at. Another button moves no selection.
function _read_click(g, plot::SequenceChartPlot, gesture::MouseClick)
    gesture.button === :left || return nothing
    chart = plot.chart
    x, y = gesture.x, gesture.y

    # Double-click returns to the whole trace: the reliable way out of a zoom,
    # and the one people reach for without being told. On the time axis it fits
    # the time.
    if gesture.count >= 2 && (_in_body(g, x, y) || _is_over_time_axis(g, x, y))
        plot.view === nothing && return nothing
        return _write_view_state(plot, "view", nothing)
    end

    if _in_body(g, x, y)
        row = find_event_hit(g, plot, x, y)
        row === nothing || return _make_selection_operation(plot, get_event_reference(chart, row))
        arrow = find_arrow_hit(g, plot, x, y)
        arrow === nothing || return _make_selection_operation(plot, get_arrow_reference(chart, arrow))
        band = find_band_hit(g, plot, x, y)
        band === nothing || return _make_selection_operation(plot,
                                 get_band_reference(chart; band...))
        lane = find_lane_hit(g, plot, x, y)
        lane === nothing || return _make_selection_operation(plot, get_axis_reference(chart, lane))
        return nothing
    end

    lane = _label_strip_lane(g, x, y)
    lane === nothing || return _make_selection_operation(plot, get_axis_reference(chart, lane))
    nothing
end

# ── The buttons and the bars in the frame of the chart ───────────────────

# The field of the plot that holds the bar along the right edge of the body, and
# the one along its bottom edge: the time runs across a horizontal chart, so its
# bar is the one along the bottom.
_get_right_scroll_bar_field(g) = (g !== nothing && g.vertical) ? "time_scroll_bar" : "lane_scroll_bar"
_get_bottom_scroll_bar_field(g) = (g !== nothing && g.vertical) ? "lane_scroll_bar" : "time_scroll_bar"

# Whether the buttons of `plot` show: while the pointer is over the chart and no
# drag runs.
_is_sequence_chart_toolbar_wanted(plot::SequenceChartPlot, g) =
    g !== nothing && plot.toolbar !== nothing && plot.drag_anchor === nothing &&
    get_mouse_target(plot) !== nothing

# Whether the bar `bar` of a plot is there: while its thumb is less than the whole
# track.
_is_sequence_chart_scroll_bar_wanted(bar, g) =
    g !== nothing && bar !== nothing && bar.thumb_size < 1

_count_sequence_chart_buttons(plot::SequenceChartPlot) =
    plot.toolbar === nothing ? 0 : length(plot.toolbar.elements)

# Where the buttons of the print `toolbar` show, of `count` buttons: the top-right
# corner of the chart, as `(; x, y, w, h, iomap)`, or `nothing` when they do not
# show, or when the body is narrower than four buttons or lower than two.
function _find_shown_sequence_chart_toolbar(g, toolbar, count::Integer)
    (g === nothing || toolbar === nothing || count == 0) && return nothing
    canvas = toolbar.output
    canvas isa GraphicsCanvas || return nothing
    w, h = Int(canvas.w), Int(canvas.h)
    (w > 0 && h > 0) || return nothing
    (g.body_w >= 4 * w / count && g.body_h >= 2 * h) || return nothing
    inset = max(1, round(Int, g.padding) ÷ 2)
    (; x = g.w - w - inset, y = inset, w, h, iomap = toolbar)
end

# The parts that only the plot holds and that show now, the buttons first, as the
# children that the chart draws (`find_drawn_child_at`), with the field that holds
# each: the buttons in the top-right corner of the chart, the bar along the right
# edge of the body, and the bar along its bottom edge.
function _find_shown_sequence_chart_parts(g, plot::SequenceChartPlot, toolbar, right, bottom)
    parts = NamedTuple[]
    g === nothing && return parts
    part(field, x, y, w, h, iomap) = (; field, x, y, w, h, iomap, steps = (FieldReferenceStep(field),))
    shown = _find_shown_sequence_chart_toolbar(g, toolbar, _count_sequence_chart_buttons(plot))
    shown === nothing || push!(parts, part("toolbar", shown.x, shown.y, shown.w, shown.h, toolbar))
    body_x, body_y = round(Int, g.body_x), round(Int, g.body_y)
    body_w, body_h = round(Int, g.body_w), round(Int, g.body_h)
    if right !== nothing && right.output isa GraphicsCanvas
        w, h = Int(right.output.w), Int(right.output.h)
        push!(parts, part(_get_right_scroll_bar_field(g), body_x + body_w - w, body_y, w, h, right))
    end
    if bottom !== nothing && bottom.output isa GraphicsCanvas
        w, h = Int(bottom.output.w), Int(bottom.output.h)
        push!(parts, part(_get_bottom_scroll_bar_field(g), body_x, body_y + body_h - h, w, h, bottom))
    end
    parts
end

_find_shown_sequence_chart_parts(iomap::SequenceChartPlotToGraphicsCanvasIoMap) =
    _find_shown_sequence_chart_parts(iomap.geometry, iomap.input, iomap.toolbar,
                                     iomap.right_scroll_bar, iomap.bottom_scroll_bar)

get_child_iomaps(iomap::SequenceChartPlotToGraphicsCanvasIoMap) =
    Any[child for child in (iomap.toolbar, iomap.right_scroll_bar, iomap.bottom_scroll_bar)
        if child !== nothing]

# The value and the thumb of the bars of `plot` are those of its window among the
# trace and of its lanes among their room, which only the laid-out frame knows, so
# the renderer sets them from its `geometry`.
function _bind_scroll_bars!(plot::SequenceChartPlot, geometry::Cell)
    for (bar, axis) in ((plot.time_scroll_bar, :time), (plot.lane_scroll_bar, :lanes))
        bar === nothing && continue
        place = Cell(@computation _get_scroll_bar_place(geometry[], plot, axis))
        set_cell_computation!(getfield(bar, :value), () -> place[][1])
        set_cell_computation!(getfield(bar, :thumb_size), () -> place[][2])
    end
end

# The window, as a pair of a start and an end among the extent, that the bar of
# `axis` shows: the window of the time among the trace, or the lanes that the body
# shows among all of them.
function _get_scroll_bar_window(g, plot::SequenceChartPlot, axis::Symbol)
    axis === :time && return ((g.lo, g.hi), _get_trace_extent(g.coordinates))
    visible = Float64(_get_lane_page(g))
    ((Float64(plot.cross_offset), plot.cross_offset + visible), (0.0, visible + g.cross_room))
end

function _get_scroll_bar_place(g, plot::SequenceChartPlot, axis::Symbol)
    g === nothing && return (0.0, 1.0)
    window, extent = _get_scroll_bar_window(g, plot, axis)
    (compute_window_scroll_bar_value(window; extent), compute_window_scroll_bar_thumb(window; extent))
end

# The write of the view with the window of `axis` at the place `value` of its bar.
function _move_to_scroll_bar_value(g, plot::SequenceChartPlot, axis::Symbol, value::Real)
    window, extent = _get_scroll_bar_window(g, plot, axis)
    moved = compute_window_at_scroll_bar_value(window, value; extent)
    axis === :time && return _move_window(plot, _get_window_state(g), moved)
    _set_cross_offset(g, plot, round(Int, moved[1]))
end

# A move of the pointer: on a button or a bar it goes to that part and clears the
# readout; elsewhere it tracks the readout. The part that the pointer leaves gets
# the leave, so a press released off a button ends.
function _read_move(g, plot::SequenceChartPlot, parts, event::MouseMove)
    answer = read_drawn_child_move(plot, parts, event)
    on_part = find_drawn_child_at(parts, event.x, event.y) !== nothing
    join_move_answers(answer, on_part ? _clear_cursor(plot) : _track_cursor(g, plot, event))
end

# The answer of a button or a bar to a pointer gesture on it. A press on the thumb
# of a bar starts a drag that the plot keeps, and a write of the value of a bar
# moves the view.
function _read_sequence_chart_part_event(g, plot::SequenceChartPlot, part, event)
    answer = read_drawn_child_event(plot, part, event)
    (is_outward_gesture(event) || part.field == "toolbar") && return answer
    bar = getproperty(plot, Symbol(part.field))
    event isa MouseDown && (answer = keep_owned_scroll_bar_drag(answer, bar, event))
    _convert_scroll_bar_answer(g, plot, answer)
end

# The answer of a bar whose thumb the plot drags to a part of that drag, with the
# value made the move of the view, or `nothing` when no thumb is dragged.
function _read_sequence_chart_scroll_bar_drag(g, plot::SequenceChartPlot, event)
    for bar in (plot.time_scroll_bar, plot.lane_scroll_bar)
        bar === nothing && continue
        answer = read_scroll_bar_drag(bar, event)
        answer === nothing || return _convert_scroll_bar_answer(g, plot, answer)
    end
    nothing
end

# `answer` with each write of the value of a bar of `plot` made the move of the
# view to that value. A move that changes nothing is left out.
function _convert_scroll_bar_answer(g, plot::SequenceChartPlot, answer)
    for (bar, axis) in ((plot.time_scroll_bar, :time), (plot.lane_scroll_bar, :lanes))
        bar === nothing && continue
        answer = convert_scroll_bar_value_writes(answer, bar,
                                                 value -> _move_to_scroll_bar_value(g, plot, axis, value))
    end
    answer
end

# A move writes the time under the pointer, which the gutter and the cursor line
# read, only when it changes. A move off the body clears the readout, such as the
# move to `(-1, -1)` that a container gives to the plot that the pointer leaves, so
# a stale readout never outlives the pointer. What is under the pointer is the
# mouse target of the plot, which the element pass reads, so a pointer move never
# re-runs the layout.
function _track_cursor(g, plot::SequenceChartPlot, event::MouseMove)
    cursor = nothing
    if _in_body(g, event.x, event.y) && plot.chart.gutter.cursor_readout
        cursor = convert_coordinate_to_time(g.times, g.coordinates,
                                            to_data(g.scale, _get_flow(g, event.x, event.y)))
    end
    isequal(plot.cursor, cursor) ? nothing : _write_view_state(plot, "cursor", cursor)
end

function _clear_cursor(plot::SequenceChartPlot)
    plot.cursor === nothing && return nothing
    _write_view_state(plot, "cursor", nothing)
end

# ── View interaction ─────────────────────────────────────────────────────
#
# Every gesture here rewrites the window on the plot, and the frame re-derives
# the ticks, the labels and the decimation from it, so zooming in reveals more
# detail rather than magnifying pixels. The window zooms and pans inside the
# first and the last event, with the arithmetic of the plot slice that the chart
# uses.

const _ZOOM_STEP = 1.15      # per wheel notch
const _PAN_STEP = 0.1        # fraction of the window per notch along the time
const _LANE_SCROLL_STEP = 20 # the pixels that a notch moves the lanes
const _DRAG_MIN = 6          # a rubber band smaller than this is a click, not a zoom

# The window, the lane offset and the pointer are the state of the view, not of
# the trace: a write of one is marked as view state, so a history does not record
# a zoom, a scroll of the lanes or a readout.
_write_view_state(plot::SequenceChartPlot, field::AbstractString, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(plot, field, value))

# The first and the last coordinate of the trace, between which the window moves.
# A trace of one coordinate has the extent of the window that `resolve_window`
# gives it.
function _get_trace_extent(coordinates)
    isempty(coordinates) && return (0.0, 1.0)
    first_coordinate, last_coordinate = Float64(coordinates[1]), Float64(coordinates[end])
    (first_coordinate, last_coordinate > first_coordinate ? last_coordinate : first_coordinate + 1.0)
end

# What a gesture on the window needs: the coordinate of every event, the window
# that shows now and the extent that it stays in.
_make_window_state(coordinates, lo::Real, hi::Real) =
    (; coordinates, window = (Float64(lo), Float64(hi)), extent = _get_trace_extent(coordinates))

# The state of the window of the laid-out frame `g`, or of the plot alone, which
# lays out the timeline for itself.
_get_window_state(g) = _make_window_state(g.coordinates, g.lo, g.hi)

function _get_window_state(plot::SequenceChartPlot)
    plot.chart isa SequenceChart || return nothing
    coordinates = _timeline(plot.chart).coordinates
    isempty(coordinates) && return nothing
    lo, hi = resolve_window(plot, coordinates)
    _make_window_state(coordinates, lo, hi > lo ? hi : lo + 1.0)
end

# The write of the window `window`: the view `nothing` for the whole trace, and
# nothing for the window that shows now.
function _set_window(plot::SequenceChartPlot, state, window)
    window == state.extent && return plot.view === nothing ? nothing : _write_view_state(plot, "view", nothing)
    window == state.window && return nothing
    _window_operation(plot, state.coordinates, window[1], window[2] - window[1])
end

# The write of the window `window` as a move along the time: a move back from the
# end of a plot that follows the end stops the follow, as a scroll pane does.
function _move_window(plot::SequenceChartPlot, state, window)
    operation = _set_window(plot, state, window)
    (operation === nothing || !plot.follow_end || window[1] >= state.window[1]) && return operation
    CompoundOperation(Any[_write_view_state(plot, "follow_end", false), operation])
end

# The write of the window scaled by `factor` about the coordinate `focus`, or about
# its middle, inside the trace. A zoom at a limit writes nothing.
_zoom_window(plot::SequenceChartPlot, state, factor::Real; focus = nothing) =
    _set_window(plot, state, compute_zoomed_window(state.window, factor; extent = state.extent, focus))

# The write of the window moved by `fraction` of its span toward the end of the
# trace, inside the trace. A move that the trace stops writes nothing.
_pan_window(plot::SequenceChartPlot, state, fraction::Real) =
    _move_window(plot, state, compute_panned_window(state.window, fraction; extent = state.extent))

# The view actions that the keys, the menu and the buttons share: each answers the
# write of the view, or `nothing` at a limit.
_zoom_in_window(plot::SequenceChartPlot, state) = _zoom_window(plot, state, 1 / _ZOOM_STEP)
_zoom_out_window(plot::SequenceChartPlot, state) = _zoom_window(plot, state, _ZOOM_STEP)
_show_whole_trace(plot::SequenceChartPlot, state) = _set_window(plot, state, state.extent)

# The action `action` on the window that `plot` shows now.
function _compute_window_operation(action, plot::SequenceChartPlot)
    state = _get_window_state(plot)
    state === nothing ? nothing : action(plot, state)
end

# The distance of the lanes that the body shows across the time, in pixels.
_get_lane_page(g) = round(Int, g.vertical ? g.body_w : g.body_h)

# The largest scroll of the lanes: the room past the body, and never less than the
# scroll that the plot holds.
_get_cross_limit(g, plot::SequenceChartPlot) = max(Int(plot.cross_offset), ceil(Int, g.cross_room))

# The write of the scroll of the lanes `offset`, inside the room of the lanes. A
# scroll that changes nothing writes nothing.
function _set_cross_offset(g, plot::SequenceChartPlot, offset::Integer)
    offset = clamp(Int(offset), 0, _get_cross_limit(g, plot))
    offset == plot.cross_offset ? nothing : _write_view_state(plot, "cross_offset", offset)
end

# A window is stored relative to an event, so committing one means choosing the
# anchor: the first event at or after the window's start, falling back to the
# last event. Anchoring to an occurrence is what keeps the view still when the
# trace grows behind it.
function _window_operation(plot::SequenceChartPlot, coordinates, lo::Real, span::Real)
    n = length(coordinates)
    n == 0 && return nothing
    span > 0 || return nothing
    anchor = clamp(searchsortedfirst(coordinates, Float64(lo)), 1, n)
    view = SequenceChartView(anchor, Float64(lo) - coordinates[anchor], Float64(span))
    _write_view_state(plot, "view", view)
end

_compound(a, b) = a === nothing ? b : b === nothing ? a : CompoundOperation(Operation[a, b])

# The distance along the time of the canvas point `(x, y)` from the start of the
# body: the pixel that the scale of the window takes.
_get_flow(g, x::Real, y::Real) = g.vertical ? Float64(y) - g.body_y : Float64(x) - g.body_x

# The strips of the time scale, along the body: the gutter above and below it, or
# left and right of it. A drag there pans the time, and a double click fits it.
_is_over_time_axis(g, x::Integer, y::Integer) =
    any(r -> _in_rect(x, y, r...), _gutter_rects(g, g.gutter_h))

# Ctrl and the wheel zoom about the pointer, so whatever is under it stays under
# it — the only zoom that lets someone drive toward a detail rather than hunt for
# it again afterwards. With no Ctrl the wheel scrolls, as in a scroll pane: a
# turn away from the person shows what is above, or what is to the left. A turn
# along the time moves the window inside the first and the last event, and a turn
# across the time scrolls the lanes, as every turn over the lane labels does. A
# turn that moves nothing is not the chart's, so the page around it scrolls.
function _read_scroll(g, plot::SequenceChartPlot, gesture::MouseScroll)
    x, y = gesture.x, gesture.y
    on_labels = _label_strip_lane(g, x, y) !== nothing
    (on_labels || _in_body(g, x, y)) || return nothing
    gesture.modifiers.ctrl || return _scroll_sequence_chart(g, plot, gesture; on_labels)
    on_labels && return nothing

    notches = gesture.dy != 0 ? gesture.dy : gesture.dx
    notches == 0 && return nothing
    _zoom_window(plot, _get_window_state(g), _ZOOM_STEP^(-notches);
                 focus = to_data(g.scale, _get_flow(g, x, y)))
end

# The scroll of a turn with no Ctrl. Shift makes a turn go across also when the
# backend gives it as a vertical turn, and a touchpad moves by the fraction of a
# notch. The time runs across a horizontal chart and down a vertical one.
function _scroll_sequence_chart(g, plot::SequenceChartPlot, gesture::MouseScroll; on_labels::Bool)
    turn_x, turn_y = gesture.precise_dx, gesture.precise_dy
    across = gesture.modifiers.shift || (turn_x != 0 && turn_y == 0)
    turn = across ? (turn_x != 0 ? turn_x : turn_y) : turn_y
    turn == 0 && return nothing
    if on_labels || across == g.vertical
        return _set_cross_offset(g, plot, round(Int, plot.cross_offset - _LANE_SCROLL_STEP * turn))
    end
    _pan_window(plot, _get_window_state(g), -_PAN_STEP * turn)
end

# Dragging in the body draws a rubber band along the time and commits it as the new
# window; with Shift or the middle button it pans the time and the lanes instead,
# and a drag on the time axis pans the time. The lifecycle mirrors the splitter
# drag: the anchor goes down on press and starts the drag of the plot, the
# rectangle grows on each `DragMove`, and `DragEnd` either commits or — if the band
# never grew past a few pixels — leaves the window alone. The anchor keeps the
# view of the press as the plot holds it, so `DragCancel` puts back a pan.
function _drag_start(g, plot::SequenceChartPlot, event::MouseDown)
    mode = _find_drag_mode(g, event)
    mode === nothing && return nothing
    # A pan shows the closed hand while the drag is on; a band keeps the arrow of
    # the press.
    CompoundOperation(Operation[
        _write_view_state(plot, "drag_anchor",
                          (event.x, event.y, mode, (g.lo, g.hi), g.scale, plot.cross_offset,
                           plot.view, plot.follow_end)),
        StartDragOperation(EmptyReference(), nothing),
        make_screen_pointer_shape_operation(mode === :zoom ? :arrow : :closed_hand)])
end

# What a press starts: in the body a band zoom, or a pan with Shift or the middle
# button; on the time axis a pan of the time; elsewhere nothing.
function _find_drag_mode(g, event::MouseDown)
    pan = event.button === :middle || event.modifiers.shift
    _in_body(g, event.x, event.y) && return pan ? :pan : :zoom
    _is_over_time_axis(g, event.x, event.y) && return :pan_time
    nothing
end

# The rectangle that a band from the press `ax`, `ay` to `x`, `y` draws: across
# all the lanes, so the person sees that the release zooms the time alone.
function _get_band_rect(g, ax::Integer, ay::Integer, x::Integer, y::Integer)
    body_x, body_y, body_w, body_h = round(Int, g.body_x), round(Int, g.body_y),
                                     round(Int, g.body_w), round(Int, g.body_h)
    g.vertical ? (body_x, min(ay, y), body_w, abs(y - ay)) : (min(ax, x), body_y, abs(x - ax), body_h)
end

function _drag_move(g, plot::SequenceChartPlot, event::DragMove)
    anchor = plot.drag_anchor
    anchor === nothing && return nothing
    ax, ay, mode, window, scale, offset = anchor
    if mode !== :zoom
        # Pan against the window and the scroll the drag started from, so a slow
        # drag does not accumulate rounding, and a move to the point of the last
        # move gives the same window, which is not written again. The distance
        # along the time is a part of the pixel span of the scale of the press. The
        # lanes follow the pointer across the time, and a pan of the time alone
        # leaves them.
        along, across = g.vertical ? (ay - event.y, ax - event.x) : (ax - event.x, ay - event.y)
        state = _get_window_state(g)
        moved = compute_panned_window(window, along / (scale.p1 - scale.p0); extent = state.extent)
        return _compound(_move_window(plot, state, moved),
                         mode === :pan ? _set_cross_offset(g, plot, offset + across) : nothing)
    end
    _set_drag_rect(plot, _get_band_rect(g, ax, ay, event.x, event.y))
end

function _drag_end(g, plot::SequenceChartPlot, event::DragEnd)
    anchor = plot.drag_anchor
    anchor === nothing && return nothing
    ax, ay, mode, _, scale = anchor
    clear = _clear_drag(plot)
    mode === :zoom || return clear
    from, to = _get_flow(g, ax, ay), _get_flow(g, event.x, event.y)
    abs(to - from) >= _DRAG_MIN || return clear
    state = _get_window_state(g)
    window = compute_limited_window(minmax(to_data(scale, from), to_data(scale, to)); extent = state.extent)
    _compound(_set_window(plot, state, window), clear)
end

_set_drag_rect(plot::SequenceChartPlot, rect) =
    isequal(plot.drag_rect, rect) ? nothing : _write_view_state(plot, "drag_rect", rect)

# The write that ends a drag: the anchor and the band go, and the pointer is an
# arrow again.
_clear_drag(plot::SequenceChartPlot) = CompoundOperation(Operation[
    _write_view_state(plot, "drag_anchor", nothing),
    _write_view_state(plot, "drag_rect", nothing),
    make_screen_pointer_shape_operation(nothing)])

# The end of a drag with no change: a pan puts back the view of the press.
function _cancel_drag(plot::SequenceChartPlot)
    anchor = plot.drag_anchor
    (anchor === nothing && plot.drag_rect === nothing) && return nothing
    clear = _clear_drag(plot)
    (anchor !== nothing && anchor[3] !== :zoom) || return clear
    _, _, _, _, _, offset, view, follow_end = anchor
    back = Operation[]
    isequal(plot.view, view) || push!(back, _write_view_state(plot, "view", view))
    plot.follow_end == follow_end || push!(back, _write_view_state(plot, "follow_end", follow_end))
    plot.cross_offset == offset || push!(back, _write_view_state(plot, "cross_offset", offset))
    isempty(back) ? clear : CompoundOperation(Operation[back..., clear])
end

# Keyboard view control. This lives in the reader rather than in a `@gestures`
# block because the window belongs to the plot, and a document gesture only ever
# sees the chart.
#
# - Ctrl+=, Ctrl+- and Ctrl+0 zoom in, zoom out and show the whole trace, before
#   the zoom of the interface reads them, as a transform pane does. At a limit the
#   key is not the chart's, so Ctrl+0 on a chart that shows the whole trace resets
#   the zoom of the interface.
# - Page Up and Page Down scroll a page up and down, and with Alt a page across,
#   as in a spreadsheet. A page of the time is the window, and a page of the lanes
#   is the body.
# - The arrows and Shift with the left and right arrows belong to the navigation
#   along the events, so this reader declines them.
function _key_intent(g, plot::SequenceChartPlot, event::KeyDown)
    m = event.modifiers
    m.meta && return nothing
    key = event.key
    state = _get_window_state(g)
    if m.ctrl
        (m.shift || m.alt) && return nothing
        key === :equals && return _zoom_in_window(plot, state)
        key === :minus && return _zoom_out_window(plot, state)
        key === :zero && return _show_whole_trace(plot, state)
        return nothing
    end
    (key in (:page_up, :page_down) && !m.shift) || return nothing
    page = key === :page_down ? 1 : -1
    # A page along the time when the time runs the way the key points: down in a
    # vertical chart, and across with Alt in a horizontal one.
    m.alt != g.vertical && return _pan_window(plot, state, Float64(page))
    _set_cross_offset(g, plot, plot.cross_offset + page * _get_lane_page(g))
end

# Zoom and reset arrive as characters rather than named keys. A character typed
# with Ctrl or Alt is the key of the `KeyDown` reader, or of the editor.
function _key_intent(g, plot::SequenceChartPlot, event::KeyPress)
    m = event.modifiers
    (m.ctrl || m.alt || m.meta) && return nothing
    state = _get_window_state(g)
    event.char == '0' && return _show_whole_trace(plot, state)
    event.char in ('+', '=') && return _zoom_in_window(plot, state)
    event.char == '-' && return _zoom_out_window(plot, state)
    nothing
end

# ── The menu and the buttons ─────────────────────────────────────────────

"""
    compute_context_menu(plot::SequenceChartPlot) -> WidgetMenu | Nothing

The menu that a right click on a sequence chart opens: "Zoom in", "Zoom out" and
"Show the whole trace", each with its key. An item whose action changes nothing is
disabled. A plot that holds no chart has no menu.
"""
function compute_context_menu(plot::SequenceChartPlot)
    plot.chart isa SequenceChart || return nothing
    item(label, action, keys) =
        let operation = _compute_window_operation(action, plot)
            WidgetMenuItem(label; keys, enabled = operation !== nothing,
                           operation = something(operation, DoNothingOperation()))
        end
    WidgetMenu(Any[item("Zoom in", _zoom_in_window, Any["Ctrl+="]),
                   item("Zoom out", _zoom_out_window, Any["Ctrl+-"]),
                   item("Show the whole trace", _show_whole_trace, Any["Ctrl+0"])])
end

get_document_gesture_bindings_own(::Type{SequenceChartPlot}) =
    GestureBinding[make_context_menu_binding(compute_context_menu; description = "Show the menu of the sequence chart")]

"""
    make_sequence_chart_buttons(plot) -> WidgetToolbar

The buttons that show over `plot` while the pointer is over the chart: "Zoom in",
"Zoom out" and "Show the whole trace". A press does what the key of the button
does, and the tooltip names the key. A button whose action changes nothing is
disabled, so "Show the whole trace" is disabled while the chart shows it.
"""
function make_sequence_chart_buttons(plot::SequenceChartPlot)
    function button(label, icon, key, action)
        item = WidgetToolbarItem(label; icon, focusable = false, tooltip = "$label ($key)",
            gestures = GestureBinding[GestureBinding(MouseClickPattern(:left),
                                                     (_, _) -> _compute_window_operation(action, plot);
                                                     description = label, domain = "sequence chart")])
        set_cell_computation!(getfield(item, :enabled), () -> _compute_window_operation(action, plot) !== nothing)
        item
    end
    WidgetToolbar(Any[button("Zoom in", :zoom_in, "Ctrl+=", _zoom_in_window),
                      button("Zoom out", :zoom_out, "Ctrl+-", _zoom_out_window),
                      button("Show the whole trace", :maximize, "Ctrl+0", _show_whole_trace)])
end

"""
    make_sequence_chart_scroll_bar(plot, axis) -> WidgetScrollBar

The bar of `plot` along `axis`, `:time` or `:lanes`, which the renderer draws along
an edge of the body: the time along the edge that the time runs along, and the
lanes along the other. Its thumb is the part of the trace that the window shows,
or the part of the lanes that the body shows, and its value the place of the
window among the trace, or of the scroll among the room of the lanes; the renderer
sets both from its laid-out frame. A write of its value moves the view, and the
plot keeps the drag of its thumb.
"""
function make_sequence_chart_scroll_bar(plot::SequenceChartPlot, axis::Symbol)
    bar = WidgetScrollBar(:horizontal; thumb_size = 1.0)
    set_cell_computation!(getfield(bar, :orientation), () -> begin
        orientation = plot.chart isa SequenceChart ? plot.chart.orientation : :horizontal
        (axis === :time) == (orientation === :horizontal) ? :horizontal : :vertical
    end)
    bar
end

"""
    make_sequence_chart_projection(; measure, widget_theme = WidgetTheme(),
                                   width = 900, height = 520, theme = nothing) -> Projection

A sequence chart view: a `SequenceChart` through `SequenceChartToSequenceChartPlot`
and `SequenceChartPlotToGraphicsCanvas` to a `GraphicsCanvas`, with the buttons
that show while the pointer is over the chart and the bars of a zoomed or
scrolled chart. `theme`, `width` and `height` are those of the renderer of the
chart; `widget_theme` is that of the buttons and the bars.

The renderer prints the buttons and the bars through its recursion, and this
projection gives it a recursion that prints them, so a chart shows them in any
host. A chain of the two stages built by hand must give a recursion that prints a
`WidgetToolbar`, a `WidgetToolbarItem` and a `WidgetScrollBar`.
"""
make_sequence_chart_projection(; measure::TextMeasure, widget_theme = WidgetTheme(), kwargs...) =
    NestingProjection(ChainingProjection(SequenceChartToSequenceChartPlot(),
                                         SequenceChartPlotToGraphicsCanvas(; measure, kwargs...));
                      recursion = TypeDispatchingProjection(
                          WidgetToolbar => WidgetToolbarToGraphicsCanvas(widget_theme; measure),
                          WidgetToolbarItem => WidgetToolbarItemToGraphicsCanvas(widget_theme; measure),
                          WidgetScrollBar => WidgetScrollBarToGraphicsCanvas(widget_theme)))
