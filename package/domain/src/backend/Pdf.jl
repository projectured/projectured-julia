"""
    PdfBackendModule

A second, SDL-free backend over the graphics domain: it walks a `GraphicsCanvas`
tree and emits a **vector** PDF — rectangles, lines, circles become PDF path
operators and text becomes selectable `Tj` text shows. The editor's own fonts
(`font/`) are embedded as Type0 / CIDFontType2 composite fonts (`Identity-H`),
so the full Unicode range the editor uses is covered.

Entry points mirror `write_image` in `SdlBackendModule`:

- `write_pdf(canvas, filename; width, height)` — a canvas you already have.
- `write_pdf(document, projection, filename; ...)` — runs the pipeline, sizes a
  single page to the content (same two-pass fit as `write_image`), and writes.
- `GraphicsCanvasToPdfFile` — printer-only projection for pipeline composition.

The PDF writer and a minimal read-only TrueType parser are hand-rolled, so the
backend pulls in no new dependencies (no Cairo, no zlib). Content streams are
emitted uncompressed; Flate compression and font subsetting are future
optimizations. The graphics domain is top-left/y-down; PDF is bottom-left/y-up,
so a single `page_height - y` flip is applied at the moment each coordinate is
written.
"""
module PdfBackendModule

import ..GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsLine,
                         GraphicsCircle, GraphicsPolyline, GraphicsSpline,
                         GraphicsViewport, GraphicsImage, GraphicsFence,
                         _canvas_content_bounds, tessellate_spline, polyline_arrowhead
import ..GeometryModule: AffineTransform, affine_identity, affine_is_axis_aligned
import ..FontModule: StyleFont
import ..ImageModule: ImageFile
import ..ProjectionApiModule: projection_print, Projection
import ..IoMapModule: SimpleIoMap
import ..PrinterContextModule: PrinterContext
import ..ReferenceModule: EmptyReferencePath
import ..ReactiveModule: Cell

export write_pdf, GraphicsCanvasToPdfFile, pdf_measure_text, truetype_measure_text

const DEFAULT_BG = (0xfd, 0xf6, 0xe3, 0xff)
const KAPPA = 0.5522847498307936   # circle/quarter-arc Bézier constant

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
    italic_angle::Float64
    is_fixed_pitch::Bool
    cmap_off::Int                 # byte offset of chosen cmap subtable, 0 if none
    cmap_kind::Int                # 4, 12, or 0
    gid_cache::Dict{UInt32,UInt16}
end

const _TTF_CACHE = Dict{String,TrueTypeFont}()

_load_ttf(path::AbstractString) = get!(() -> _parse_ttf(read(path)), _TTF_CACHE, String(path))

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
    italic_angle = (post_off != 0 && post_len >= 8) ? _s32(b, post_off + 4) / 65536 : 0.0
    is_fixed = (post_off != 0 && post_len >= 16) ? _u32(b, post_off + 12) != 0 : false

    TrueTypeFont(b, units, num_glyphs, advances, ascent, descent, bbox,
                 cap_height, italic_angle, is_fixed, cmap_sub, cmap_kind,
                 Dict{UInt32,UInt16}())
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
    pdf_measure_text(text, font::StyleFont) -> (Int, Int)

SDL-free text measurement from the embedded font's own metrics, used to size the
page. Returns `(width, height)` in logical pixels — both `Int`, matching
`sdl_measure_text`'s contract so the same projections can be driven without SDL.
"""
pdf_measure_text(text, font::StyleFont) =
    (round(Int, text_width(_load_ttf(font.filename), font.size, String(text))), Int(font.size))

"""
    truetype_measure_text(text, font::StyleFont) -> (Int, Int)

Canonical SDL-free text measurer for layout: a neutral-named alias of
[`pdf_measure_text`]. Reads advance widths from the font's own TrueType `hmtx`
metrics (pure Julia, no SDL/SDL_ttf), so any projection pipeline can measure text
without SDL. Use this as the default `measure=` for projection examples; it
matches `sdl_measure_text`'s `(width, height)` contract.
"""
const truetype_measure_text = pdf_measure_text

# ════════════════════════════════════════════════════════════════════════
# Number / color formatting
# ════════════════════════════════════════════════════════════════════════

# Locale-independent, trailing-zero-trimmed decimal (PDF wants '.' decimals).
function n2(x::Real)
    r = round(Float64(x); digits = 3)
    r == round(r) ? string(Int(round(r))) : string(r)
end
c01(u::Integer) = n2(u / 255)

# ════════════════════════════════════════════════════════════════════════
# PDF object / xref / trailer writer
# ════════════════════════════════════════════════════════════════════════

mutable struct PdfWriter
    io::IOBuffer
    offsets::Vector{Int}    # byte offset of each object, indexed by object number
end

function PdfWriter()
    io = IOBuffer()
    write(io, "%PDF-1.7\n")
    write(io, UInt8[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])   # binary marker comment
    PdfWriter(io, Int[])
end

new_object!(w::PdfWriter) = (push!(w.offsets, 0); length(w.offsets))

function write_object!(w::PdfWriter, num::Int, body::AbstractString)
    w.offsets[num] = position(w.io)
    write(w.io, string(num), " 0 obj\n", body, "\nendobj\n")
end

function write_stream!(w::PdfWriter, num::Int, dict::AbstractString, data::Vector{UInt8})
    w.offsets[num] = position(w.io)
    write(w.io, string(num), " 0 obj\n<< ", dict, " /Length ", string(length(data)), " >>\nstream\n")
    write(w.io, data)
    write(w.io, "\nendstream\nendobj\n")
end

function finish!(w::PdfWriter, root::Int)
    n = length(w.offsets)
    xref_pos = position(w.io)
    write(w.io, "xref\n0 ", string(n + 1), "\n")
    write(w.io, "0000000000 65535 f \n")
    for i in 1:n
        write(w.io, lpad(string(w.offsets[i]), 10, '0'), " 00000 n \n")
    end
    write(w.io, "trailer\n<< /Size ", string(n + 1), " /Root ", string(root), " 0 R >>\n")
    write(w.io, "startxref\n", string(xref_pos), "\n%%EOF\n")
    take!(w.io)
end

# ════════════════════════════════════════════════════════════════════════
# Page paint context
# ════════════════════════════════════════════════════════════════════════

mutable struct FontReg
    resname::String                 # "F1"
    basefont::String                # sanitized name for /BaseFont
    ttf::TrueTypeFont
    used::Set{UInt16}               # glyph ids referenced (for W array)
    gid_to_uni::Dict{UInt16,UInt32} # for ToUnicode
end

mutable struct PageCtx
    page_height::Float64
    y0::Float64                     # global y of the current page's top (0 = single page)
    band_lo::Float64                # global y band of the current page, for culling
    band_hi::Float64
    buf::IOBuffer
    fonts::Dict{String,FontReg}     # keyed by font filename (shared across sizes/pages)
    gstates::Dict{UInt8,String}     # alpha byte -> ExtGState resource name
    images::Vector{Any}
end

PageCtx(height) = PageCtx(Float64(height), 0.0, 0.0, Float64(height), IOBuffer(),
                          Dict{String,FontReg}(), Dict{UInt8,String}(), Any[])

# Flip a global (top-left, y-down) y into the current page's PDF (bottom-left,
# y-up) space, accounting for the page's vertical band offset `y0`.
_flip(ctx::PageCtx, gy) = ctx.page_height - (gy - ctx.y0)

# True when a primitive's global vertical extent `[top, bottom]` intersects the
# current page's band, so off-page elements can be culled during pagination.
_on_page(ctx::PageCtx, top, bottom) = bottom >= ctx.band_lo && top <= ctx.band_hi

function register_font!(ctx::PageCtx, font::StyleFont)
    get!(ctx.fonts, font.filename) do
        idx = length(ctx.fonts) + 1
        base = replace(splitext(basename(font.filename))[1], r"[^A-Za-z0-9]" => "")
        isempty(base) && (base = "Font$idx")
        FontReg("F$idx", base, _load_ttf(font.filename), Set{UInt16}(), Dict{UInt16,UInt32}())
    end
end

gs_for!(ctx::PageCtx, a::UInt8) = get!(() -> "GS$(length(ctx.gstates) + 1)", ctx.gstates, a)

# ════════════════════════════════════════════════════════════════════════
# Primitive painters (mirroring SdlBackend's _render_* with a y-flip)
# ════════════════════════════════════════════════════════════════════════

# Append a rounded-rect path (PDF coords: L=left x, B=bottom y) to `io`.
function _rrect_path!(io, L, B, w, h, rtl, rtr, rbr, rbl)
    mr = min(w, h) / 2
    rtl = clamp(rtl, 0, mr); rtr = clamp(rtr, 0, mr)
    rbr = clamp(rbr, 0, mr); rbl = clamp(rbl, 0, mr)
    R = L + w; T = B + h
    p(x, y) = print(io, n2(x), " ", n2(y), " ")
    p(L + rtl, T); print(io, "m ")
    p(R - rtr, T); print(io, "l ")
    p(R - rtr + KAPPA * rtr, T); p(R, T - rtr + KAPPA * rtr); p(R, T - rtr); print(io, "c ")
    p(R, B + rbr); print(io, "l ")
    p(R, B + rbr - KAPPA * rbr); p(R - rbr + KAPPA * rbr, B); p(R - rbr, B); print(io, "c ")
    p(L + rbl, B); print(io, "l ")
    p(L + rbl - KAPPA * rbl, B); p(L, B + rbl - KAPPA * rbl); p(L, B + rbl); print(io, "c ")
    p(L, T - rtl); print(io, "l ")
    p(L, T - rtl + KAPPA * rtl); p(L + rtl - KAPPA * rtl, T); p(L + rtl, T); print(io, "c ")
    print(io, "h")
end

function _fill_rrect!(ctx, L, B, w, h, rtl, rtr, rbr, rbl, r, g, b, a)
    (a == 0 || w <= 0 || h <= 0) && return
    print(ctx.buf, "/", gs_for!(ctx, a), " gs ", c01(r), " ", c01(g), " ", c01(b), " rg ")
    _rrect_path!(ctx.buf, L, B, w, h, rtl, rtr, rbr, rbl)
    print(ctx.buf, " f\n")
end

function paint_rect!(ctx, rect, ox, oy)
    x = ox + Int(rect.x); y = oy + Int(rect.y); w = Int(rect.w); h = Int(rect.h)
    (w <= 0 || h <= 0) && return
    _on_page(ctx, y, y + h) || return
    L = x; B = _flip(ctx, y + h)
    rtl, rtr = Int(rect.radius_tl), Int(rect.radius_tr)
    rbr, rbl = Int(rect.radius_br), Int(rect.radius_bl)
    bw = Int(rect.border_width)
    if bw > 0 && rect.border_a > 0
        _fill_rrect!(ctx, L, B, w, h, rtl, rtr, rbr, rbl,
                     rect.border_r, rect.border_g, rect.border_b, rect.border_a)
        rect.a > 0 && _fill_rrect!(ctx, L + bw, B + bw, w - 2bw, h - 2bw,
                                   max(0, rtl - bw), max(0, rtr - bw),
                                   max(0, rbr - bw), max(0, rbl - bw),
                                   rect.r, rect.g, rect.b, rect.a)
    else
        _fill_rrect!(ctx, L, B, w, h, rtl, rtr, rbr, rbl, rect.r, rect.g, rect.b, rect.a)
    end
end

function _fill_disc!(ctx, cx, cy, rad, r, g, b, a)
    (rad <= 0 || a == 0) && return
    k = KAPPA * rad
    p(x, y) = print(ctx.buf, n2(x), " ", n2(y), " ")
    print(ctx.buf, "/", gs_for!(ctx, a), " gs ", c01(r), " ", c01(g), " ", c01(b), " rg ")
    p(cx + rad, cy); print(ctx.buf, "m ")
    p(cx + rad, cy + k); p(cx + k, cy + rad); p(cx, cy + rad); print(ctx.buf, "c ")
    p(cx - k, cy + rad); p(cx - rad, cy + k); p(cx - rad, cy); print(ctx.buf, "c ")
    p(cx - rad, cy - k); p(cx - k, cy - rad); p(cx, cy - rad); print(ctx.buf, "c ")
    p(cx + k, cy - rad); p(cx + rad, cy - k); p(cx + rad, cy); print(ctx.buf, "c h f\n")
end

function paint_circle!(ctx, circ, ox, oy)
    cyG = oy + Int(circ.cy); rad = Int(circ.radius); bw = Int(circ.border_width)
    _on_page(ctx, cyG - rad - bw, cyG + rad + bw) || return
    cx = ox + Int(circ.cx); cy = _flip(ctx, cyG)
    if bw > 0 && circ.border_a > 0
        _fill_disc!(ctx, cx, cy, rad, circ.border_r, circ.border_g, circ.border_b, circ.border_a)
        circ.a > 0 && _fill_disc!(ctx, cx, cy, rad - bw, circ.r, circ.g, circ.b, circ.a)
    else
        _fill_disc!(ctx, cx, cy, rad, circ.r, circ.g, circ.b, circ.a)
    end
end

function paint_line!(ctx, line, ox, oy)
    line.a == 0 && return
    wdt = max(1, Int(line.width))
    g1 = oy + Int(line.y1); g2 = oy + Int(line.y2)
    _on_page(ctx, min(g1, g2) - wdt, max(g1, g2) + wdt) || return
    x1 = ox + Int(line.x1); y1 = _flip(ctx, g1)
    x2 = ox + Int(line.x2); y2 = _flip(ctx, g2)
    print(ctx.buf, "/", gs_for!(ctx, line.a), " gs ",
          c01(line.r), " ", c01(line.g), " ", c01(line.b), " RG ",
          n2(wdt), " w 2 J ", n2(x1), " ", n2(y1), " m ", n2(x2), " ", n2(y2), " l S\n")
end

# Stroke a polyline of absolute (gx, gy) points (page-top coordinates) with
# width `wdt`, plus optional filled-triangle arrowheads. Splines tessellate to
# a polyline first, so this serves both edge primitives — native vector output.
function _paint_polyline_points!(ctx, gpts, wdt::Int, r, g, b, a,
                                 start_arrow::Bool, end_arrow::Bool, arrow_size::Int)
    (a == 0 || isempty(gpts)) && return
    ys = [p[2] for p in gpts]
    _on_page(ctx, minimum(ys) - wdt, maximum(ys) + wdt) || return
    flip = [(p[1], _flip(ctx, p[2])) for p in gpts]
    if length(flip) >= 2
        print(ctx.buf, "/", gs_for!(ctx, a), " gs ",
              c01(r), " ", c01(g), " ", c01(b), " RG ", n2(wdt), " w 1 J 1 j ")
        print(ctx.buf, n2(flip[1][1]), " ", n2(flip[1][2]), " m ")
        for i in 2:length(flip)
            print(ctx.buf, n2(flip[i][1]), " ", n2(flip[i][2]), " l ")
        end
        print(ctx.buf, "S\n")
    end
    # Arrowheads are filled triangles (computed in page-top space, then flipped).
    fill_tri(tri) = begin
        isempty(tri) && return
        ft = [(t[1], _flip(ctx, t[2])) for t in tri]
        print(ctx.buf, "/", gs_for!(ctx, a), " gs ", c01(r), " ", c01(g), " ", c01(b), " rg ")
        print(ctx.buf, n2(ft[1][1]), " ", n2(ft[1][2]), " m ",
              n2(ft[2][1]), " ", n2(ft[2][2]), " l ",
              n2(ft[3][1]), " ", n2(ft[3][2]), " l h f\n")
    end
    end_arrow   && fill_tri(polyline_arrowhead(gpts, arrow_size; at_end=true))
    start_arrow && fill_tri(polyline_arrowhead(gpts, arrow_size; at_end=false))
end

function paint_polyline!(ctx, pl, ox, oy)
    gpts = [(ox + Int(p[1]), oy + Int(p[2])) for p in pl.points]
    _paint_polyline_points!(ctx, gpts, max(1, Int(pl.width)), pl.r, pl.g, pl.b, pl.a,
                            pl.start_arrow, pl.end_arrow, Int(pl.arrow_size))
end

function paint_spline!(ctx, sp, ox, oy)
    tess = tessellate_spline(sp.points, sp.kind, sp.segments)
    gpts = [(ox + p[1], oy + p[2]) for p in tess]
    _paint_polyline_points!(ctx, gpts, max(1, Int(sp.width)), sp.r, sp.g, sp.b, sp.a,
                            sp.start_arrow, sp.end_arrow, Int(sp.arrow_size))
end

function paint_text!(ctx, t, ox, oy)
    (isempty(t.text) || t.a == 0) && return
    gy = oy + Int(t.y)
    _on_page(ctx, gy, gy + t.font.size) || return
    reg = register_font!(ctx, t.font)
    ttf = reg.ttf
    io = IOBuffer()
    for c in t.text
        cp = UInt32(c)
        gid = glyph_id(ttf, cp)
        push!(reg.used, gid)
        get!(reg.gid_to_uni, gid, cp)
        print(io, string(gid, base = 16, pad = 4))
    end
    hex = String(take!(io))
    size = t.font.size
    baseline = _flip(ctx, gy + ascent_px(ttf, size))
    print(ctx.buf, "/", gs_for!(ctx, t.a), " gs ",
          c01(t.r), " ", c01(t.g), " ", c01(t.b), " rg BT /", reg.resname, " ",
          n2(size), " Tf 1 0 0 1 ", n2(ox + Int(t.x)), " ", n2(baseline), " Tm <", hex, "> Tj ET\n")
end

function paint_image!(ctx, img, ox, oy)
    data = img.data
    data === nothing && return
    local nw, nh, buf
    if data isa Tuple && length(data) == 3 && data[1] isa Vector{UInt8}
        buf = data[1]::Vector{UInt8}; nw = Int(data[2]); nh = Int(data[3])
    elseif data isa Vector{UInt8}
        buf = data; nw = Int(img.w); nh = Int(img.h)
    else
        return   # raw SDL texture pointer: cannot read pixels back, unsupported
    end
    (nw <= 0 || nh <= 0 || length(buf) < nw * nh * 4) && return
    rgb = Vector{UInt8}(undef, nw * nh * 3)
    al = Vector{UInt8}(undef, nw * nh)
    @inbounds for i in 0:(nw * nh - 1)
        rgb[3i + 1] = buf[4i + 1]; rgb[3i + 2] = buf[4i + 2]; rgb[3i + 3] = buf[4i + 3]
        al[i + 1] = buf[4i + 4]
    end
    x = ox + Int(img.x); w = Int(img.w); h = Int(img.h); gy = oy + Int(img.y)
    _on_page(ctx, gy, gy + h) || return
    resname = "Im$(length(ctx.images) + 1)"
    push!(ctx.images, (resname = resname, nw = nw, nh = nh, rgb = rgb, alpha = al))
    yb = _flip(ctx, gy + h)
    print(ctx.buf, "q ", n2(w), " 0 0 ", n2(h), " ", n2(x), " ", n2(yb), " cm /", resname, " Do Q\n")
end

function paint_viewport!(ctx, vp, ox, oy)
    vx = ox + Int(vp.x); vy = oy + Int(vp.y); vw = Int(vp.w); vh = Int(vp.h)
    _on_page(ctx, vy, vy + vh) || return
    yb = _flip(ctx, vy + vh)
    print(ctx.buf, "q ", n2(vx), " ", n2(yb), " ", n2(vw), " ", n2(vh), " re W n\n")
    # Apply the viewport's affine transform (translate+scale subset) as a PDF `cm`
    # *after* the clip, so content is magnified within the fixed viewport box.
    # The matrix is derived in PDF (bottom-up) space from the top-down transform:
    # output = (sx·P.x + Ex, sy·P.y + Fy), accounting for the per-element y-flip.
    M = vp.transform::AffineTransform
    if M !== affine_identity && affine_is_axis_aligned(M) &&
       !(M.a == 1.0 && M.d == 1.0 && M.e == 0.0 && M.f == 0.0)
        sx, sy = M.a, M.d
        ex = vx * (1.0 - sx) + M.e
        fy = (1.0 - sy) * _flip(ctx, vy) - M.f
        print(ctx.buf, n2(sx), " 0 0 ", n2(sy), " ", n2(ex), " ", n2(fy), " cm\n")
    end
    content = vp.content
    paint_canvas!(ctx, content, vx + Int(content.x), vy + Int(content.y))
    print(ctx.buf, "Q\n")
end

function paint_elem!(ctx, elem, ox, oy)
    if elem isa GraphicsText
        paint_text!(ctx, elem, ox, oy)
    elseif elem isa GraphicsRect
        paint_rect!(ctx, elem, ox, oy)
    elseif elem isa GraphicsLine
        paint_line!(ctx, elem, ox, oy)
    elseif elem isa GraphicsPolyline
        paint_polyline!(ctx, elem, ox, oy)
    elseif elem isa GraphicsSpline
        paint_spline!(ctx, elem, ox, oy)
    elseif elem isa GraphicsCircle
        paint_circle!(ctx, elem, ox, oy)
    elseif elem isa GraphicsViewport
        paint_viewport!(ctx, elem, ox, oy)
    elseif elem isa GraphicsImage
        paint_image!(ctx, elem, ox, oy)
    elseif elem isa GraphicsCanvas
        paint_canvas!(ctx, elem, ox + Int(elem.x), oy + Int(elem.y))
    end
    # GraphicsFence and unknown types paint nothing.
end

function paint_canvas!(ctx, canvas::GraphicsCanvas, ox::Int, oy::Int)
    for elem in canvas.elements
        elem isa GraphicsFence && continue
        paint_elem!(ctx, elem, ox, oy)
    end
end

# ════════════════════════════════════════════════════════════════════════
# Font object emission
# ════════════════════════════════════════════════════════════════════════

function _utf16be_hex(cp::UInt32)
    if cp <= 0xFFFF
        string(cp, base = 16, pad = 4)
    else
        cp2 = cp - 0x10000
        hi = 0xD800 + (cp2 >> 10); lo = 0xDC00 + (cp2 & 0x3FF)
        string(hi, base = 16, pad = 4) * string(lo, base = 16, pad = 4)
    end
end

function _tounicode_cmap(reg::FontReg)
    io = IOBuffer()
    print(io, "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n")
    print(io, "/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n")
    print(io, "/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n")
    print(io, "1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n")
    entries = sort!(collect(reg.gid_to_uni); by = first)
    i = 1
    while i <= length(entries)
        chunk = entries[i:min(i + 99, length(entries))]
        print(io, length(chunk), " beginbfchar\n")
        for (gid, cp) in chunk
            print(io, "<", string(gid, base = 16, pad = 4), "> <", _utf16be_hex(cp), ">\n")
        end
        print(io, "endbfchar\n")
        i += 100
    end
    print(io, "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend")
    take!(io)
end

function _write_font!(w::PdfWriter, info)
    reg = info.reg; ttf = reg.ttf; bn = reg.basefont
    write_stream!(w, info.ff, "/Length1 $(length(ttf.bytes))", ttf.bytes)

    scale = 1000 / ttf.units_per_em
    x0, y0, x1, y1 = ttf.bbox
    flags = 32
    ttf.is_fixed_pitch && (flags |= 1)
    ttf.italic_angle != 0 && (flags |= 64)
    asc = round(Int, ttf.ascent * scale); desc = round(Int, ttf.descent * scale)
    cap = round(Int, ttf.cap_height * scale)
    write_object!(w, info.fd,
        "<< /Type /FontDescriptor /FontName /$bn /Flags $flags " *
        "/FontBBox [$(round(Int, x0*scale)) $(round(Int, y0*scale)) $(round(Int, x1*scale)) $(round(Int, y1*scale))] " *
        "/ItalicAngle $(n2(ttf.italic_angle)) /Ascent $asc /Descent $desc /CapHeight $cap " *
        "/StemV 80 /FontFile2 $(info.ff) 0 R >>")

    wio = IOBuffer(); print(wio, "[ ")
    for gid in sort!(collect(reg.used))
        print(wio, Int(gid), " [", advance_1000(ttf, gid), "] ")
    end
    print(wio, "]")
    warr = String(take!(wio))
    dw = advance_1000(ttf, UInt16(0))

    write_stream!(w, info.tu, "", _tounicode_cmap(reg))
    write_object!(w, info.cid,
        "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /$bn " *
        "/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> " *
        "/FontDescriptor $(info.fd) 0 R /CIDToGIDMap /Identity /DW $dw /W $warr >>")
    write_object!(w, info.t0,
        "<< /Type /Font /Subtype /Type0 /BaseFont /$bn /Encoding /Identity-H " *
        "/DescendantFonts [$(info.cid) 0 R] /ToUnicode $(info.tu) 0 R >>")
end

# ════════════════════════════════════════════════════════════════════════
# Public: write_pdf
# ════════════════════════════════════════════════════════════════════════

# Render `npages` content streams for `canvas`, one per vertical band of height
# `page_h` starting at global y `top`. Fonts/gstates/images accumulate into the
# single shared `ctx` so each is emitted once and referenced by every page.
function _render_pages(canvas::GraphicsCanvas, page_w::Int, page_h::Int,
                       npages::Int, top::Int, background::NTuple{4,UInt8})
    ctx = PageCtx(page_h)
    r, g, b, a = background
    contents = Vector{Vector{UInt8}}(undef, npages)
    for k in 0:(npages - 1)
        ctx.buf = IOBuffer()
        ctx.y0 = Float64(top + k * page_h)
        ctx.band_lo = Float64(top + k * page_h)
        ctx.band_hi = Float64(top + (k + 1) * page_h)
        # Clip the page to its MediaBox so an element straddling a page boundary
        # is split cleanly between consecutive pages.
        print(ctx.buf, "q 0 0 ", n2(page_w), " ", n2(page_h), " re W n\n")
        if a > 0
            print(ctx.buf, "/", gs_for!(ctx, a), " gs ", c01(r), " ", c01(g), " ", c01(b),
                  " rg 0 0 ", n2(page_w), " ", n2(page_h), " re f\n")
        end
        paint_canvas!(ctx, canvas, 0, 0)
        print(ctx.buf, "Q\n")
        contents[k + 1] = take!(ctx.buf)
    end
    (ctx, contents)
end

# Assemble the PDF file from already-rendered per-page `contents` and the shared
# `ctx` (fonts/gstates/images). Each page is `page_w × page_h` and references the
# same `/Resources`.
function _write_pdf_document(filename::AbstractString, contents::Vector{Vector{UInt8}},
                             ctx::PageCtx, page_w::Int, page_h::Int)
    w = PdfWriter()
    content_nums = Int[new_object!(w) for _ in contents]

    # Reserve object numbers up front so cross-references are known before writing.
    fontnums = Pair{String,NamedTuple}[]
    for (fn, reg) in ctx.fonts
        ff = new_object!(w); fd = new_object!(w); tu = new_object!(w)
        cid = new_object!(w); t0 = new_object!(w)
        push!(fontnums, fn => (t0 = t0, cid = cid, fd = fd, ff = ff, tu = tu, reg = reg))
    end
    gsnums = Dict{UInt8,Int}()
    for (alpha, _) in ctx.gstates
        gsnums[alpha] = new_object!(w)
    end
    imgnums = NamedTuple[]
    for im in ctx.images
        smask = new_object!(w); base = new_object!(w)
        push!(imgnums, (base = base, smask = smask, img = im))
    end
    page_nums = Int[new_object!(w) for _ in contents]
    pages_num = new_object!(w); catalog_num = new_object!(w)

    for (cn, c) in zip(content_nums, contents)
        write_stream!(w, cn, "", c)
    end
    for (_, info) in fontnums
        _write_font!(w, info)
    end
    for (alpha, _) in ctx.gstates
        av = c01(alpha)
        write_object!(w, gsnums[alpha], "<< /Type /ExtGState /ca $av /CA $av >>")
    end
    for ni in imgnums
        im = ni.img
        write_stream!(w, ni.smask,
            "/Type /XObject /Subtype /Image /Width $(im.nw) /Height $(im.nh) /ColorSpace /DeviceGray /BitsPerComponent 8",
            im.alpha)
        write_stream!(w, ni.base,
            "/Type /XObject /Subtype /Image /Width $(im.nw) /Height $(im.nh) /ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask $(ni.smask) 0 R",
            im.rgb)
    end

    res = IOBuffer(); print(res, "<< ")
    if !isempty(fontnums)
        print(res, "/Font << ")
        for (_, info) in fontnums
            print(res, "/", info.reg.resname, " ", info.t0, " 0 R ")
        end
        print(res, ">> ")
    end
    if !isempty(ctx.gstates)
        print(res, "/ExtGState << ")
        for (alpha, name) in ctx.gstates
            print(res, "/", name, " ", gsnums[alpha], " 0 R ")
        end
        print(res, ">> ")
    end
    if !isempty(imgnums)
        print(res, "/XObject << ")
        for ni in imgnums
            print(res, "/", ni.img.resname, " ", ni.base, " 0 R ")
        end
        print(res, ">> ")
    end
    print(res, ">>")
    resources = String(take!(res))

    for (pn, cn) in zip(page_nums, content_nums)
        write_object!(w, pn,
            "<< /Type /Page /Parent $pages_num 0 R /MediaBox [0 0 $(n2(page_w)) $(n2(page_h))] " *
            "/Resources $resources /Contents $cn 0 R >>")
    end
    kids = join(("$pn 0 R" for pn in page_nums), " ")
    write_object!(w, pages_num, "<< /Type /Pages /Kids [$kids] /Count $(length(page_nums)) >>")
    write_object!(w, catalog_num, "<< /Type /Catalog /Pages $pages_num 0 R >>")

    open(filename, "w") do f
        write(f, finish!(w, catalog_num))
    end
    ImageFile(filename)
end

"""
    write_pdf(canvas::GraphicsCanvas, filename::AbstractString;
              width::Integer, height::Integer, paginate::Bool = false,
              background::NTuple{4,UInt8} = (0xfd,0xf6,0xe3,0xff),
              measure = pdf_measure_text) -> ImageFile

Low-level overload. Emit `canvas` as a vector PDF where each page is
`width × height` points (1 pt == 1 logical px). Shapes become PDF paths, text
becomes selectable glyphs in embedded fonts. Returns `ImageFile(filename)`.

With `paginate = false` (default) the result is a single page; content taller
than `height` overflows and is clipped. With `paginate = true`, content taller
than `height` flows onto successive `width × height` pages, sliced into vertical
bands; `measure` is used to find the content height.
"""
function write_pdf(canvas::GraphicsCanvas, filename::AbstractString;
                   width::Integer, height::Integer, paginate::Bool = false,
                   background::NTuple{4,UInt8} = DEFAULT_BG,
                   measure = pdf_measure_text)
    ext = lowercase(splitext(filename)[2])
    ext == ".pdf" || error("write_pdf: unsupported format \"$ext\" (only .pdf is supported)")

    page_w = Int(width); page_h = Int(height)
    top = 0; npages = 1
    if paginate
        _, miny, _, maxy = _canvas_content_bounds(canvas, measure)
        top = min(0, miny)
        npages = max(1, cld(max(0, maxy - top), page_h))
    end
    ctx, contents = _render_pages(canvas, page_w, page_h, npages, top, background)
    _write_pdf_document(filename, contents, ctx, page_w, page_h)
end

"""
    write_pdf(document, projection, filename::AbstractString;
              width=nothing, height=nothing, paginate::Bool = false,
              max_width::Integer = 1200, max_height::Integer = 800,
              background::NTuple{4,UInt8} = (0xfd,0xf6,0xe3,0xff),
              measure = pdf_measure_text) -> ImageFile

Run `projection_print(projection, document)` to obtain a `GraphicsCanvas` and
write the vector PDF. Throws if the projection output is not a `GraphicsCanvas`.

With `paginate = false` (default), a single page is sized to the content (same
two-pass content-fit as `write_image`: omitted axes hug the content, capped at
`max_*`).

With `paginate = true`, the content flows across multiple pages: `height` is the
page height (default `792`, US-Letter at 72 dpi) and the layout is produced with
its vertical axis unbounded, then sliced into `height`-tall bands. `width` is the
page width — given (the projection reflows to it) or the content's natural width
capped at `max_width`. `max_height` is ignored in this mode.

```julia
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
)
write_pdf(doc, proj, "snapshot.pdf")                       # one content-fit page
write_pdf(doc, proj, "book.pdf"; paginate=true, height=792) # multi-page
```
"""
function write_pdf(document, projection, filename::AbstractString;
                   width::Union{Nothing,Integer} = nothing,
                   height::Union{Nothing,Integer} = nothing,
                   paginate::Bool = false,
                   max_width::Integer = 1200,
                   max_height::Integer = 800,
                   background::NTuple{4,UInt8} = DEFAULT_BG,
                   measure = pdf_measure_text)
    print_canvas = (aw, ah) -> begin
        ctx = PrinterContext(EmptyReferencePath(), aw, ah, Dict{Symbol,Any}())
        iomap = projection_print(projection, nothing, document, ctx)
        canvas = iomap.output
        canvas isa GraphicsCanvas ||
            error("write_pdf: projection output is $(typeof(canvas)), expected GraphicsCanvas")
        canvas
    end

    if paginate
        # Lay out at the page width (vertical axis unbounded), then slice into
        # `page_h`-tall pages.
        page_h = height === nothing ? 792 : Int(height)
        aw = width === nothing ? nothing : Cell(Int(width))
        canvas = print_canvas(aw, nothing)
        _, _, nw, _ = _canvas_content_bounds(canvas, measure)
        if width === nothing && nw > max_width
            canvas = print_canvas(Cell(Int(max_width)), nothing)
            _, _, nw, _ = _canvas_content_bounds(canvas, measure)
        end
        page_w = width === nothing ? clamp(nw, 1, Int(max_width)) : Int(width)
        return write_pdf(canvas, filename; width = page_w, height = page_h,
                         paginate = true, background = background, measure = measure)
    end

    aw = width  === nothing ? nothing : Cell(Int(width))
    ah = height === nothing ? nothing : Cell(Int(height))
    canvas = print_canvas(aw, ah)
    _, _, nw, nh = _canvas_content_bounds(canvas, measure)

    cap_w = width  === nothing && nw > max_width
    cap_h = height === nothing && nh > max_height
    if cap_w || cap_h
        aw2 = cap_w ? Cell(Int(max_width))  : aw
        ah2 = cap_h ? Cell(Int(max_height)) : ah
        canvas = print_canvas(aw2, ah2)
        _, _, nw, nh = _canvas_content_bounds(canvas, measure)
    end

    out_w = width  === nothing ? clamp(nw, 1, Int(max_width))  : Int(width)
    out_h = height === nothing ? clamp(nh, 1, Int(max_height)) : Int(height)

    write_pdf(canvas, filename; width = out_w, height = out_h, background = background)
end

# ════════════════════════════════════════════════════════════════════════
# Printer-only projection
# ════════════════════════════════════════════════════════════════════════

"""
    GraphicsCanvasToPdfFile(filename; width=800, height=600,
                            background=(0xfd,0xf6,0xe3,0xff), paginate=false)

Printer-only projection. On `projection_print` it renders the input
`GraphicsCanvas` to a vector PDF and saves to `filename`. With `paginate=true`,
content taller than `height` flows across multiple `width × height` pages. The
`output` of the returned `SimpleIoMap` is an `ImageFile`. Has no reader (subtypes
`Projection`, so the default reference mappers return `nothing`).
"""
struct GraphicsCanvasToPdfFile <: Projection
    filename::String
    width::Int
    height::Int
    background::NTuple{4,UInt8}
    paginate::Bool
end

function GraphicsCanvasToPdfFile(filename::AbstractString;
                                 width::Integer = 800, height::Integer = 600,
                                 background = DEFAULT_BG, paginate::Bool = false)
    GraphicsCanvasToPdfFile(String(filename), Int(width), Int(height),
                            NTuple{4,UInt8}(background), paginate)
end

function projection_print(p::GraphicsCanvasToPdfFile, recursion, canvas::GraphicsCanvas, ctx)
    output = write_pdf(canvas, p.filename;
                       width = p.width, height = p.height,
                       background = p.background, paginate = p.paginate)
    SimpleIoMap(p, canvas, output)
end

end # module
