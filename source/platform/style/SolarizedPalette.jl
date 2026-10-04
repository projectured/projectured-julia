# Fragment of `StyleModule` — the Solarized palette: the base tones of Solarized
# as a neutral ramp, and a ramp around each of its eight accents. The colours of
# Solarized and their notice are in `Color.jl`.

# The base tones of Solarized, from base3 to base03.
const _SOLARIZED_BASE = [color_solarized_background_lighter, color_solarized_background_light,
                         color_solarized_content_lighter, color_solarized_content_light,
                         color_solarized_content_dark, color_solarized_content_darker,
                         color_solarized_background_dark, color_solarized_background_darker]

# Each accent of Solarized, by the name of its ramp, with the hue of the palette
# that it gives and whose lightness its ramp takes.
const _SOLARIZED_ACCENTS = (yellow = (:amber, color_solarized_yellow),
                            orange = (:orange, color_solarized_orange),
                            red = (:red, color_solarized_red),
                            magenta = (:pink, color_solarized_magenta),
                            violet = (:violet, color_solarized_violet),
                            blue = (:blue, color_solarized_blue),
                            cyan = (:teal, color_solarized_cyan),
                            green = (:green, color_solarized_green))

# The ramps of Solarized in `mode`: the base tones resampled, and a ramp around
# each accent, with the accent at step 9.
_make_solarized_ramps(mode::Symbol) =
    Dict{Symbol,NTuple{12,StyleColor}}(
        :base => make_resampled_ramp(_SOLARIZED_BASE, :neutral, mode),
        (name => make_generated_ramp(color, hue, mode) for (name, (hue, color)) in pairs(_SOLARIZED_ACCENTS))...)

"""
    SOLARIZED_PALETTE

The palette of Solarized: one neutral ramp, `base`, from the eight base tones, so
the window of the light mode is base3 and that of the dark mode is base03, and a
ramp around each of the eight accents, with the accent itself at step 9. The hue
`amber` is the Solarized yellow, `teal` its cyan and `pink` its magenta.
"""
const SOLARIZED_PALETTE = TablePalette("solarized";
    light = _make_solarized_ramps(:light), dark = _make_solarized_ramps(:dark),
    hues = Dict(hue => name for (name, (hue, _)) in pairs(_SOLARIZED_ACCENTS)),
    neutrals = [:base])

register_palette!(SOLARIZED_PALETTE)
