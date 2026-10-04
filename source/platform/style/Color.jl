# Fragment of `StyleModule` — `StyleColor` and the colours. Two functions write
# a colour as text and read it back, others compare, interpolate and shade a
# colour and measure the contrast of two; everything else here is data: about
# 80 named constants, in curated ramps.
#
# The Solarized colours are the values of Solarized,
# https://ethanschoonover.com/solarized, under the MIT License:
#
# Copyright (c) 2011 Ethan Schoonover
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# The zinc, the slate and the indigo ramps and `color_destructive` are the
# values of the default colour palette of Tailwind CSS 3, https://tailwindcss.com,
# under the MIT License:
#
# Copyright (c) Tailwind Labs, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""
    StyleColor(red, green, blue, alpha = 1.0)

A colour, as four parts from zero to one.

Use it wherever something is painted: the fill of a box, the ink of a word, the
line of a chart. A colour with a name is a constant, `color_black`,
`color_red`, `color_slate_500`, and the themes carry curated ramps; a colour
with an alpha below one lets what is behind it show through.

# Example

    GraphicsRect(0, 0, 10, 10; color = color_slate_200)
    faint = StyleColor(0.0, 0.0, 0.0, 0.25)

See also `StyleText`, which pairs a colour with a font, and `GraphicsRect`.
"""
@document ImmutableCell [DC] struct StyleColor
    red::Float64
    green::Float64
    blue::Float64
    alpha::Float64
    selection::Nothing
end

# ── Construction ──────────────────────────────────────────────────────────────

make_style_color(red, green, blue, alpha) = StyleColor(red, green, blue, alpha)

# Internal helper: construct from 0-255 integer components with alpha = 1.0
_color(r, g, b) = StyleColor(r / 255.0, g / 255.0, b / 255.0, 1.0)

# ── Text ──────────────────────────────────────────────────────────────────────

"""
    format_style_color(color) -> String

`color` as text, `#rrggbbaa`: each of the four parts as two hex digits.
[`convert_text_to_style_color`](@ref) reads it back.
"""
format_style_color(color::StyleColor) =
    "#" * join(string(round(Int, clamp(c, 0, 1) * 255); base = 16, pad = 2)
               for c in (color.red, color.green, color.blue, color.alpha))

"""
    convert_text_to_style_color(text) -> StyleColor or nothing

The colour that `text` names as `#rrggbb` or `#rrggbbaa`, with hex digits in
either case, or `nothing` for a text of another form. With no alpha the colour is
opaque.
"""
function convert_text_to_style_color(text::AbstractString)
    found = match(r"^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$", text)
    found === nothing && return nothing
    digits = found[1] * something(found[2], "ff")
    StyleColor((parse(Int, digits[i:i+1]; base = 16) / 255 for i in 1:2:7)...)
end

# ── Default ───────────────────────────────────────────────────────────────────

const color_default = _color(0, 0, 0)

# ── Pure ──────────────────────────────────────────────────────────────────────

const color_black  = _color(0, 0, 0)
const color_white  = _color(255, 255, 255)

# The one color that draws nothing: alpha 0. A part in this color is not drawn.
const color_transparent = StyleColor(0.0, 0.0, 0.0, 0.0)
const color_red    = _color(255, 0, 0)
const color_green  = _color(0, 255, 0)
const color_blue   = _color(0, 0, 255)
const color_yellow = _color(255, 255, 0)
const color_purple = _color(255, 0, 255)
const color_cyan   = _color(0, 255, 255)

# ── Gray ──────────────────────────────────────────────────────────────────────

const color_gray0   = _color(0, 0, 0)
const color_gray15  = _color(15, 15, 15)
const color_gray31  = _color(31, 31, 31)
const color_gray47  = _color(47, 47, 47)
const color_gray63  = _color(63, 63, 63)
const color_gray79  = _color(79, 79, 79)
const color_gray95  = _color(95, 95, 95)
const color_gray111 = _color(111, 111, 111)
const color_gray127 = _color(127, 127, 127)
const color_gray143 = _color(143, 143, 143)
const color_gray159 = _color(159, 159, 159)
const color_gray175 = _color(175, 175, 175)
const color_gray191 = _color(191, 191, 191)
const color_gray207 = _color(207, 207, 207)
const color_gray223 = _color(223, 223, 223)
const color_gray239 = _color(239, 239, 239)
const color_gray255 = _color(255, 255, 255)

# ── Solarized ─────────────────────────────────────────────────────────────────
# http://ethanschoonover.com/solarized

const color_solarized_gray                = _color(128, 128, 128)
const color_solarized_yellow              = _color(181, 137, 0)
const color_solarized_orange              = _color(203, 75, 22)
const color_solarized_red                 = _color(220, 50, 47)
const color_solarized_magenta             = _color(211, 54, 130)
const color_solarized_violet              = _color(108, 113, 196)
const color_solarized_blue                = _color(38, 139, 210)
const color_solarized_cyan                = _color(42, 161, 152)
const color_solarized_green               = _color(133, 153, 0)
const color_solarized_background_darker   = _color(0, 43, 54)
const color_solarized_background_dark     = _color(7, 54, 66)
const color_solarized_background_light    = _color(238, 232, 213)
const color_solarized_background_lighter  = _color(253, 246, 227)
const color_solarized_content_darker      = _color(88, 110, 117)
const color_solarized_content_dark        = _color(101, 123, 131)
const color_solarized_content_light       = _color(131, 148, 150)
const color_solarized_content_lighter     = _color(147, 161, 161)

# The pale-green completion hint: what accepting the completion would append
# after the typed (solid green) characters of an insertion — translucent
# solarized green so typed and hinted text read as one family at two weights.
const color_completion_hint               = StyleColor(133 / 255, 153 / 255, 0 / 255, 128 / 255)

# ── Zinc neutral ramp (Tailwind) ─────────────────────────────────────────────────
# Neutral palette used by the widget theme (see WidgetTheme). Plus the
# accent reds used for the "destructive" token.

const color_zinc_50  = _color(250, 250, 250)
const color_zinc_100 = _color(244, 244, 245)
const color_zinc_200 = _color(228, 228, 231)
const color_zinc_300 = _color(212, 212, 216)
const color_zinc_400 = _color(161, 161, 170)
const color_zinc_500 = _color(113, 113, 122)
const color_zinc_600 = _color(82,  82,  91)
const color_zinc_700 = _color(63,  63,  70)
const color_zinc_800 = _color(39,  39,  42)
const color_zinc_900 = _color(24,  24,  27)
const color_zinc_950 = _color(9,   9,   11)
# ── Slate neutral ramp (Tailwind) ───────────────────────────────────────────────
# A cool, slightly blue-tinted neutral used by the widget theme in place of the
# flatter zinc grey, so surfaces read as colored rather than washed-out grey.

const color_slate_50  = _color(248, 250, 252)
const color_slate_100 = _color(241, 245, 249)
const color_slate_200 = _color(226, 232, 240)
const color_slate_300 = _color(203, 213, 225)
const color_slate_400 = _color(148, 163, 184)
const color_slate_500 = _color(100, 116, 139)
const color_slate_600 = _color(71,  85,  105)
const color_slate_700 = _color(51,  65,  85)
const color_slate_800 = _color(30,  41,  59)
const color_slate_900 = _color(15,  23,  42)
const color_slate_950 = _color(2,   6,   23)

# ── Indigo accent ramp (Tailwind) ───────────────────────────────────────────────
# The widget theme's primary / accent / focus-ring color. Gives buttons, active
# states and focus rings a saturated identity instead of neutral grey.

const color_indigo_50  = _color(238, 242, 255)
const color_indigo_100 = _color(224, 231, 255)
const color_indigo_200 = _color(199, 210, 254)
const color_indigo_300 = _color(165, 180, 252)
const color_indigo_400 = _color(129, 140, 248)
const color_indigo_500 = _color(99,  102, 241)
const color_indigo_600 = _color(79,  70,  229)
const color_indigo_700 = _color(67,  56,  202)
const color_indigo_800 = _color(55,  48,  163)
const color_indigo_900 = _color(49,  46,  129)
const color_indigo_950 = _color(30,  27,  75)

const color_destructive       = _color(239, 68, 68)   # red-500
const color_destructive_fg    = _color(250, 250, 250)

# ── API ───────────────────────────────────────────────────────────────────────

"""
    is_color_equal(c1, c2) -> Bool

Return `true` if all four RGBA components of `c1` and `c2` are identical.
"""
is_color_equal(c1::StyleColor, c2::StyleColor) =
    c1.alpha == c2.alpha && c1.red == c2.red && c1.green == c2.green && c1.blue == c2.blue

"""
    is_color_transparent(color) -> Bool

Return `true` if `color` has alpha 0, as `color_transparent` has. The check is
exact: a color with a very small alpha is not transparent.
"""
is_color_transparent(color::StyleColor) = color.alpha == 0.0

"""
    is_color_equal_safe(c1, c2) -> Bool

Like `is_color_equal`, but handles `nothing`: returns `true` only when both
arguments are `nothing` or both are equal `StyleColor` values.
"""
function is_color_equal_safe(c1, c2)
    if c1 !== nothing && c2 !== nothing
        is_color_equal(c1, c2)
    else
        c1 === c2
    end
end

"""
    color_interpolate(c1, c2, ratio) -> StyleColor

Linearly interpolate between `c1` (ratio = 0) and `c2` (ratio = 1).
"""
function color_interpolate(c1::StyleColor, c2::StyleColor, ratio::Real)
    t = Float64(ratio)
    s = 1.0 - t
    make_style_color(s * c1.red   + t * c2.red,
                     s * c1.green + t * c2.green,
                     s * c1.blue  + t * c2.blue,
                     s * c1.alpha + t * c2.alpha)
end

"""
    color_lighten(color, ratio) -> StyleColor

Mix `color` toward white by `ratio` (0 = unchanged, 1 = white).
"""
color_lighten(color::StyleColor, ratio::Real) = color_interpolate(color, color_white, ratio)

"""
    color_darken(color, ratio) -> StyleColor

Mix `color` toward black by `ratio` (0 = unchanged, 1 = black).
"""
color_darken(color::StyleColor, ratio::Real) = color_interpolate(color, color_black, ratio)

"""
    compute_relative_luminance(color) -> Float64

The relative luminance of `color` as WCAG 2 defines it: from 0 for black to 1
for white. The alpha of `color` takes no part.
"""
function compute_relative_luminance(color::StyleColor)
    linear(c) = c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)^2.4
    0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
end

"""
    compute_contrast_ratio(a, b) -> Float64

The contrast ratio of the colours `a` and `b` as WCAG 2 defines it: from 1, for
two colours of the same luminance, to 21, for black and white. A text needs 4.5
against its background, a large text, a line and a ring need 3, and a text of a
high contrast scheme needs 7.
"""
function compute_contrast_ratio(a::StyleColor, b::StyleColor)
    la, lb = compute_relative_luminance(a), compute_relative_luminance(b)
    (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
end

"""
    convert_color_to_oklch(color) -> (lightness, chroma, hue)

`color` in OKLCH: its perceived lightness from 0 to 1, its chroma, and its hue
angle in degrees. The alpha of `color` takes no part.
"""
function convert_color_to_oklch(color::StyleColor)
    lightness, a, b = _convert_color_to_oklab(color)
    (lightness, hypot(a, b), mod(rad2deg(atan(b, a)), 360.0))
end

"""
    convert_oklch_to_color(lightness, chroma, hue; alpha = 1) -> StyleColor

The colour of a point of OKLCH. A point outside sRGB takes the most chroma at its
lightness and its hue that stays inside, so the hue and the lightness hold.
"""
function convert_oklch_to_color(lightness::Real, chroma::Real, hue::Real; alpha::Real = 1.0)
    a, b = cosd(hue), sind(hue)
    inside(c) = all(x -> -1e-6 <= x <= 1 + 1e-6, _convert_oklab_to_linear(lightness, c * a, c * b))
    if !inside(chroma)
        low, high = 0.0, Float64(chroma)
        for _ in 1:30
            middle = (low + high) / 2
            inside(middle) ? (low = middle) : (high = middle)
        end
        chroma = low
    end
    _convert_linear_to_color(_convert_oklab_to_linear(lightness, chroma * a, chroma * b), alpha)
end

# OKLab of a colour, and the linear sRGB of a point of OKLab (Björn Ottosson, 2020).
function _convert_color_to_oklab(color::StyleColor)
    linear(c) = c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)^2.4
    r, g, b = linear(color.red), linear(color.green), linear(color.blue)
    l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
end
function _convert_oklab_to_linear(lightness::Real, a::Real, b::Real)
    l = (lightness + 0.3963377774 * a + 0.2158037573 * b)^3
    m = (lightness - 0.1055613458 * a - 0.0638541728 * b)^3
    s = (lightness - 0.0894841775 * a - 1.2914855480 * b)^3
    (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
end
function _convert_linear_to_color(linear, alpha::Real)
    encode(c) = (c = clamp(c, 0.0, 1.0); c <= 0.0031308 ? 12.92 * c : 1.055 * c^(1 / 2.4) - 0.055)
    StyleColor(encode(linear[1]), encode(linear[2]), encode(linear[3]), Float64(alpha))
end

# The colour `fraction` of the way from `a` to `b` in OKLab, with the alpha of `a`.
function _mix_colors_in_oklab(a::StyleColor, b::StyleColor, fraction::Real)
    la, lb = _convert_color_to_oklab(a), _convert_color_to_oklab(b)
    mixed = la .+ (lb .- la) .* fraction
    _convert_linear_to_color(_convert_oklab_to_linear(mixed...), a.alpha)
end

"""
    color_lighten_selection(color, selection; default_color=color) -> StyleColor

Lighten `color` based on selection depth.
"""
function color_lighten_selection(color::StyleColor, selection; default_color::StyleColor=color)
    if selection !== nothing
        color_lighten(color, max(0, min(6, length(selection) - 4)) / 6.0)
    else
        default_color
    end
end

"""
    color_darken_selection(color, selection; default_color=color) -> StyleColor

Darken `color` based on selection depth.
"""
function color_darken_selection(color::StyleColor, selection; default_color::StyleColor=color)
    if selection !== nothing
        color_darken(color, 1.0 - max(0, min(6, length(selection) - 4)) / 6.0)
    else
        default_color
    end
end
