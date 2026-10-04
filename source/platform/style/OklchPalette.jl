# Fragment of `StyleModule` — the OKLCH palette: ramps made in OKLCH from a hue
# angle and a chroma, at one lightness for each step across every hue.

# The hue angle and the chroma of the solid step of each hue, and of each neutral.
const _OKLCH_HUES = (red = (25.0, 0.19), orange = (50.0, 0.17), amber = (80.0, 0.16),
                     green = (150.0, 0.15), teal = (185.0, 0.12), blue = (262.0, 0.19),
                     violet = (295.0, 0.17), pink = (350.0, 0.17))
const _OKLCH_NEUTRALS = (slate = (260.0, 0.02), gray = (0.0, 0.0), sand = (85.0, 0.015))

# The ramp of the angle `angle` with the chroma `chroma` at its solid step, in
# `mode`: at each step the lightness of the neutral ramp of Radix, so every hue has
# the same lightness at the same step, and the chroma of the steps of Radix blue.
_make_oklch_ramp(angle::Real, chroma::Real, mode::Symbol) =
    map((l, c) -> convert_oklch_to_color(l, chroma * c, angle),
        compute_step_lightness(:neutral, mode), compute_step_chroma(:blue, mode))

_make_oklch_ramps(mode::Symbol) =
    Dict{Symbol,NTuple{12,StyleColor}}(
        (name => _make_oklch_ramp(angle, chroma, mode)
         for (name, (angle, chroma)) in pairs(merge(_OKLCH_HUES, _OKLCH_NEUTRALS)))...)

"""
    OKLCH_PALETTE

The palette made in OKLCH: a ramp for each hue from its angle and its chroma, at
the same lightness for each step across every hue, so no token is lighter or
darker than another at the same step. Three neutrals: `slate` (cool, the
default), `gray` and `sand` (warm).
"""
const OKLCH_PALETTE = TablePalette("oklch";
    light = _make_oklch_ramps(:light), dark = _make_oklch_ramps(:dark),
    hues = Dict(name => name for name in keys(_OKLCH_HUES)),
    neutrals = [:slate, :gray, :sand])

register_palette!(OKLCH_PALETTE)
