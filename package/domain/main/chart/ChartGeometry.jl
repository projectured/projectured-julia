"""
    ChartGeometryModule

The chart slice's arithmetic: axis scaling, tick selection, data↔pixel mapping,
and the decimation and folding that keep a chart's cost proportional to its
pixels rather than to its data.

Everything here is a pure function over plain numbers and vectors — no cells, no
document types, no dependency on the rest of the slice. That is deliberate, the
same split `GraphLayoutEngine` makes: the algorithms stay unit-testable headless
and a caller is free to memoize them in a reactive cell.

The scalability story lives here:

- [`visible_range`](@ref) binary-searches an ascending column for the indices
  overlapping the view window, so panning a huge series touches only what shows.
- [`decimate_minmax`](@ref) collapses every run of samples landing on one pixel
  column to at most four points (first, min, max, last). The result is
  pixel-identical to drawing all of them, so this is exact, not sampling.
- [`fold_scatter`](@ref) bins an overplotted cloud into a density grid.
- [`fold_bins`](@ref) merges bars or bins narrower than a pixel threshold.
- [`label_step`](@ref) thins tick labels that would otherwise collide.
"""
module ChartGeometryModule

export AxisScale, to_pixel, to_data, axis_span,
       column_bounds, merge_bounds, pad_range,
       nice_num, nice_ticks, log_ticks, format_tick,
       visible_range, decimate_minmax, step_points, pins_segments,
       fold_scatter, fold_bins, label_step,
       bin_values, histogram_values,
       legend_layout, anchor_offset

# Smallest positive value a log axis will map; below it the scale saturates
# rather than diverging to -Inf.
const _LOG_FLOOR = 1e-12

# ── Axis scale ───────────────────────────────────────────────────────────

"""
    AxisScale(lo, hi, p0, p1; log=false)

The affine (or log-affine) map from data coordinates to pixels: data `lo` sits
at pixel `p0` and data `hi` at pixel `p1`.

A y axis simply passes `p0` as the plot's *bottom* pixel and `p1` as its top, so
the screen's downward-growing y needs no separate flip flag.
"""
struct AxisScale
    lo::Float64
    hi::Float64
    p0::Float64
    p1::Float64
    log::Bool
end

AxisScale(lo::Real, hi::Real, p0::Real, p1::Real; log::Bool=false) =
    AxisScale(Float64(lo), Float64(hi), Float64(p0), Float64(p1), log)

_fwd(s::AxisScale, v::Real) = s.log ? log10(max(Float64(v), _LOG_FLOOR)) : Float64(v)
_inv(s::AxisScale, t::Real) = s.log ? exp10(Float64(t)) : Float64(t)

"""
    to_pixel(scale, value) -> Float64

Map a data coordinate to its pixel position. A degenerate scale (`lo == hi`)
maps everything to the midpoint of the pixel span rather than dividing by zero.
"""
function to_pixel(s::AxisScale, value::Real)
    t0, t1 = _fwd(s, s.lo), _fwd(s, s.hi)
    d = t1 - t0
    d == 0 && return (s.p0 + s.p1) / 2
    s.p0 + (_fwd(s, value) - t0) / d * (s.p1 - s.p0)
end

"""
    to_data(scale, pixel) -> Float64

The inverse of [`to_pixel`](@ref): what data coordinate a pixel stands for.
"""
function to_data(s::AxisScale, pixel::Real)
    dp = s.p1 - s.p0
    dp == 0 && return s.lo
    t0, t1 = _fwd(s, s.lo), _fwd(s, s.hi)
    _inv(s, t0 + (Float64(pixel) - s.p0) / dp * (t1 - t0))
end

"""
    axis_span(scale) -> Float64

The pixel length of the scale, always positive regardless of direction.
"""
axis_span(s::AxisScale) = abs(s.p1 - s.p0)

# ── Ranges ───────────────────────────────────────────────────────────────

"""
    column_bounds(values) -> (lo, hi) | nothing

The finite extent of a column, skipping `NaN`/`Inf`. Returns `nothing` when the
column holds no finite value at all, which callers treat as "this series
contributes no range".
"""
function column_bounds(values)
    lo = Inf; hi = -Inf
    @inbounds for v in values
        f = Float64(v)
        isfinite(f) || continue
        f < lo && (lo = f)
        f > hi && (hi = f)
    end
    lo > hi ? nothing : (lo, hi)
end

"""
    merge_bounds(a, b) -> (lo, hi) | nothing

Union of two optional ranges, so a chart can fold the per-series bounds into one.
"""
merge_bounds(::Nothing, ::Nothing) = nothing
merge_bounds(a, ::Nothing) = a
merge_bounds(::Nothing, b) = b
merge_bounds(a, b) = (min(a[1], b[1]), max(a[2], b[2]))

"""
    pad_range(lo, hi; fraction=0.05, include_zero=false, log=false) -> (lo, hi)

Widen a data range into a plotting range.

A degenerate range (a single value, or none) opens up to a unit-ish window so a
constant series still draws sensibly. When `include_zero` is set and the range
does not already straddle zero, the near side is extended to the origin with
*half* the usual padding — past that point the extension itself is the
whitespace, so a full margin on top would look lopsided. This mirrors the
origin-margin heuristic OMNeT++'s line plots use.
"""
function pad_range(lo::Real, hi::Real; fraction::Real=0.05,
                   include_zero::Bool=false, log::Bool=false)
    lo = Float64(lo); hi = Float64(hi)
    (isfinite(lo) && isfinite(hi)) || return (0.0, 1.0)
    if log
        lo = max(lo, _LOG_FLOOR); hi = max(hi, lo * 10)
        f = (hi / lo)^fraction
        return (lo / f, hi * f)
    end
    if hi == lo
        d = lo == 0 ? 1.0 : abs(lo) * 0.1
        return (lo - d, hi + d)
    end
    d = (hi - lo) * fraction
    lo2, hi2 = lo - d, hi + d
    if include_zero
        if lo > 0 && lo2 > 0
            lo2 = 0.0
        elseif hi < 0 && hi2 < 0
            hi2 = 0.0
        end
    end
    (lo2, hi2)
end

# ── Ticks ────────────────────────────────────────────────────────────────

"""
    nice_num(x, round_it) -> Float64

Heckbert's "nice number" from *Graphics Gems*: the 1/2/5/10 × 10ⁿ value nearest
`x` (rounded when `round_it`, otherwise the next one up). This is what puts tick
labels on round numbers instead of on whatever the data range happens to be.
"""
function nice_num(x::Real, round_it::Bool)
    x = Float64(x)
    x <= 0 && return 1.0
    e = floor(log10(x))
    f = x / exp10(e)
    nf = if round_it
        f < 1.5 ? 1.0 : f < 3.0 ? 2.0 : f < 7.0 ? 5.0 : 10.0
    else
        f <= 1.0 ? 1.0 : f <= 2.0 ? 2.0 : f <= 5.0 ? 5.0 : 10.0
    end
    nf * exp10(e)
end

"""
    nice_ticks(lo, hi, target) -> Vector{Float64}

Round tick positions covering `[lo, hi]`, aiming for about `target` of them.
Returns the two endpoints for a degenerate range.
"""
function nice_ticks(lo::Real, hi::Real, target::Integer=6)
    lo = Float64(lo); hi = Float64(hi)
    (isfinite(lo) && isfinite(hi) && hi > lo) && target >= 1 || return Float64[lo, hi]
    # The interval comes straight from the range, not from Heckbert's rounded-up
    # span: he expands the axis out to whole ticks, and we clip ticks to the
    # range instead, so rounding the span first would leave the axis with a
    # third of the ticks that were asked for.
    step = nice_num((hi - lo) / max(target - 1, 1), true)
    step > 0 || return Float64[lo, hi]
    first_tick = ceil(lo / step) * step
    ticks = Float64[]
    t = first_tick
    # Guard against a pathological step that would loop forever on huge ranges.
    limit = target * 10 + 10
    while t <= hi + step * 1e-9 && length(ticks) < limit
        push!(ticks, abs(t) < step * 1e-9 ? 0.0 : t)
        t += step
    end
    isempty(ticks) ? Float64[lo, hi] : ticks
end

"""
    log_ticks(lo, hi) -> Vector{Float64}

Decade ticks with 1/2/5 subdivisions — 0.1, 0.2, 0.5, 1, 2, 5, 10 … — clipped to
`[lo, hi]`. Falls back to whole decades once the range spans enough of them that
the subdivisions would crowd.
"""
function log_ticks(lo::Real, hi::Real)
    lo = max(Float64(lo), _LOG_FLOOR); hi = Float64(hi)
    hi > lo || return Float64[lo, max(hi, lo * 10)]
    d0 = floor(Int, log10(lo)); d1 = ceil(Int, log10(hi))
    mantissas = (d1 - d0) > 5 ? (1.0,) : (1.0, 2.0, 5.0)
    ticks = Float64[]
    for d in d0:d1, m in mantissas
        t = m * exp10(d)
        (t >= lo * (1 - 1e-9) && t <= hi * (1 + 1e-9)) && push!(ticks, t)
    end
    isempty(ticks) ? Float64[lo, hi] : ticks
end

"""
    format_tick(value, step) -> String

A tick label: plain decimal with just enough fraction digits to distinguish
neighbouring ticks `step` apart, or scientific notation once the magnitudes get
too small or too large for that to be readable.
"""
function format_tick(value::Real, step::Real=0.0)
    v = Float64(value)
    isfinite(v) || return string(v)
    v == 0 && return "0"
    a = abs(v)
    (a < 1e-3 || a >= 1e6) && return _sci(v)
    digits = 0
    if step > 0 && isfinite(step)
        digits = clamp(-floor(Int, log10(abs(step))) , 0, 6)
    else
        digits = a < 1 ? 3 : a < 10 ? 2 : a < 100 ? 1 : 0
    end
    s = string(round(v; digits=digits))
    endswith(s, ".0") ? s[1:end-2] : s
end

function _sci(v::Float64)
    e = floor(Int, log10(abs(v)))
    m = v / exp10(e)
    ms = string(round(m; digits=2))
    endswith(ms, ".0") && (ms = ms[1:end-2])
    string(ms, "e", e)
end

# ── Visible range and decimation ─────────────────────────────────────────

"""
    visible_range(x, lo, hi; sorted=true) -> (i0, i1)

The index range of `x` overlapping `[lo, hi]`, extended one index each way so
the segments entering and leaving the window still draw.

With `sorted` this is a binary search — O(log n) regardless of column length,
which is what makes panning a million-sample series cheap. Without it the whole
column is in range and the caller relies on decimation alone to bound the work.
Returns an empty range `(1, 0)` for an empty column.
"""
function visible_range(x, lo::Real, hi::Real; sorted::Bool=true)
    n = length(x)
    n == 0 && return (1, 0)
    sorted || return (1, n)
    i0 = searchsortedfirst(x, lo)
    i1 = searchsortedlast(x, hi)
    (max(1, i0 - 1), min(n, i1 + 1))
end

"""
    decimate_minmax(x, y, xs, ys, i0, i1) -> Vector{Tuple{Int,Int}}

Pixel points for a line through `x[i0:i1]`/`y[i0:i1]`, with every run of samples
landing on the same pixel column reduced to at most four: the first, the
lowest, the highest and the last, kept in index order.

Those four are exactly what a renderer needs to reproduce the column — the
vertical extent plus the segments joining the neighbouring columns — so the
decimated polyline is pixel-identical to the full one at this scale, not an
approximation. Output length is bounded by four times the plot width no matter
how long the columns are.
"""
function decimate_minmax(x, y, xs::AxisScale, ys::AxisScale, i0::Integer, i1::Integer)
    out = Tuple{Int,Int}[]
    i1 >= i0 || return out
    n = min(length(x), length(y))
    i0 = max(i0, 1); i1 = min(i1, n)
    i1 >= i0 || return out

    col = 0            # pixel column being accumulated
    have = false
    fi = mi = ai = li = 0          # first / min / max / last sample index in the column
    mv = Inf; av = -Inf

    flush!() = begin
        have || return
        idxs = (fi, mi, ai, li)
        prev = 0
        for k in sort!(collect(idxs))
            k == prev && continue
            prev = k
            push!(out, (col, round(Int, to_pixel(ys, y[k]))))
        end
    end

    @inbounds for i in i0:i1
        xv = Float64(x[i]); yv = Float64(y[i])
        (isfinite(xv) && isfinite(yv)) || continue
        c = round(Int, to_pixel(xs, xv))
        if !have
            col = c; have = true; fi = mi = ai = li = i; mv = av = yv
        elseif c != col
            flush!()
            col = c; fi = mi = ai = li = i; mv = av = yv
        else
            li = i
            yv < mv && (mv = yv; mi = i)
            yv > av && (av = yv; ai = i)
        end
    end
    flush!()
    out
end

"""
    step_points(points, mode) -> Vector{Tuple{Int,Int}}

Turn a polyline into a staircase.

`:steps_post` holds each value until the next sample (sample-and-hold),
`:steps_pre` jumps to the next value immediately (backward sample-and-hold), and
`:steps_mid` switches halfway between the samples. Any other mode returns the
points unchanged.
"""
function step_points(points::AbstractVector, mode::Symbol)
    (mode in (:steps_post, :steps_pre, :steps_mid) && length(points) >= 2) || return collect(points)
    out = Tuple{Int,Int}[]
    push!(out, (points[1][1], points[1][2]))
    for i in 2:length(points)
        x0, y0 = points[i-1]; x1, y1 = points[i]
        if mode === :steps_post
            push!(out, (x1, y0))
        elseif mode === :steps_pre
            push!(out, (x0, y1))
        else
            xm = (x0 + x1) ÷ 2
            push!(out, (xm, y0)); push!(out, (xm, y1))
        end
        push!(out, (x1, y1))
    end
    out
end

"""
    pins_segments(points, baseline) -> Vector{Tuple{Int,Int,Int}}

Vertical stems from `baseline` (a pixel row) up to each point, as
`(x, y_top, y_bottom)` triples — the "pins" draw style.
"""
function pins_segments(points::AbstractVector, baseline::Integer)
    segs = Tuple{Int,Int,Int}[]
    for p in points
        x, y = p[1], p[2]
        push!(segs, (x, min(y, baseline), max(y, baseline)))
    end
    segs
end

# ── Folding ──────────────────────────────────────────────────────────────

"""
    fold_scatter(x, y, xs, ys, cell_px, i0, i1; levels=8) -> Vector{Tuple{Int,Int,Int,Int,Int}}

Fold an overplotted point cloud into a density map, returning
`(x, y, width, height, level)` bands where `level` runs from 1 to `levels`.

Past a few thousand markers the individual points are no longer
distinguishable, so what matters is where the cloud is dense — which one shaded
band per run of equally-dense cells conveys just as well as a marker per point,
with a bounded number of elements.

Two things bound the output. Points are binned into a `cell_px` grid, so the
count is limited by the plot area rather than by the data; and the density is
quantized to `levels` before neighbouring cells in a row are merged into a
single band, so a dense region costs a handful of wide bands instead of
hundreds of little squares.
"""
function fold_scatter(x, y, xs::AxisScale, ys::AxisScale, cell_px::Integer,
                      i0::Integer, i1::Integer; levels::Integer=8)
    cell = max(Int(cell_px), 1)
    nlev = max(Int(levels), 1)
    counts = Dict{Tuple{Int,Int},Int}()
    n = min(length(x), length(y))
    i0 = max(i0, 1); i1 = min(i1, n)
    peak = 0
    @inbounds for i in i0:i1
        xv = Float64(x[i]); yv = Float64(y[i])
        (isfinite(xv) && isfinite(yv)) || continue
        px = round(Int, to_pixel(xs, xv)) ÷ cell
        py = round(Int, to_pixel(ys, yv)) ÷ cell
        c = get(counts, (px, py), 0) + 1
        counts[(px, py)] = c
        c > peak && (peak = c)
    end
    isempty(counts) && return Tuple{Int,Int,Int,Int,Int}[]

    # Square-root scaling: a linear ramp leaves everything but the densest
    # handful in the lowest band once one cell holds thousands.
    level_of(c) = clamp(ceil(Int, nlev * sqrt(c / peak)), 1, nlev)

    cells = sort!([(py, px, level_of(c)) for ((px, py), c) in counts])
    out = Tuple{Int,Int,Int,Int,Int}[]
    row, start_col, prev_col, level = cells[1][1], cells[1][2], cells[1][2], cells[1][3]
    flush!() = push!(out, (start_col * cell, row * cell,
                           (prev_col - start_col + 1) * cell, cell, level))
    @inbounds for k in 2:length(cells)
        r, c, l = cells[k]
        if r == row && l == level && c == prev_col + 1
            prev_col = c
        else
            flush!()
            row, start_col, prev_col, level = r, c, c, l
        end
    end
    flush!()
    out
end

"""
    fold_bins(lefts, rights, values, min_px) -> Vector{Tuple{Int,Int,Float64,Float64}}

Merge adjacent bins narrower than `min_px` pixels into envelope bars, returning
`(left, right, min_value, max_value)` per surviving bar.

Bins that are already wide enough pass through with `min == max`, so a caller
can draw every result the same way and only sees a difference where the folding
actually happened.
"""
function fold_bins(lefts::AbstractVector, rights::AbstractVector,
                   values::AbstractVector, min_px::Integer)
    out = Tuple{Int,Int,Float64,Float64}[]
    n = min(length(lefts), length(rights), length(values))
    n == 0 && return out
    w = max(Int(min_px), 1)
    i = 1
    @inbounds while i <= n
        l = Int(lefts[i]); r = Int(rights[i])
        lo = hi = Float64(values[i])
        j = i
        while (r - l) < w && j < n
            j += 1
            r = Int(rights[j])
            v = Float64(values[j])
            v < lo && (lo = v)
            v > hi && (hi = v)
        end
        push!(out, (l, max(r, l + 1), lo, hi))
        i = j + 1
    end
    out
end

"""
    label_step(count, span_px, label_px) -> Int

Draw every `k`-th label so that `count` labels of width `label_px` fit across
`span_px` pixels. Returns 1 when they all fit; this is what keeps a
ten-thousand-category axis from emitting ten thousand text elements.
"""
function label_step(count::Integer, span_px::Real, label_px::Real)
    count <= 0 && return 1
    per = Float64(span_px) / count
    per <= 0 && return count
    max(1, ceil(Int, Float64(label_px) / per))
end

# ── Legend ───────────────────────────────────────────────────────────────

"""
    legend_layout(sizes, horizontal, area_w, area_h; swatch, gap, line_gap, pad)
      -> (; cols, rows, col_w, row_h, box_w, box_h, shown, truncated)

Pack legend entries of the given measured `(width, height)` text sizes into a
box that fits `area_w × area_h`.

A `horizontal` legend (one above or below the plot) spreads into as many equal
columns as fit and wraps; a vertical one (beside the plot) is a single column.
When the entries do not all fit, `shown` is how many are drawn and `truncated`
says the caller should replace the last slot with an "and N more" line — which
is why `shown` leaves room for it rather than filling the box.
"""
function legend_layout(sizes::AbstractVector, horizontal::Bool,
                       area_w::Real, area_h::Real;
                       swatch::Integer=14, gap::Integer=6,
                       line_gap::Integer=4, pad::Integer=6)
    n = length(sizes)
    n == 0 && return (; cols=0, rows=0, col_w=0, row_h=0, box_w=0, box_h=0,
                        shown=0, truncated=false)
    text_w = maximum(sz[1] for sz in sizes)
    row_h = maximum(sz[2] for sz in sizes) + line_gap
    col_w = swatch + gap + text_w

    inner_w = max(Float64(area_w) - 2pad, Float64(col_w))
    inner_h = max(Float64(area_h) - 2pad, Float64(row_h))

    cols = horizontal ? clamp(floor(Int, (inner_w + gap) / (col_w + gap)), 1, n) : 1
    rows = cld(n, cols)

    max_rows = max(floor(Int, inner_h / row_h), 1)
    truncated = rows > max_rows
    if truncated
        rows = max_rows
        # One slot goes to the "and N more" line, so it is never itself hidden.
        shown = max(cols * rows - 1, 1)
    else
        shown = n
    end

    (; cols, rows, col_w, row_h,
       box_w = 2pad + cols * col_w + (cols - 1) * gap,
       box_h = 2pad + rows * row_h,
       shown, truncated)
end

"""
    anchor_offset(anchor, outer_w, outer_h, box_w, box_h) -> (dx, dy)

Where a box of `box_w × box_h` sits inside an `outer_w × outer_h` area for one
of the eight compass anchors. `:north` centres horizontally and pins to the top,
`:northeast` pins to both, and so on.
"""
function anchor_offset(anchor::Symbol, outer_w::Real, outer_h::Real,
                       box_w::Real, box_h::Real)
    free_w = max(Float64(outer_w) - box_w, 0.0)
    free_h = max(Float64(outer_h) - box_h, 0.0)
    west = anchor in (:northwest, :west, :southwest)
    east = anchor in (:northeast, :east, :southeast)
    north = anchor in (:northwest, :north, :northeast)
    south = anchor in (:southwest, :south, :southeast)
    dx = west ? 0.0 : east ? free_w : free_w / 2
    dy = north ? 0.0 : south ? free_h : free_h / 2
    (round(Int, dx), round(Int, dy))
end

# ── Histograms ───────────────────────────────────────────────────────────

"""
    bin_values(values, nbins) -> (edges, counts)

Bin a raw sample column into `nbins` equal-width bins over its finite extent,
returning `nbins + 1` edges and `nbins` counts. A degenerate column gets a unit
window so the histogram still has somewhere to draw.
"""
function bin_values(values, nbins::Integer)
    k = max(Int(nbins), 1)
    b = column_bounds(values)
    lo, hi = b === nothing ? (0.0, 1.0) : b
    hi <= lo && (hi = lo + 1.0)
    w = (hi - lo) / k
    edges = Float64[lo + i * w for i in 0:k]
    counts = zeros(Float64, k)
    @inbounds for v in values
        f = Float64(v)
        isfinite(f) || continue
        i = clamp(floor(Int, (f - lo) / w) + 1, 1, k)
        counts[i] += 1
    end
    (edges, counts)
end

"""
    histogram_values(edges, values, cumulative, density, total) -> Vector{Float64}

The four histogram value transforms, as the cross product of two flags: raw
counts, a density (count per unit bin width per total weight), a running sum,
and a CDF (running sum over total weight).

`total` is the weight the density and CDF forms normalize by — pass the sum of
the bin values plus any under/overflow so the CDF really reaches 1.
"""
function histogram_values(edges::AbstractVector, values::AbstractVector,
                          cumulative::Bool, density::Bool, total::Real=0.0)
    n = length(values)
    out = zeros(Float64, n)
    tw = Float64(total)
    tw > 0 || (tw = sum(Float64(v) for v in values; init=0.0))
    tw > 0 || (tw = 1.0)
    if cumulative
        acc = 0.0
        @inbounds for i in 1:n
            acc += Float64(values[i])
            out[i] = density ? acc / tw : acc
        end
    else
        @inbounds for i in 1:n
            v = Float64(values[i])
            if density
                w = i + 1 <= length(edges) ? Float64(edges[i+1]) - Float64(edges[i]) : 1.0
                out[i] = w > 0 ? v / w / tw : 0.0
            else
                out[i] = v
            end
        end
    end
    out
end

end # module
