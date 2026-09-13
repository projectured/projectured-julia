"""
    TrueTypeModule

A minimal read-only TrueType parser and the SDL-free text measurer built on it.
Reads advance widths straight from a font's own `hmtx` table (pure Julia — no
rasterizer, no display server, no SDL), so any projection pipeline can measure
text for layout without a live backend.

This machinery is format-neutral: the PDF backend uses it for both measurement
and glyph embedding, the web backend uses `measure_truetype_text` for its
metrics, and every projection example defaults `measure=measure_truetype_text`.
It lives here next to `FontModule` (which owns `StyleFont` and the font-zoom
sizing) rather than inside the PDF backend, which is only one of its consumers.
"""
module TrueTypeModule

import ..FontModule: StyleFont, font_logical_size

export measure_truetype_text, font_ascent, font_descent, font_line_height,
       font_x_height, font_cap_height, font_glyph_bounds, font_file

# ════════════════════════════════════════════════════════════════════════
# Big-endian byte readers over a font's raw bytes (0-based offsets)
# ════════════════════════════════════════════════════════════════════════

@inline _u8(b, o)  = b[o + 1]
@inline _u16(b, o) = (UInt16(b[o + 1]) << 8) | UInt16(b[o + 2])
@inline _s16(b, o) = reinterpret(Int16, _u16(b, o))
@inline _u32(b, o) = (UInt32(b[o + 1]) << 24) | (UInt32(b[o + 2]) << 16) |
                     (UInt32(b[o + 3]) << 8)  |  UInt32(b[o + 4])
@inline _s32(b, o) = reinterpret(Int32, _u32(b, o))

# ════════════════════════════════════════════════════════════════════════
# Minimal read-only TrueType parser
# ════════════════════════════════════════════════════════════════════════

mutable struct TrueTypeFont
    bytes::Vector{UInt8}          # the whole file, for FontFile2
    units_per_em::Int
    num_glyphs::Int
    advances::Vector{Int}         # hmtx advanceWidth per glyph (font units)
    ascent::Int                   # hhea ascender (font units)
    descent::Int                  # hhea descender (font units, usually negative)
    bbox::NTuple{4,Int}           # head xMin,yMin,xMax,yMax (font units)
    cap_height::Int               # OS/2 sCapHeight if present, else ascent
    x_height::Int                 # OS/2 sxHeight if present, else half the cap height
    italic_angle::Float64
    is_fixed_pitch::Bool
    cmap_off::Int                 # byte offset of chosen cmap subtable, 0 if none
    cmap_kind::Int                # 4, 12, or 0
    loca_off::Int                 # byte offset of the loca table, 0 if none (CFF)
    glyf_off::Int                 # byte offset of the glyf table, 0 if none (CFF)
    long_loca::Bool               # head indexToLocFormat: 32-bit loca entries
    gid_cache::Dict{UInt32,UInt16}
end

const _TTF_CACHE = Dict{String,TrueTypeFont}()

"""
    font_file(path) -> String

Where the font actually is, given where it was when this package was compiled.

A `StyleFont` carries a path built from `_FONT_DIR`, which is `@__DIR__`
resolved when the package is precompiled. That is correct in a checkout and
wrong in a bundle: a PackageCompiler image bakes the string, and the checkout it
names is not on the machine the bundle is copied to. So the path is resolved
where the file is opened rather than where it is written down, and the baked one
is only the first candidate.

The order, first hit wins:

1. the path as given — a checkout, and nothing changes for it;
2. `PROJECTURED_FONT_DIR`, for a person who keeps the fonts somewhere else;
3. `share/projectured/font` beside the running executable, which is where a
   bundle carries them. `Sys.BINDIR` is that `bin` directory, and it is how the
   image finds its own depot files as well.

A path that matches nothing is answered unchanged, so the error a caller sees
names the file it asked for and not the last place this looked.
"""
function font_file(path::AbstractString)
    isfile(path) && return String(path)
    name = basename(path)
    for directory in font_search_path()
        candidate = joinpath(directory, name)
        isfile(candidate) && return candidate
    end
    String(path)
end

"""
    font_search_path() -> Vector{String}

Where [`font_file`](@ref) looks when the compiled-in path is not there. Read at
run time, never baked: an environment variable that was set at build time must
not decide where a bundle looks a year later.
"""
function font_search_path()
    directories = String[]
    from_environment = get(ENV, "PROJECTURED_FONT_DIR", "")
    isempty(from_environment) || push!(directories, from_environment)
    push!(directories,
          normpath(joinpath(Sys.BINDIR, "..", "share", "projectured", "font")))
    directories
end

# The cache is keyed by the path the caller asked for, not by the one that was
# found: two callers asking for the same font must share one parse, and where it
# came from is this function's business rather than theirs.
_load_ttf(path::AbstractString) =
    get!(() -> _parse_ttf(read(font_file(path))), _TTF_CACHE, String(path))

# Find a 4-char table tag in the SFNT directory; returns (offset, length) or (0, 0).
function _find_table(b, tag::String)
    ntables = _u16(b, 4)
    for i in 0:(ntables - 1)
        rec = 12 + 16 * i
        if Char(b[rec + 1]) == tag[1] && Char(b[rec + 2]) == tag[2] &&
           Char(b[rec + 3]) == tag[3] && Char(b[rec + 4]) == tag[4]
            return (Int(_u32(b, rec + 8)), Int(_u32(b, rec + 12)))
        end
    end
    (0, 0)
end

function _parse_ttf(b::Vector{UInt8})
    head_off, _ = _find_table(b, "head")
    maxp_off, _ = _find_table(b, "maxp")
    hhea_off, _ = _find_table(b, "hhea")
    hmtx_off, _ = _find_table(b, "hmtx")
    cmap_off, _ = _find_table(b, "cmap")
    os2_off, os2_len = _find_table(b, "OS/2")
    post_off, post_len = _find_table(b, "post")

    units = Int(_u16(b, head_off + 18))
    bbox = (Int(_s16(b, head_off + 36)), Int(_s16(b, head_off + 38)),
            Int(_s16(b, head_off + 40)), Int(_s16(b, head_off + 42)))
    num_glyphs = Int(_u16(b, maxp_off + 4))
    ascent  = Int(_s16(b, hhea_off + 4))
    descent = Int(_s16(b, hhea_off + 6))
    num_hm  = Int(_u16(b, hhea_off + 34))

    advances = Vector{Int}(undef, num_glyphs)
    last = 0
    for i in 0:(num_glyphs - 1)
        i < num_hm && (last = Int(_u16(b, hmtx_off + 4 * i)))
        advances[i + 1] = last
    end

    cmap_sub, cmap_kind = cmap_off == 0 ? (0, 0) : _select_cmap(b, cmap_off)

    cap_height = (os2_off != 0 && os2_len >= 96) ? Int(_s16(b, os2_off + 88)) : ascent
    # `sxHeight` sits two bytes before `sCapHeight` and arrived with OS/2
    # version 2, so the same length gate covers both. Math needs the x height:
    # the axis a fraction bar sits on is half of it above the baseline.
    x_height = (os2_off != 0 && os2_len >= 96) ? Int(_s16(b, os2_off + 86)) : cap_height ÷ 2
    italic_angle = (post_off != 0 && post_len >= 8) ? _s32(b, post_off + 4) / 65536 : 0.0
    is_fixed = (post_off != 0 && post_len >= 16) ? _u32(b, post_off + 12) != 0 : false

    loca_off, _ = _find_table(b, "loca")
    glyf_off, _ = _find_table(b, "glyf")
    long_loca = _u16(b, head_off + 50) == 1

    font = TrueTypeFont(b, units, num_glyphs, advances, ascent, descent, bbox,
                        cap_height, x_height, italic_angle, is_fixed, cmap_sub, cmap_kind,
                        loca_off, glyf_off, long_loca,
                        Dict{UInt32,UInt16}())

    # DejaVu — the family math is set in — still ships an OS/2 **version 1**
    # table, which carries neither field, and the fallbacks above are poor: a
    # cap height equal to the ascent overshoots by a fifth, and math would put
    # the fraction bar too low. Read the glyphs instead. The top of `x` is the
    # x height and the top of `H` is the cap height, which is what those numbers
    # mean. A CFF font has no `glyf` table and keeps the fallbacks.
    if os2_off == 0 || os2_len < 96
        _, top_x = _glyph_bounds(font, 'x')
        _, top_h = _glyph_bounds(font, 'H')
        top_h > 0 && (font.cap_height = top_h)
        font.x_height = top_x > 0 ? top_x : font.cap_height ÷ 2
    end
    font
end

"""
    _glyph_bounds(f, ch) -> (ymin, ymax)

The vertical extent of one glyph's ink, in font units, or `(0, 0)` when the font
carries no outline for it (a CFF font, or an empty glyph such as a space). The
glyph header is numberOfContours, xMin, yMin, xMax, yMax — five signed shorts —
so `yMin` sits at offset 4 and `yMax` at offset 8.
"""
function _glyph_bounds(f::TrueTypeFont, ch::AbstractChar)
    gid = Int(glyph_id(f, UInt32(ch)))
    (f.loca_off == 0 || f.glyf_off == 0 || gid == 0) && return (0, 0)
    b = f.bytes
    start = f.long_loca ? Int(_u32(b, f.loca_off + 4gid))     : 2 * Int(_u16(b, f.loca_off + 2gid))
    stop  = f.long_loca ? Int(_u32(b, f.loca_off + 4gid + 4)) : 2 * Int(_u16(b, f.loca_off + 2gid + 2))
    stop <= start && return (0, 0)   # an empty glyph, e.g. a space
    (Int(_s16(b, f.glyf_off + start + 4)), Int(_s16(b, f.glyf_off + start + 8)))
end

# Pick the most capable Unicode cmap subtable; returns (subtable_offset, format).
function _select_cmap(b, cmap_off)
    ntab = Int(_u16(b, cmap_off + 2))
    best_off = 0; best_fmt = 0; best_score = -1
    for i in 0:(ntab - 1)
        rec = cmap_off + 4 + 8 * i
        plat = _u16(b, rec); enc = _u16(b, rec + 2)
        sub = cmap_off + Int(_u32(b, rec + 4))
        fmt = Int(_u16(b, sub))
        score = if fmt == 12 && plat == 3 && enc == 10; 5
                elseif fmt == 12; 4
                elseif fmt == 4 && plat == 3 && enc == 1; 3
                elseif fmt == 4 && plat == 0; 2
                elseif fmt == 4; 1
                else; 0 end
        if score > best_score
            best_score = score; best_off = sub; best_fmt = fmt
        end
    end
    (best_off, best_fmt)
end

# cmap format 4 lookup (BMP).
function _cmap4(b, off, c::UInt32)
    c > 0xFFFF && return UInt16(0)
    seg_count = Int(_u16(b, off + 6)) ÷ 2
    end_base   = off + 14
    start_base = end_base + 2 * seg_count + 2
    delta_base = start_base + 2 * seg_count
    range_base = delta_base + 2 * seg_count
    for i in 0:(seg_count - 1)
        endc = UInt32(_u16(b, end_base + 2 * i))
        if c <= endc
            startc = UInt32(_u16(b, start_base + 2 * i))
            c < startc && return UInt16(0)
            idr = Int(_u16(b, range_base + 2 * i))
            if idr == 0
                return UInt16((c + _s16(b, delta_base + 2 * i)) & 0xFFFF)
            else
                addr = range_base + 2 * i + idr + 2 * Int(c - startc)
                g = _u16(b, addr)
                g == 0 && return UInt16(0)
                return UInt16((Int(g) + _s16(b, delta_base + 2 * i)) & 0xFFFF)
            end
        end
    end
    UInt16(0)
end

# cmap format 12 lookup (full Unicode).
function _cmap12(b, off, c::UInt32)
    ngroups = Int(_u32(b, off + 12))
    base = off + 16
    for i in 0:(ngroups - 1)
        g = base + 12 * i
        sc = _u32(b, g); ec = _u32(b, g + 4)
        if sc <= c <= ec
            return UInt16(_u32(b, g + 8) + (c - sc))
        end
    end
    UInt16(0)
end

function glyph_id(f::TrueTypeFont, c::UInt32)
    get!(f.gid_cache, c) do
        f.cmap_kind == 12 ? _cmap12(f.bytes, f.cmap_off, c) :
        f.cmap_kind == 4  ? _cmap4(f.bytes, f.cmap_off, c)  : UInt16(0)
    end
end
glyph_id(f::TrueTypeFont, c::Char) = glyph_id(f, UInt32(c))

_advance_units(f::TrueTypeFont, gid::UInt16) =
    (Int(gid) + 1) <= length(f.advances) ? f.advances[Int(gid) + 1] : f.advances[end]

advance_1000(f::TrueTypeFont, gid::UInt16) = round(Int, _advance_units(f, gid) * 1000 / f.units_per_em)

function text_width(f::TrueTypeFont, size::Real, s::AbstractString)
    total = 0
    for c in s
        total += _advance_units(f, glyph_id(f, UInt32(c)))
    end
    total * size / f.units_per_em
end

ascent_px(f::TrueTypeFont, size::Real) = f.ascent * size / f.units_per_em

"""
    measure_truetype_text(text, font::StyleFont) -> (Int, Int)

Canonical SDL-free text measurer for layout. Returns `(width, height)` in logical
pixels — both `Int`, matching `sdl_measure_text`'s contract so the same
projections can be driven with or without SDL. Reads advance widths from the
font's own TrueType `hmtx` metrics (pure Julia, no SDL/SDL_ttf), so any pipeline
can measure text without a live backend. Use it as the default `measure=` for
projection examples.

Measures at the font's *logical* (font-zoomed) size — [`font_logical_size`](@ref),
which reads the reactive `_FONT_ZOOM` cell — exactly like `sdl_measure_text`
(which rasterizes at `font_device_size` and divides back by `_DISPLAY_SCALE`).
This is what makes layout reflow with `Ctrl+Alt` font-zoom even on the SDL path.
A no-op at the default zoom (`font_logical_size == size`).
"""
measure_truetype_text(text, font::StyleFont) =
    (round(Int, text_width(_load_ttf(font.filename), font_logical_size(font), String(text))),
     font_logical_size(font))

# ════════════════════════════════════════════════════════════════════════
# Vertical metrics
# ════════════════════════════════════════════════════════════════════════
#
# A measurer answers `(width, height)`, and the two measurers answer different
# heights: `measure_truetype_text` gives the em size, `sdl_measure_text` gives
# the rasterized one. Neither says where the baseline sits, so a caller that
# aligns boxes on a baseline — a math typesetter — reads the font's own table
# instead. Every function below answers in *logical* pixels at
# `font_logical_size(font)`, so a caller inside a computed cell reflows when the
# user changes the font zoom.

_font_metric(font::StyleFont, units::Integer) =
    round(Int, units * font_logical_size(font) / _load_ttf(font.filename).units_per_em)

"""
    font_ascent(font::StyleFont) -> Int

Distance from the top of a text box down to its baseline, in logical pixels
(the `hhea` ascender). A `GraphicsText` draws from the top of its box, so its
baseline sits exactly this far below its `y`.
"""
font_ascent(font::StyleFont) = _font_metric(font, _load_ttf(font.filename).ascent)

"""
    font_descent(font::StyleFont) -> Int

Distance from the baseline down to the bottom of a text box, in logical pixels.
Positive, unlike the `hhea` descender it comes from.
"""
font_descent(font::StyleFont) = _font_metric(font, -_load_ttf(font.filename).descent)

"""
    font_line_height(font::StyleFont) -> Int

The full height of a text box: the ascent plus the descent.
"""
font_line_height(font::StyleFont) = font_ascent(font) + font_descent(font)

"""
    font_x_height(font::StyleFont) -> Int

The height of a lowercase `x`, in logical pixels. Math sets the axis — the
height a fraction bar and a large operator center on — at half of it.
"""
font_x_height(font::StyleFont) = _font_metric(font, _load_ttf(font.filename).x_height)

"""
    font_cap_height(font::StyleFont) -> Int

The height of a capital letter, in logical pixels.
"""
font_cap_height(font::StyleFont) = _font_metric(font, _load_ttf(font.filename).cap_height)

"""
    font_glyph_bounds(font::StyleFont, ch) -> (Int, Int)

How far one glyph's ink reaches below and above the baseline, in logical pixels
(below is negative). `(0, 0)` when the font carries no outline for it.

A caller that tiles a tall delimiter out of the Unicode extension pieces needs
this: the pieces stack by their ink, not by their text boxes.
"""
function font_glyph_bounds(font::StyleFont, ch::AbstractChar)
    f = _load_ttf(font.filename)
    ymin, ymax = _glyph_bounds(f, ch)
    scale = font_logical_size(font) / f.units_per_em
    (round(Int, ymin * scale), round(Int, ymax * scale))
end

end
