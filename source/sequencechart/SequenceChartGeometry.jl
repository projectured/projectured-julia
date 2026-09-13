"""
    SequenceChartGeometryModule

The sequence chart slice's arithmetic: the timeline mapping that turns times
into a monotone coordinate, the conversions back and forth, tick selection for a
non-uniform axis, lane placement, arrow routing, and the decimation that keeps a
chart's cost proportional to its pixels rather than to its event count.

Everything here is a pure function over plain numbers and vectors — no cells, no
document types, no dependency on the rest of the slice, the same split
`ChartGeometry` makes.

**The three-stage coordinate pipeline** is the idea the whole slice rests on:

```
time ──(timeline mapping)──▶ timeline coordinate ──(AxisScale over the window)──▶ flow pixel
```

The middle stage is what makes a sequence chart different from a plot. Event
times in a trace span orders of magnitude — microseconds between two protocol
steps, seconds until the next timeout — and a linear axis can show one or the
other but never both. So the mapping is pluggable
([`get_timeline_coordinates`](@ref)): proportional to time, to an ordinal, one unit
per event, or the nonlinear compression that keeps every gap visible while
preserving which gap is longer.

Everything downstream works in **flow** and **cross** coordinates rather than x
and y: flow is the direction time runs, cross is the direction lanes stack.
[`FlowFrame`](@ref) maps that pair to pixels, and it is the only place that
knows whether the chart is drawn horizontally or vertically.
"""
module SequenceChartGeometryModule

import ..PlotModule: AxisScale, to_pixel, to_data, compute_nice_ticks, format_tick

export FlowFrame, flow_point, flow_rect, frame_flow_span, frame_cross_span,
       get_timeline_coordinates, default_nonlinear_focus,
       time_to_coordinate, convert_coordinate_to_time,
       get_visible_event_range, get_visible_arrows,
       flow_ticks, get_honest_tick_label, tick_common_prefix,
       get_zero_time_spans, get_axis_cross_positions,
       get_arc_geometry, split_arrow, get_arrow_route,
       decimate_events, deduplicate_arrow_coverage,
       get_band_intervals, get_event_ordinal

# ── The flow frame ───────────────────────────────────────────────────────

"""
    FlowFrame(orientation, x, y, w, h)

The rectangle a chart body occupies, plus which way time runs inside it.

`:horizontal` runs time to the right and stacks lanes downward — the classic
sequence chart. `:vertical` runs time downward and places lanes side by side,
which is how a UML sequence diagram reads. Every geometry function below works
in `(flow, cross)` pairs, and this maps them to pixels, so orientation is one
coordinate swap rather than a branch in every drawing routine.

The swap is safe for the backends: it is axis-aligned, and nothing here asks for
a rotation.
"""
struct FlowFrame
    orientation::Symbol
    x::Float64
    y::Float64
    w::Float64
    h::Float64
end

FlowFrame(orientation::Symbol, x::Real, y::Real, w::Real, h::Real) =
    FlowFrame(orientation, Float64(x), Float64(y), Float64(w), Float64(h))

"""
    frame_flow_span(frame) -> (lo, hi)

The pixel interval time runs across: left-to-right when horizontal,
top-to-bottom when vertical.
"""
frame_flow_span(f::FlowFrame) =
    f.orientation === :vertical ? (f.y, f.y + f.h) : (f.x, f.x + f.w)

"""
    frame_cross_span(frame) -> (lo, hi)

The pixel interval lanes stack across — the other one.
"""
frame_cross_span(f::FlowFrame) =
    f.orientation === :vertical ? (f.x, f.x + f.w) : (f.y, f.y + f.h)

"""
    flow_point(frame, flow, cross) -> (x, y)

Place a `(flow, cross)` pair in pixels.
"""
flow_point(f::FlowFrame, flow::Real, cross::Real) =
    f.orientation === :vertical ? (Float64(cross), Float64(flow)) :
                                  (Float64(flow), Float64(cross))

"""
    flow_rect(frame, flow, cross, flow_length, cross_length) -> (x, y, w, h)

Place a rectangle given in flow/cross terms — a band interval, a gutter strip, a
zero-time span.
"""
function flow_rect(f::FlowFrame, flow::Real, cross::Real,
                   flow_length::Real, cross_length::Real)
    x, y = flow_point(f, flow, cross)
    f.orientation === :vertical ? (x, y, Float64(cross_length), Float64(flow_length)) :
                                  (x, y, Float64(flow_length), Float64(cross_length))
end

# ── The timeline mapping ─────────────────────────────────────────────────

"""
    get_event_ordinal(ordinals, i) -> Float64

The ordinal of event row `i`: the column's entry when the chart carries one,
otherwise the row index itself.

An upstream filter that hides events keeps the original numbers here, so
`:ordinal` mode still shows the gaps where events were removed — the distinction
that separates it from `:step`. Rows sharing an ordinal share one coordinate,
which is how one occurrence appears on several lanes without occupying several
slots.
"""
get_event_ordinal(ordinals, i::Integer) =
    ordinals === nothing || i > length(ordinals) ? Float64(i) : Float64(ordinals[i])

"""
    default_nonlinear_focus(times) -> Float64

The gap length the nonlinear mapping treats as "typical": the mean spacing,
scaled down an order of magnitude so that a gap of average length already gets
most of its width. Degenerate inputs fall back to `1.0`.
"""
function default_nonlinear_focus(times)
    n = length(times)
    n < 2 && return 1.0
    span = Float64(times[n]) - Float64(times[1])
    (isfinite(span) && span > 0) || return 1.0
    focus = span / n / 10
    (isfinite(focus) && focus > 0) ? focus : 1.0
end

"""
    get_timeline_coordinates(times, ordinals, mode; focus=nothing, minimum=0.1) -> Vector{Float64}

The timeline coordinate of every event row — the middle stage of the coordinate
pipeline, computed in one cumulative pass.

The four modes:

- `:time` — the coordinate *is* the elapsed time. Faithful, and unreadable as
  soon as the interesting gaps differ by orders of magnitude.
- `:ordinal` — proportional to the event's ordinal, so every event gets equal
  room and filtered-out events leave a proportional hole.
- `:step` — one unit per event, holes and all closed up.
- `:nonlinear` — the compression that makes the tool worth having. Each gap gets
  `c + (1 − c)·atan(Δt / focus)/(π/2)` units: never less than `c`, never more
  than one, and strictly increasing in `Δt`. A microsecond gap and a
  ten-second gap both stay visible, and which of two gaps is longer is still
  readable off the picture even though their ratio is not.

Rows sharing an ordinal share a coordinate in every mode, so a duplicated
occurrence costs no width.
"""
function get_timeline_coordinates(times, ordinals, mode::Symbol;
                              focus=nothing, minimum::Real=0.1)
    n = length(times)
    out = Vector{Float64}(undef, n)
    n == 0 && return out
    c = Float64(minimum)

    if mode === :time
        t0 = Float64(times[1])
        @inbounds for i in 1:n
            out[i] = Float64(times[i]) - t0
        end
        return out
    end

    if mode === :ordinal
        o0 = get_event_ordinal(ordinals, 1)
        @inbounds for i in 1:n
            out[i] = get_event_ordinal(ordinals, i) - o0
        end
        return out
    end

    f = focus === nothing ? default_nonlinear_focus(times) : Float64(focus)
    (isfinite(f) && f > 0) || (f = 1.0)

    out[1] = 0.0
    previous_ordinal = get_event_ordinal(ordinals, 1)
    @inbounds for i in 2:n
        ordinal = get_event_ordinal(ordinals, i)
        if ordinal == previous_ordinal
            # The same occurrence seen again: no new slot, no width.
            out[i] = out[i-1]
            continue
        end
        delta = if mode === :step
            1.0
        else
            dt = abs(Float64(times[i]) - Float64(times[i-1]))
            isfinite(dt) ? c + (1 - c) * atan(dt / f) / (pi / 2) : 1.0
        end
        out[i] = out[i-1] + delta
        previous_ordinal = ordinal
    end
    out
end

"""
    time_to_coordinate(times, coordinates, t; upper=false) -> Float64

Where a time sits on the timeline, interpolated linearly inside whichever gap
encloses it.

A time that several events share spans a *range* of coordinates rather than a
point — that is exactly what a zero-time region is — so `upper` picks which edge
of the range is meant. This is the conversion a timeline-mode switch runs
through; it is deliberately not how the live view window is stored, because a
pair of times cannot name a window *inside* such a range.
"""
function time_to_coordinate(times, coordinates, t::Real; upper::Bool=false)
    n = min(length(times), length(coordinates))
    n == 0 && return 0.0
    t = Float64(t)
    t <= Float64(times[1]) && return coordinates[1]
    t >= Float64(times[n]) && return coordinates[n]
    # The last index whose time is <= t, then the run of equal times around it.
    i = searchsortedlast(view(times, 1:n), t)
    i = clamp(i, 1, n)
    if Float64(times[i]) == t
        lo = i; hi = i
        while lo > 1 && Float64(times[lo-1]) == t
            lo -= 1
        end
        while hi < n && Float64(times[hi+1]) == t
            hi += 1
        end
        return upper ? coordinates[hi] : coordinates[lo]
    end
    i >= n && return coordinates[n]
    t0 = Float64(times[i]); t1 = Float64(times[i+1])
    c0 = coordinates[i]; c1 = coordinates[i+1]
    t1 == t0 && return upper ? c1 : c0
    c0 + (t - t0) / (t1 - t0) * (c1 - c0)
end

"""
    convert_coordinate_to_time(times, coordinates, c) -> Float64

The inverse: what time a timeline coordinate stands for, interpolated inside the
enclosing gap. Inside a zero-time region every coordinate maps to the one time
the region holds, which is the honest answer.
"""
function convert_coordinate_to_time(times, coordinates, c::Real)
    n = min(length(times), length(coordinates))
    n == 0 && return 0.0
    c = Float64(c)
    c <= coordinates[1] && return Float64(times[1])
    c >= coordinates[n] && return Float64(times[n])
    i = searchsortedlast(view(coordinates, 1:n), c)
    i = clamp(i, 1, n - 1)
    c0 = coordinates[i]; c1 = coordinates[i+1]
    t0 = Float64(times[i]); t1 = Float64(times[i+1])
    c1 == c0 && return t0
    t0 + (c - c0) / (c1 - c0) * (t1 - t0)
end

# ── Visible ranges ───────────────────────────────────────────────────────

"""
    get_visible_event_range(coordinates, lo, hi) -> (i0, i1)

The rows whose coordinates overlap `[lo, hi]`, one index wider each way so
whatever enters and leaves the window still draws. A binary search: panning a
long trace touches only what shows. Empty input gives the empty range `(1, 0)`.
"""
function get_visible_event_range(coordinates, lo::Real, hi::Real)
    n = length(coordinates)
    n == 0 && return (1, 0)
    i0 = searchsortedfirst(coordinates, Float64(lo))
    i1 = searchsortedlast(coordinates, Float64(hi))
    (max(1, i0 - 1), min(n, i1 + 1))
end

"""
    get_visible_arrows(coordinates, sources, targets, lo, hi; horizon=0.0) -> Vector{Int}

Which arrows can affect the window `[lo, hi]`, widened by `horizon`.

Membership is by **interval overlap**, not by whether an endpoint is inside the
window: an arrow whose cause is off the left edge and whose consequence is off
the right edge crosses everything the viewer is looking at, and dropping it
would erase the very connection the chart exists to show.

The scan is linear in the arrow count, which suits this slice's bounded-document
posture — a chart is windowed upstream before it is printed.
"""
function get_visible_arrows(coordinates, sources, targets, lo::Real, hi::Real;
                        horizon::Real=0.0)
    out = Int[]
    n = min(length(sources), length(targets))
    n == 0 && return out
    events = length(coordinates)
    lo = Float64(lo) - Float64(horizon)
    hi = Float64(hi) + Float64(horizon)
    @inbounds for k in 1:n
        s = sources[k]; t = targets[k]
        (1 <= s <= events && 1 <= t <= events) || continue
        cs = coordinates[s]; ct = coordinates[t]
        a = min(cs, ct); b = max(cs, ct)
        (b >= lo && a <= hi) && push!(out, k)
    end
    out
end

# ── Ticks ────────────────────────────────────────────────────────────────

"""
    get_honest_tick_label(t, neighbourhood) -> String

The shortest decimal that still names this tick unambiguously at this zoom.

A tick stands for a pixel, and a pixel stands for a span of time
`± neighbourhood`. Printing more digits than that span justifies is noise
dressed as precision, so this rounds to the fewest digits that still land inside
the neighbourhood. Zooming in lengthens the labels on its own, exactly as far as
the extra resolution earns.
"""
function get_honest_tick_label(t::Real, neighbourhood::Real)
    v = Float64(t)
    isfinite(v) || return string(v)
    n = abs(Float64(neighbourhood))
    (isfinite(n) && n > 0) || return format_tick(v, 0.0)
    for digits in 0:12
        r = round(v; digits=digits)
        abs(r - v) <= n && return format_tick(r, exp10(-digits))
    end
    format_tick(v, 0.0)
end

"""
    tick_common_prefix(labels) -> (prefix, suffixes)

Factor the leading characters every tick label shares out into one string.

Deep into a long run the labels differ in their last digits and agree in all the
others; showing `1.024000` … `1.024003` spends the whole gutter on the part that
never changes. The shared head is drawn once and each tick keeps its tail. The
split is only taken when it pays and never mid-number in a way that misleads: it
stops at the last position all labels agree on, and is refused when fewer than
two characters would be saved.
"""
function tick_common_prefix(labels)
    n = length(labels)
    n < 2 && return ("", collect(String, labels))
    first_label = String(labels[1])
    limit = length(first_label)
    for l in labels
        limit = min(limit, length(String(l)))
    end
    shared = 0
    for i in 1:limit
        c = first_label[i]
        all(String(l)[i] == c for l in labels) || break
        shared = i
    end
    # A prefix worth pulling out has to save more than it costs to print.
    shared < 2 && return ("", collect(String, labels))
    prefix = first_label[1:shared]
    (prefix, String[String(l)[shared+1:end] for l in labels])
end

"""
    flow_ticks(times, coordinates, scale, mode; target_px=100) -> Vector{(coordinate, time)}

Where the gutter's ticks go and what time each one stands for.

In `:time` mode the timeline is uniform, so the ticks are round numbers off the
1-2-5 ladder and land wherever those numbers fall. In every other mode a round
time has no fixed width, so the ticks are placed at even *pixel* intervals
instead and each one is labelled with the time that happens to be there — which
is why [`get_honest_tick_label`](@ref) exists.
"""
function flow_ticks(times, coordinates, scale::AxisScale, mode::Symbol;
                    target_px::Real=100)
    out = Tuple{Float64,Float64}[]
    n = min(length(times), length(coordinates))
    n == 0 && return out
    p0, p1 = scale.p0, scale.p1
    span = abs(p1 - p0)
    span <= 0 && return out
    count = max(2, floor(Int, span / max(Float64(target_px), 1.0)) + 1)

    if mode === :time
        t_lo = convert_coordinate_to_time(times, coordinates, scale.lo)
        t_hi = convert_coordinate_to_time(times, coordinates, scale.hi)
        for t in compute_nice_ticks(t_lo, t_hi, count)
            c = time_to_coordinate(times, coordinates, t)
            (scale.lo <= c <= scale.hi) && push!(out, (c, Float64(t)))
        end
        return out
    end

    step = (scale.hi - scale.lo) / (count - 1)
    step > 0 || return out
    for k in 0:(count-1)
        c = scale.lo + k * step
        push!(out, (c, convert_coordinate_to_time(times, coordinates, c)))
    end
    out
end

"""
    get_zero_time_spans(times, coordinates, lo, hi) -> Vector{(c0, c1)}

The coordinate spans where the clock does not advance.

Under any mapping but `:time` these have width, and width normally reads as
duration — so without marking them the picture lies. Shading them says "the
distance you see here is ordering, not elapsed time", which is what makes a
nonlinear timeline safe to read.
"""
function get_zero_time_spans(times, coordinates, lo::Real, hi::Real)
    out = Tuple{Float64,Float64}[]
    n = min(length(times), length(coordinates))
    n < 2 && return out
    lo = Float64(lo); hi = Float64(hi)
    i = 1
    @inbounds while i < n
        if Float64(times[i+1]) == Float64(times[i])
            j = i + 1
            while j < n && Float64(times[j+1]) == Float64(times[i])
                j += 1
            end
            c0 = coordinates[i]; c1 = coordinates[j]
            (c1 > c0 && c1 >= lo && c0 <= hi) && push!(out, (max(c0, lo), min(c1, hi)))
            i = j
        else
            i += 1
        end
    end
    out
end

# ── Lane placement ───────────────────────────────────────────────────────

"""
    get_axis_cross_positions(count, band_heights, cross_lo, cross_hi; spacing=nothing,
                         minimum_spacing=14.0, offset=20.0) -> Vector{Float64}

The cross-axis centre of every lane, in display order.

With `spacing` unset the lanes divide the available room between them, which
keeps a chart of any lane count filling its pane; pass a number to pin the
spacing instead and let the lanes overflow into a scroll. A lane carrying a
state band needs extra room, so its band height widens its slot.
"""
function get_axis_cross_positions(count::Integer, band_heights, cross_lo::Real, cross_hi::Real;
                              spacing=nothing, minimum_spacing::Real=14.0,
                              offset::Real=20.0)
    out = Float64[]
    count <= 0 && return out
    cross_lo = Float64(cross_lo); cross_hi = Float64(cross_hi)
    available = cross_hi - cross_lo - 2 * Float64(offset)
    total_bands = 0.0
    for i in 1:count
        total_bands += _band_height(band_heights, i)
    end
    # Dividing by the number of *gaps* rather than of lanes is what makes the
    # outermost lanes land on the edges of the room they were given; dividing by
    # the lane count leaves a lane's worth of space unused at the far end.
    gap = if spacing === nothing
        count == 1 ? 0.0 :
            max(Float64(minimum_spacing), (available - total_bands) / (count - 1))
    else
        max(Float64(minimum_spacing), Float64(spacing))
    end
    position = cross_lo + Float64(offset)
    for i in 1:count
        h = _band_height(band_heights, i)
        position += h
        push!(out, position)
        position += gap
    end
    out
end

_band_height(heights, i::Integer) =
    heights === nothing || i > length(heights) ? 0.0 : Float64(heights[i])

# ── Arrow routing ────────────────────────────────────────────────────────

"""
    get_arrow_route(route, same_lane) -> :direct | :arc

What shape an arrow takes. `:auto` draws an arc when both ends sit on one lane —
a straight line there would be invisible, hidden inside the lane it runs along —
and a direct line otherwise.
"""
function get_arrow_route(route::Symbol, same_lane::Bool)
    route === :direct && return :direct
    route === :arc && return :arc
    same_lane ? :arc : :direct
end

"""
    get_arc_geometry(flow0, flow1, cross, height) -> Vector{Tuple{Float64,Float64}}

Bezier control points for a same-lane arrow: a half-ellipse rising off the lane
and returning to it, in `(flow, cross)` pairs, with the four-point cubic whose
`4/3` handle height reproduces a semi-ellipse closely enough to read as one.

The arc bulges toward *lower* cross coordinates — above the lane in a horizontal
chart — which is where there is room, since the lane's own events sit on the
line itself.
"""
function get_arc_geometry(flow0::Real, flow1::Real, cross::Real, height::Real)
    f0 = Float64(flow0); f1 = Float64(flow1)
    c = Float64(cross); h = abs(Float64(height))
    handle = c - h * 4 / 3
    [(f0, c), (f0, handle), (f1, handle), (f1, c)]
end

"""
    arc_height(row_delta, spacing; minimum=15.0, buckets=4) -> Float64

How high a same-lane arc rises. Consecutive arcs on one lane would otherwise
trace the same curve and become one smear, so the height cycles through a few
buckets keyed on the distance between the two rows — deterministic, so the
picture is stable across repaints, and varied enough that neighbours separate.
"""
function arc_height(row_delta::Integer, spacing::Real; minimum::Real=15.0, buckets::Integer=4)
    b = max(Int(buckets), 1)
    step = max(Float64(spacing), Float64(minimum)) / b
    Float64(minimum) + step * (mod(abs(Int(row_delta)), b))
end

"""
    split_arrow(flow0, flow1, horizon, stub) -> nothing | (near, far)

How to draw an arrow whose ends are further apart than `horizon` pixels.

Drawing the whole line would sweep a shape the size of the window and say
nothing: at that length the line's angle carries no information and its middle
is off screen anyway. So each end keeps a stub of its own — solid where it is
anchored to a real event, and the pair reads as "this continues past the edge".
Returns `nothing` when the arrow is short enough to draw whole.

Each half is `(flow_from, flow_to)`, oriented outward from its anchored end.
"""
function split_arrow(flow0::Real, flow1::Real, horizon::Real, stub::Real)
    f0 = Float64(flow0); f1 = Float64(flow1)
    h = abs(Float64(horizon)); s = abs(Float64(stub))
    abs(f1 - f0) <= h && return nothing
    direction = f1 > f0 ? 1.0 : -1.0
    ((f0, f0 + direction * s), (f1, f1 - direction * s))
end

# ── Decimation ───────────────────────────────────────────────────────────

"""
    decimate_events(coordinates, axes, scale, i0, i1; kinds=nothing, separation=1) -> Vector{Int}

The rows worth drawing in the window: at most one per lane, per kind, per
`separation` pixels.

A mark is a disc, not a pixel. Where events are packed closer together than the
disc is wide, every one of them paints ground the one before it already covered,
and the reader sees a solid run either way. So `separation` is the mark's own
radius: consecutive drawn marks still overlap heavily, the run stays unbroken,
and the count drops by the width of a mark instead of standing at one per pixel.

Keyed by **kind** as well as by lane, because collapsing marks of different
kinds would lose the thing they were drawn to distinguish — a crowded stretch
must still show that a timeout happened among the ordinary receives.

Zoomed in far enough that marks no longer touch, nothing is dropped at all.
"""
function decimate_events(coordinates, axes, scale::AxisScale, i0::Integer, i1::Integer;
                         kinds=nothing, separation::Integer=1)
    out = Int[]
    i1 >= i0 || return out
    n = min(length(coordinates), length(axes))
    i0 = max(Int(i0), 1); i1 = min(Int(i1), n)
    gap = max(Int(separation), 1)
    last_pixel = Dict{Tuple{Int,Int},Int}()
    @inbounds for i in i0:i1
        lane = Int(axes[i])
        kind = (kinds === nothing || i > length(kinds)) ? 0 : Int(kinds[i])
        pixel = round(Int, to_pixel(scale, coordinates[i]))
        key = (lane, kind)
        previous = get(last_pixel, key, nothing)
        (previous !== nothing && abs(pixel - previous) < gap) && continue
        last_pixel[key] = pixel
        push!(out, i)
    end
    out
end

"""
    deduplicate_arrow_coverage(candidates, flows, crosses, tolerance=1.0) -> Vector{Int}

Thin a bundle of near-parallel arrows down to the pixels they actually cover.

Zoomed out, thousands of arrows collapse onto the same few pixel columns and
redraw the same marks; keeping one per distinct covered interval leaves the
picture identical and the element count bounded by the pixels, not the traffic.
An arrow spanning more than a pixel of flow is never dropped — it is a shape in
its own right, not part of a bundle.

`flows[k]` and `crosses[k]` are the `(from, to)` pixel pairs of candidate `k`.
"""
function deduplicate_arrow_coverage(candidates, flows, crosses; tolerance::Real=1.0)
    out = Int[]
    covered = Dict{Int,Vector{Tuple{Int,Int}}}()
    tolerance = Float64(tolerance)
    for (index, k) in enumerate(candidates)
        f0, f1 = flows[index]
        c0, c1 = crosses[index]
        if abs(f1 - f0) > tolerance
            push!(out, k)                       # a real shape, always drawn
            continue
        end
        column = round(Int, (f0 + f1) / 2)
        lo = round(Int, min(c0, c1)); hi = round(Int, max(c0, c1))
        spans = get!(() -> Tuple{Int,Int}[], covered, column)
        _span_covered(spans, lo, hi) && continue
        _span_insert!(spans, lo, hi)
        push!(out, k)
    end
    out
end

# Coverage is against the **union** of what the column already holds, not
# against any one interval of it: two arrows that each add nothing beyond what
# a third pair already painted still add nothing together, and testing them one
# at a time would draw them both.
function _span_covered(spans, lo::Int, hi::Int)
    for (a, b) in spans
        a <= lo && hi <= b && return true
    end
    # Walk the merged cover from `lo` upward, extending through every span that
    # touches what is reached so far.
    reach = lo
    progressed = true
    while progressed && reach < hi
        progressed = false
        for (a, b) in spans
            if a <= reach && b > reach
                reach = b
                progressed = true
            end
        end
    end
    reach >= hi
end

# Insert and coalesce, so the column's cover stays a short list of disjoint
# intervals however many arrows land on it.
function _span_insert!(spans, lo::Int, hi::Int)
    merged_lo = lo; merged_hi = hi
    keep = Tuple{Int,Int}[]
    for (a, b) in spans
        if b < merged_lo || a > merged_hi
            push!(keep, (a, b))
        else
            merged_lo = min(merged_lo, a)
            merged_hi = max(merged_hi, b)
        end
    end
    push!(keep, (merged_lo, merged_hi))
    resize!(spans, length(keep))
    copyto!(spans, keep)
    spans
end

"""
    get_band_intervals(band_times, values, events, event_times, coordinates, lo, hi)
        -> Vector{(c0, c1, value, index)}

The visible run of a lane's state band, as coordinate intervals.

A band is sample-and-hold: a value holds from its own sample until the next one,
so an interval — not a point — is what gets painted.

A band's samples are timestamped in the trace's own clock, and turning one of
those into a coordinate takes the *event* timeline (`event_times` paired with
`coordinates`) — the band's own times say nothing about where the axis has been
stretched. Anchoring a sample to an event row instead skips that conversion, and
that is the accurate way wherever several events share a time: the raw time
names the whole zero-time region, while the state changed at one point inside it.
"""
function get_band_intervals(band_times, values, events, event_times, coordinates,
                        lo::Real, hi::Real)
    out = Tuple{Float64,Float64,Float64,Int}[]
    n = min(length(band_times), length(values))
    n == 0 && return out
    lo = Float64(lo); hi = Float64(hi)
    total = length(coordinates)
    edge(i) = begin
        if events !== nothing && i <= length(events)
            row = Int(events[i])
            1 <= row <= total && return coordinates[row]
        end
        time_to_coordinate(event_times, coordinates, band_times[i])
    end
    @inbounds for i in 1:n
        c0 = edge(i)
        c1 = i < n ? edge(i + 1) : (total == 0 ? c0 : coordinates[total])
        c1 > c0 || (c1 = c0)
        (c1 < lo || c0 > hi) && continue
        push!(out, (max(c0, lo), min(c1, hi), Float64(values[i]), i))
    end
    out
end

end # module
