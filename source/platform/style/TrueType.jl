# Fragment of `StyleModule`.
#
# A minimal read-only TrueType parser. It reads the tables of a font file that a
# layout and a backend need (pure Julia — no rasterizer, no display server, no
# SDL): the advance widths of `hmtx`, the pairs of `kern`, and the vertical
# metrics of `hhea` and OS/2. `FontFileMeasure` (TextMeasure.jl) measures text
# from them, and the PDF backend embeds glyphs with them. It lives here next to
# `StyleModule`, which owns `StyleFont` and the font-zoom sizing.
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
    line_gap::Int                 # hhea lineGap (font units)
    typo_ascent::Int              # OS/2 sTypoAscender, 0 without an OS/2 table
    typo_descent::Int             # OS/2 sTypoDescender (usually negative)
    typo_line_gap::Int            # OS/2 sTypoLineGap
    win_ascent::Int               # OS/2 usWinAscent
    win_descent::Int              # OS/2 usWinDescent (positive)
    use_typo_metrics::Bool        # OS/2 fsSelection bit 7, USE_TYPO_METRICS
    bbox::NTuple{4,Int}           # head xMin,yMin,xMax,yMax (font units)
    cap_height::Int               # OS/2 sCapHeight if present, else ascent
    x_height::Int                 # OS/2 sxHeight if present, else half the cap height
    italic_angle::Float64
    is_fixed_pitch::Bool
    weight_class::Int             # OS/2 usWeightClass, 100 to 900; 400 without an OS/2 table
    is_italic::Bool               # OS/2 fsSelection bit 0 or 9; else a nonzero italic angle
    cmap_off::Int                 # byte offset of chosen cmap subtable, 0 if none
    cmap_kind::Int                # 4, 12, or 0
    loca_off::Int                 # byte offset of the loca table, 0 if none (CFF)
    glyf_off::Int                 # byte offset of the glyf table, 0 if none (CFF)
    long_loca::Bool               # head indexToLocFormat: 32-bit loca entries
    gid_cache::Dict{UInt32,UInt16}
    kern_pairs::Dict{UInt32,Int}  # kern table: (left glyph << 16) | right glyph => font units
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
load_truetype_font(path::AbstractString) =
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
    ascent   = Int(_s16(b, hhea_off + 4))
    descent  = Int(_s16(b, hhea_off + 6))
    line_gap = Int(_s16(b, hhea_off + 8))
    num_hm   = Int(_u16(b, hhea_off + 34))

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
    # The typographic and the Windows metrics arrived with the first OS/2 table,
    # at 78 bytes; `fsSelection` is in every version.
    has_os2 = os2_off != 0 && os2_len >= 78
    typo_ascent   = has_os2 ? Int(_s16(b, os2_off + 68)) : 0
    typo_descent  = has_os2 ? Int(_s16(b, os2_off + 70)) : 0
    typo_line_gap = has_os2 ? Int(_s16(b, os2_off + 72)) : 0
    win_ascent    = has_os2 ? Int(_u16(b, os2_off + 74)) : 0
    win_descent   = has_os2 ? Int(_u16(b, os2_off + 76)) : 0
    use_typo      = has_os2 && (_u16(b, os2_off + 62) & 0x0080) != 0
    italic_angle = (post_off != 0 && post_len >= 8) ? _s32(b, post_off + 4) / 65536 : 0.0
    is_fixed = (post_off != 0 && post_len >= 16) ? _u32(b, post_off + 12) != 0 : false
    # `usWeightClass` and `fsSelection` are in every version of the OS/2 table.
    # A face declares its slant with the ITALIC bit or the OBLIQUE bit.
    weight_class = os2_off != 0 ? Int(_u16(b, os2_off + 4)) : 400
    is_italic = os2_off != 0 ? (_u16(b, os2_off + 62) & 0x0201) != 0 : italic_angle != 0

    loca_off, _ = _find_table(b, "loca")
    glyf_off, _ = _find_table(b, "glyf")
    long_loca = _u16(b, head_off + 50) == 1

    font = TrueTypeFont(b, units, num_glyphs, advances, ascent, descent, line_gap,
                        typo_ascent, typo_descent, typo_line_gap, win_ascent, win_descent,
                        use_typo, bbox,
                        cap_height, x_height, italic_angle, is_fixed, weight_class, is_italic,
                        cmap_sub, cmap_kind,
                        loca_off, glyf_off, long_loca,
                        Dict{UInt32,UInt16}(), _parse_kern(b))

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
    gid = Int(get_glyph_id(f, UInt32(ch)))
    (f.loca_off == 0 || f.glyf_off == 0 || gid == 0) && return (0, 0)
    b = f.bytes
    start = f.long_loca ? Int(_u32(b, f.loca_off + 4gid))     : 2 * Int(_u16(b, f.loca_off + 2gid))
    stop  = f.long_loca ? Int(_u32(b, f.loca_off + 4gid + 4)) : 2 * Int(_u16(b, f.loca_off + 2gid + 2))
    stop <= start && return (0, 0)   # an empty glyph, e.g. a space
    (Int(_s16(b, f.glyf_off + start + 4)), Int(_s16(b, f.glyf_off + start + 8)))
end

# The pairs of the `kern` table, keyed by `(left glyph << 16) | right glyph`, in
# font units. It reads the Microsoft table (version 0) and its format-0
# subtables of horizontal kerning, as FreeType does, and FreeType is what draws
# the text in SDL: a subtable of minimum values or of cross-stream kerning is
# skipped, and one with the override bit replaces the value of a pair where
# another adds to it. A font with no such table has no pairs.
function _parse_kern(b::Vector{UInt8})
    pairs = Dict{UInt32,Int}()
    kern_off, kern_len = _find_table(b, "kern")
    (kern_off == 0 || kern_len < 4 || _u16(b, kern_off) != 0) && return pairs
    at = kern_off + 4
    for _ in 1:Int(_u16(b, kern_off + 2))
        at + 6 > kern_off + kern_len && break
        length = Int(_u16(b, at + 2))
        coverage = _u16(b, at + 4)
        is_horizontal = (coverage & 0x0001) != 0
        is_minimum = (coverage & 0x0002) != 0
        is_cross_stream = (coverage & 0x0004) != 0
        overrides = (coverage & 0x0008) != 0
        if coverage >> 8 == 0 && is_horizontal && !is_minimum && !is_cross_stream
            count = Int(_u16(b, at + 6))
            for index in 0:(count - 1)
                entry = at + 14 + 6 * index
                key = (UInt32(_u16(b, entry)) << 16) | UInt32(_u16(b, entry + 2))
                value = Int(_s16(b, entry + 4))
                pairs[key] = overrides ? value : get(pairs, key, 0) + value
            end
        end
        length == 0 && break
        at += length
    end
    pairs
end

"""
    get_kerning(font::TrueTypeFont, left::UInt16, right::UInt16) -> Int

The kerning between two glyphs of `font`, in font units: negative when the pair
moves together. 0 when the `kern` table has no entry for the pair.
"""
get_kerning(font::TrueTypeFont, left::UInt16, right::UInt16) =
    get(font.kern_pairs, (UInt32(left) << 16) | UInt32(right), 0)

"""
    get_vertical_metrics(font::TrueTypeFont) -> (ascender, descender, line_gap)

The vertical metrics of `font` in font units, by the rule FreeType applies, so
they are the numbers SDL_ttf draws with: the OS/2 typographic metrics when the
font sets USE_TYPO_METRICS, else the `hhea` metrics; and when the `hhea` ascender
and descender are both 0, the typographic metrics if they are set, else the
Windows metrics with no line gap. The descender is negative, as in the tables.
"""
function get_vertical_metrics(font::TrueTypeFont)
    font.use_typo_metrics &&
        return (font.typo_ascent, font.typo_descent, font.typo_line_gap)
    (font.ascent != 0 || font.descent != 0) &&
        return (font.ascent, font.descent, font.line_gap)
    (font.typo_ascent != 0 || font.typo_descent != 0) &&
        return (font.typo_ascent, font.typo_descent, font.typo_line_gap)
    (font.win_ascent, -font.win_descent, 0)
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

function get_glyph_id(f::TrueTypeFont, c::UInt32)
    get!(f.gid_cache, c) do
        f.cmap_kind == 12 ? _cmap12(f.bytes, f.cmap_off, c) :
        f.cmap_kind == 4  ? _cmap4(f.bytes, f.cmap_off, c)  : UInt16(0)
    end
end
get_glyph_id(f::TrueTypeFont, c::Char) = get_glyph_id(f, UInt32(c))

_advance_units(f::TrueTypeFont, gid::UInt16) =
    (Int(gid) + 1) <= length(f.advances) ? f.advances[Int(gid) + 1] : f.advances[end]

get_glyph_advance_1000(f::TrueTypeFont, gid::UInt16) = round(Int, _advance_units(f, gid) * 1000 / f.units_per_em)

function measure_text_width(f::TrueTypeFont, size::Real, s::AbstractString)
    total = 0
    for c in s
        total += _advance_units(f, get_glyph_id(f, UInt32(c)))
    end
    total * size / f.units_per_em
end

get_ascent_pixels(f::TrueTypeFont, size::Real) = f.ascent * size / f.units_per_em

# ════════════════════════════════════════════════════════════════════════
# Fallback fonts
# ════════════════════════════════════════════════════════════════════════
#
# A font draws only the characters it carries. For a character it lacks, a
# renderer draws with the font `find_glyph_font_file` names, and
# `FontFileMeasure` measures with the same font, so a line is drawn as wide as it
# was measured.

const _EMOJI_FONT_FILE       = joinpath(_FONT_DIR, "NotoEmoji-Regular.ttf")
const _DEJAVU_MONO_FILE      = joinpath(_FONT_DIR, "DejaVuSansMono.ttf")
const _DEJAVU_MONO_BOLD_FILE = joinpath(_FONT_DIR, "DejaVuSansMono-Bold.ttf")

const _FALLBACK_FONT_FILES = [_DEJAVU_MONO_FILE, _EMOJI_FONT_FILE]
# DejaVu Sans Mono Bold lacks some glyphs of the regular face, so the regular
# face follows it.
const _BOLD_FALLBACK_FONT_FILES = [_DEJAVU_MONO_BOLD_FILE, _DEJAVU_MONO_FILE, _EMOJI_FONT_FILE]

"""
    get_fallback_font_files(path) -> Vector{String}

The fonts that a text set in the font at `path` falls back to, in order: DejaVu
Sans Mono, which carries arrows, check marks, stars, geometric shapes and box
drawing, and then Noto Emoji. A bold font, whose file name ends in `-B` or
`-Bold`, takes the bold face of DejaVu first.
"""
get_fallback_font_files(path::AbstractString) =
    occursin(r"-B(old)?(I|Italic|Oblique)?\.[ot]tf$", basename(path)) ?
        _BOLD_FALLBACK_FONT_FILES : _FALLBACK_FONT_FILES

const _FONT_AVAILABLE = Dict{String,Bool}()

_is_font_available(path::AbstractString) =
    get!(() -> isfile(font_file(path)), _FONT_AVAILABLE, String(path))

"""
    has_font_glyph(font::TrueTypeFont, character) -> Bool

Whether `font` carries a glyph for `character`.
"""
has_font_glyph(font::TrueTypeFont, character::UInt32) = get_glyph_id(font, character) != 0

"""
    find_glyph_font_file(path, character) -> String or nothing

The file of the font that draws `character` in a text set in the font at `path`:
that font when it carries the character, else the first font of
[`get_fallback_font_files`](@ref) that does. `nothing` when no font carries it,
and the caller then draws the character in its own font, which draws the
missing-glyph box. A fallback file that is not installed is skipped.

A character outside the basic plane is nearly always a pictograph, and Noto
Emoji draws it even when the font carries one: DejaVu Sans does, in a style of
its own.
"""
function find_glyph_font_file(path::AbstractString, character::UInt32)
    character > 0xFFFF && _has_file_glyph(_EMOJI_FONT_FILE, character) && return _EMOJI_FONT_FILE
    has_font_glyph(load_truetype_font(path), character) && return String(path)
    for fallback in get_fallback_font_files(path)
        _has_file_glyph(fallback, character) && return fallback
    end
    nothing
end

_has_file_glyph(path::AbstractString, character::UInt32) =
    _is_font_available(path) && has_font_glyph(load_truetype_font(path), character)

"""
    is_presentation_selector(character) -> Bool

Whether `character` is a variation selector that asks for text or emoji
presentation (U+FE0E, U+FE0F). It has no width, and a renderer that does no
shaping drops it, so a measurer drops it too.
"""
is_presentation_selector(character::UInt32) = character == 0xFE0E || character == 0xFE0F

# ════════════════════════════════════════════════════════════════════════
# Vertical metrics
# ════════════════════════════════════════════════════════════════════════
#
# The metrics of a font in whole logical pixels, for a caller that places boxes
# by their baseline, a math typesetter. The ascent and the descent are those of
# the box of a text in the font alone (`compute_text_extent`), so a box placed by
# them sits where a backend draws it. Every function below answers at
# `font_logical_size(font)`, the size of `font` itself: a font already scaled for
# its appearance carries its own size, so these functions need no cell of their
# own to follow a change of the font scale.

_font_metric(font::StyleFont, units::Integer) =
    round(Int, units * font_logical_size(font) / load_truetype_font(font.filename).units_per_em)

"""
    font_ascent(font::StyleFont) -> Int

The ascent of the box of a text in `font` alone, in whole logical pixels: the
ascender by FreeType's rule, rounded up. A backend draws the baseline of such a
text this far below its `y`. A glyph that a fallback font draws can make the box
of a text taller: `compute_text_extent` gives the box of a given text.
"""
font_ascent(font::StyleFont) = compute_text_extent("", font)[2]

"""
    font_descent(font::StyleFont) -> Int

The descent of the box of a text in `font` alone, from the baseline down, in
whole logical pixels: the descender by FreeType's rule, rounded up and positive.
"""
font_descent(font::StyleFont) = compute_text_extent("", font)[3]

"""
    font_line_height(font::StyleFont) -> Int

The height of the box of a text in `font` alone: its ascent and its descent. A
line of such a text also has the line gap of the font (`compute_line_box`).
"""
font_line_height(font::StyleFont) = font_ascent(font) + font_descent(font)

"""
    font_x_height(font::StyleFont) -> Int

The height of a lowercase `x`, in logical pixels. Math sets the axis — the
height a fraction bar and a large operator center on — at half of it.
"""
font_x_height(font::StyleFont) = _font_metric(font, load_truetype_font(font.filename).x_height)

"""
    font_cap_height(font::StyleFont) -> Int

The height of a capital letter, in logical pixels.
"""
font_cap_height(font::StyleFont) = _font_metric(font, load_truetype_font(font.filename).cap_height)

"""
    font_glyph_bounds(font::StyleFont, ch) -> (Int, Int)

How far one glyph's ink reaches below and above the baseline, in logical pixels
(below is negative). `(0, 0)` when the font carries no outline for it.

A caller that tiles a tall delimiter out of the Unicode extension pieces needs
this: the pieces stack by their ink, not by their text boxes.
"""
function font_glyph_bounds(font::StyleFont, ch::AbstractChar)
    f = load_truetype_font(font.filename)
    ymin, ymax = _glyph_bounds(f, ch)
    scale = font_logical_size(font) / f.units_per_em
    (round(Int, ymin * scale), round(Int, ymax * scale))
end
