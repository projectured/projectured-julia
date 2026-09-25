# Fragment of `StyleModule`.
#
# The measure of text for layout. A layout asks a `TextMeasure` for the box of a
# string, the metrics of a font, and the x of each character boundary; it never
# asks a backend. Every value is a real number in logical pixels, and nothing
# here rounds: a layout rounds a position once, where it makes one.

"""
    TextMeasure

What a layout measures text with. It answers three questions:

- [`measure_string`](@ref): the box of a string in a font;
- [`get_font_metrics`](@ref): the vertical metrics of a font, with no text;
- [`compute_caret_offsets`](@ref): the x of each character boundary of a string.

[`FontFileMeasure`](@ref) answers from the font files, as every backend draws.
[`FixedMeasure`](@ref) answers fixed numbers, for a test.
"""
abstract type TextMeasure end

"""
    FontMetrics(ascent, descent, line_gap)

The vertical metrics of a font in logical pixels: the `ascent` from the
baseline up to the top of its box, the `descent` from the baseline down to the
bottom (positive), and the `line_gap`, the extra line distance the font asks for.
A line of this font alone is `ascent + descent + line_gap` from the next one at
single spacing.
"""
struct FontMetrics
    ascent::Float64
    descent::Float64
    line_gap::Float64
end

"""
    StringBox(width, ascent, descent, line_gap)

The box of a string as it is drawn, in logical pixels: its advance `width`,
kerning included, and the largest `ascent`, `descent` and `line_gap` of the
fonts that draw its glyphs. The baseline of the string is `ascent` below the top
of the box.
"""
struct StringBox
    width::Float64
    ascent::Float64
    descent::Float64
    line_gap::Float64
end

"""
    measure_string(measure::TextMeasure, text, font::StyleFont) -> StringBox

The box of `text` set in `font`. An empty text has no width and the metrics of
`font`.
"""
function measure_string end

"""
    get_font_metrics(measure::TextMeasure, font::StyleFont) -> FontMetrics

The vertical metrics of `font` with no text: what a blank line and a caret on
an empty place are as high as.
"""
function get_font_metrics end

"""
    compute_caret_offsets(measure::TextMeasure, text, font::StyleFont) -> Vector{Float64}

The x of each character boundary of `text` set in `font`: `length(text) + 1`
values, the first 0 and the last the width of the string. Each is the pen
position where the next character starts, so it includes the kerning between
that character and the one before it. The width of a prefix does not: the caret
after "A" in "AV" stands where "V" starts, after the kerning of the pair.
"""
function compute_caret_offsets end

# ── The font files ──────────────────────────────────────────────────────────

"""
    FontFileMeasure()

The measure that reads the font files, as every backend draws them: the `hmtx`
advance of each glyph, the `kern` pairs between two glyphs of one font, the
fallback font of each character the font lacks ([`find_glyph_font_file`](@ref)),
and the vertical metrics by FreeType's rule ([`get_vertical_metrics`](@ref)).
A presentation selector (U+FE0E, U+FE0F) has no width, as the renderers draw it.
The size is the logical size of the font, so a font zoom changes it.
"""
struct FontFileMeasure <: TextMeasure end

# The metrics of the font file at `path`, at `size` logical pixels.
function _get_file_metrics(path::AbstractString, size::Real)
    file = load_truetype_font(path)
    ascender, descender, line_gap = get_vertical_metrics(file)
    scale = size / file.units_per_em
    FontMetrics(ascender * scale, -descender * scale, line_gap * scale)
end

get_font_metrics(::FontFileMeasure, font::StyleFont) =
    _get_file_metrics(font.filename, font_logical_size(font))

# Each character of `text` with the file of the font that draws it: the font
# itself, or the fallback font `find_glyph_font_file` names. A presentation
# selector is skipped: it draws nothing.
function _each_drawn_character(text, font::StyleFont)
    path = font.filename
    primary = load_truetype_font(path)
    drawn = Tuple{Int,String}[]
    for (index, character) in enumerate(String(text))
        code = UInt32(character)
        is_presentation_selector(code) && continue
        file = path
        if get_glyph_id(primary, code) == 0 || code > 0xFFFF
            fallback = find_glyph_font_file(path, code)
            fallback === nothing || (file = fallback)
        end
        push!(drawn, (index, file))
    end
    drawn
end

# The pen position before each character of `text`, and each character that
# draws with the file that draws it (`_each_drawn_character`). `offsets[i]` is
# where character `i` starts; `offsets[end]` is the width. The kerning of a pair
# moves the second character, and only two characters that one font draws kern.
function _compute_pen_positions(text, font::StyleFont)
    size = font_logical_size(font)
    characters = collect(String(text))
    offsets = zeros(Float64, length(characters) + 1)
    drawn = _each_drawn_character(text, font)
    by_index = Dict(index => file for (index, file) in drawn)
    pen = 0.0
    previous = nothing
    for index in eachindex(characters)
        offsets[index] = pen
        file = get(by_index, index, nothing)
        if file === nothing
            continue
        end
        truetype = load_truetype_font(file)
        glyph = get_glyph_id(truetype, UInt32(characters[index]))
        scale = size / truetype.units_per_em
        if previous !== nothing && previous[1] == file
            kerning = get_kerning(truetype, previous[2], glyph) * scale
            pen += kerning
            offsets[index] = pen
        end
        pen += _advance_units(truetype, glyph) * scale
        previous = (file, glyph)
    end
    offsets[end] = pen
    offsets, drawn
end

function measure_string(::FontFileMeasure, text, font::StyleFont)
    offsets, drawn = _compute_pen_positions(text, font)
    files = isempty(drawn) ? [font.filename] : unique(file for (_, file) in drawn)
    size = font_logical_size(font)
    ascent = descent = line_gap = 0.0
    for file in files
        metrics = _get_file_metrics(file, size)
        ascent = max(ascent, metrics.ascent)
        descent = max(descent, metrics.descent)
        line_gap = max(line_gap, metrics.line_gap)
    end
    StringBox(offsets[end], ascent, descent, line_gap)
end

compute_caret_offsets(::FontFileMeasure, text, font::StyleFont) =
    first(_compute_pen_positions(text, font))

"""
    PlacedGlyph(character, file, x)

A character of a text where [`FontFileMeasure`](@ref) places it: the `file` of
the font that draws it, and the pen position `x` where it starts, in logical
pixels from the start of the text.
"""
struct PlacedGlyph
    character::Char
    file::String
    x::Float64
end

"""
    compute_placed_glyphs(text, font::StyleFont) -> Vector{PlacedGlyph}

Each character of `text` that draws, in the font file and at the pen position
where [`FontFileMeasure`](@ref) measures it. A backend that draws each glyph at
its `x` in the font of its `file` draws the text as wide as the layout measured
it, whatever the backend does to the advance of a glyph. A presentation selector
draws nothing and is not in the answer.
"""
function compute_placed_glyphs(text, font::StyleFont)
    characters = collect(String(text))
    offsets, drawn = _compute_pen_positions(text, font)
    [PlacedGlyph(characters[index], file, offsets[index]) for (index, file) in drawn]
end

# ── Fixed numbers, for a test ───────────────────────────────────────────────

"""
    FixedMeasure(advance, ascent, descent, line_gap; fonts = Dict())

A measure of fixed numbers, for a test: every character is `advance` wide,
there is no kerning, and every font has the metrics `ascent`, `descent` and
`line_gap`, except a font that `fonts` gives its own `FontMetrics`. So a test of
mixed fonts gives two fonts different metrics.

# Example

    measure = FixedMeasure(8, 12, 4, 0;
                           fonts = Dict(font_ubuntu_monospace_regular_20 => FontMetrics(10, 3, 0)))
"""
struct FixedMeasure <: TextMeasure
    advance::Float64
    metrics::FontMetrics
    fonts::Dict{Tuple{String,Int},FontMetrics}
end

FixedMeasure(advance::Real, ascent::Real, descent::Real, line_gap::Real;
             fonts::AbstractDict = Dict{StyleFont,FontMetrics}()) =
    FixedMeasure(Float64(advance), FontMetrics(ascent, descent, line_gap),
                 Dict{Tuple{String,Int},FontMetrics}((font.filename, font.size) => metrics
                                                      for (font, metrics) in fonts))

get_font_metrics(measure::FixedMeasure, font::StyleFont) =
    get(measure.fonts, (font.filename, font.size), measure.metrics)

function measure_string(measure::FixedMeasure, text, font::StyleFont)
    metrics = get_font_metrics(measure, font)
    StringBox(length(text) * measure.advance, metrics.ascent, metrics.descent, metrics.line_gap)
end

compute_caret_offsets(measure::FixedMeasure, text, font::StyleFont) =
    [index * measure.advance for index in 0:length(text)]

# ── The integer box of a drawn text ─────────────────────────────────────────

"""
    compute_text_extent([measure::TextMeasure,] text, font::StyleFont) -> (width, ascent, descent)

The box of `text` in `font` in whole logical pixels, as `measure` measures it:
the width rounded, and the ascent and the descent rounded up, so the box never
ends inside the ink. The baseline of the text is `ascent` below its `y`.

With no `measure`, the box is the one that a `GraphicsText` draws, from the font
files ([`FontFileMeasure`](@ref)). Every backend draws the baseline there, and a
layout that places a text by its baseline sets `y` to the baseline minus this
ascent.
"""
compute_text_extent(measure::TextMeasure, text, font::StyleFont) =
    _round_extent(measure_string(measure, text, font))

compute_text_extent(text, font::StyleFont) = compute_text_extent(FontFileMeasure(), text, font)

_round_extent(box::StringBox) = (round(Int, box.width), _round_up(box.ascent), _round_up(box.descent))

# Up to the next whole pixel, without taking a float's last bit for a pixel:
# 18.000000000000004 is 18.
_round_up(value::Real) = ceil(Int, round(value; digits = 6))
