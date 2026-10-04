# ── The plot vocabulary ───────────────────────────────────────────────────────
#
# What every plotted notation draws with: how a series that names no colour or
# marker gets one, and what shape a marker draws as.
#
# A chart and a sequence chart both hand colours out by position in the series
# list, and both draw the same marker shapes, so neither owns this. It sits
# beside the arithmetic above for the same reason.
#
# Everything here is a pure function over plain values, colours and integers. It
# knows no document type.

# ── Colour and marker cycles ─────────────────────────────────────────────

# The hues of the series of a plot, in the order of the roles `series_1` to
# `series_8` of the colour theme.
const _SERIES_HUES = (:blue, :orange, :green, :pink, :teal, :violet, :amber, :red)

"""
    default_color_cycle() -> Vector{StyleColor}

The per-series color cycle, in the order a plot hands them out to series that
leave `color` unset: the solid step of eight hues of the default palette, in the
light mode, as the roles `series_1` to `series_8` of the colour theme give them.
The cycle is content of the document, so it does not follow the mode.
"""
default_color_cycle() =
    StyleColor[compute_palette_color(find_palette(DEFAULT_PALETTE_NAME), PaletteColor(hue, 9), :light)
               for hue in _SERIES_HUES]

"""
    default_symbol_cycle() -> Vector{Symbol}

The per-series marker cycle, ordered so that consecutive series stay
distinguishable at a glance rather than by shape family.

The full set is `:circle`, `:square`, `:diamond`, `:triangle_up`,
`:triangle_down`, `:triangle_left`, `:triangle_right`, `:pentagon`,
`:hexagon`, `:star`, `:plus`, `:cross`, `:dot`, `:hline`, `:vline` and
`:none`.
"""
default_symbol_cycle() = Symbol[:circle, :square, :triangle_up, :diamond, :plus,
                                :star, :cross, :triangle_down, :pentagon, :dot]

"""
    get_series_color(series, index, cycle) -> StyleColor

A series' own `color`, or the `index`-th entry of the plot's color cycle when
it left the field unset. Cycling is by position in the series list, so inserting
a series shifts the colors after it — the same rule the reference charts use.
"""
function get_series_color(color, index::Integer, cycle)
    color === nothing || return color
    isempty(cycle) && return first(default_color_cycle())
    cycle[mod1(index, length(cycle))]
end

"""
    get_series_symbol(symbol, index, cycle) -> Symbol

The marker shape for a series: its own `symbol` unless that is `:cycle`, in
which case the `index`-th entry of the style's symbol cycle.
"""
function get_series_symbol(symbol::Symbol, index::Integer, cycle)
    symbol === :cycle || return symbol
    isempty(cycle) && return :circle
    cycle[mod1(index, length(cycle))]
end

# ── Marker outlines ──────────────────────────────────────────────────────

# The vertices of a regular `n`-gon of radius `r` about a centre, first vertex
# pointing whichever way `phase` says (a quarter turn back puts it at the top).
_regular_polygon(x::Int, y::Int, r::Int, n::Int, phase::Real=-pi/2) =
    [(round(Int, x + r * cos(phase + 2pi * k / n)),
      round(Int, y + r * sin(phase + 2pi * k / n))) for k in 0:(n-1)]

# A five-pointed star: outer and inner radii alternating around ten vertices.
# Concave, which is why it needs a real polygon rather than a triangle fan.
function _star_polygon(x::Int, y::Int, r::Int)
    inner = max(round(Int, r * 0.4), 1)
    [(round(Int, x + (isodd(k) ? inner : r) * cos(-pi/2 + pi * k / 5)),
      round(Int, y + (isodd(k) ? inner : r) * sin(-pi/2 + pi * k / 5))) for k in 0:9]
end

"""
    build_marker_polygon(shape, x, y, r) -> Vector{Tuple{Int,Int}} | nothing

The outline of a filled marker shape, or `nothing` for a shape that is not a
polygon.
"""
function build_marker_polygon(shape::Symbol, x::Int, y::Int, r::Int)
    shape === :diamond && return [(x, y - r), (x + r, y), (x, y + r), (x - r, y)]
    shape === :triangle_up && return _regular_polygon(x, y, r, 3)
    shape === :triangle_down && return _regular_polygon(x, y, r, 3, pi/2)
    shape === :triangle_left && return _regular_polygon(x, y, r, 3, pi)
    shape === :triangle_right && return _regular_polygon(x, y, r, 3, 0.0)
    shape === :pentagon && return _regular_polygon(x, y, r, 5)
    shape === :hexagon && return _regular_polygon(x, y, r, 6)
    shape === :star && return _star_polygon(x, y, r)
    nothing
end

