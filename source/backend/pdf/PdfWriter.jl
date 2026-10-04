# Fragment of `PdfModule` — the PDF backend: the page it writes, the
# graphics operators it emits, and the Bézier arithmetic behind the curves.

const DEFAULT_BG = (0xf9, 0xf9, 0xfb, 0xff)
const KAPPA = 0.5522847498307936   # circle/quarter-arc Bézier constant

# ════════════════════════════════════════════════════════════════════════
# Number / color formatting
# ════════════════════════════════════════════════════════════════════════

# Locale-independent, trailing-zero-trimmed decimal (PDF wants '.' decimals).
function n2(x::Real)
    r = round(Float64(x); digits = 3)
    r == round(r) ? string(Int(round(r))) : string(r)
end
c01(u::Integer) = n2(u / 255)

# Convert a domain `StyleColor` (Float64 RGBA in [0,1]) to device bytes, so the
# existing byte-based painter helpers (and the UInt8-keyed ExtGState alpha dedup)
# are reused unchanged.
_rgba8(c::StyleColor) = (UInt8(round(c.red * 255)), UInt8(round(c.green * 255)),
                         UInt8(round(c.blue * 255)), UInt8(round(c.alpha * 255)))

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

function write_stream!(w::PdfWriter, num::Int; dict::AbstractString, data::Vector{UInt8})
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

mutable struct FontRegistration
    resname::String                 # "F1"
    basefont::String                # sanitized name for /BaseFont
    ttf::TrueTypeFont
    used::Set{UInt16}               # glyph ids referenced (for W array)
    gid_to_uni::Dict{UInt16,UInt32} # for ToUnicode
end

mutable struct PageContext
    page_height::Float64
    y0::Float64                     # global y of the current page's top (0 = single page)
    band_lo::Float64                # global y band of the current page, for culling
    band_hi::Float64
    buf::IOBuffer
    fonts::Dict{String,FontRegistration}     # keyed by font filename (shared across sizes/pages)
    gstates::Dict{UInt8,String}     # alpha byte -> ExtGState resource name
    images::Vector{Any}
end

PageContext(height) = PageContext(Float64(height), 0.0, 0.0, Float64(height), IOBuffer(),
                          Dict{String,FontRegistration}(), Dict{UInt8,String}(), Any[])

# Flip a global (top-left, y-down) y into the current page's PDF (bottom-left,
# y-up) space, accounting for the page's vertical band offset `y0`.
_flip(ctx::PageContext, gy) = ctx.page_height - (gy - ctx.y0)

# True when a primitive's global vertical extent `[top, bottom]` intersects the
# current page's band, so off-page elements can be culled during pagination.
_on_page(ctx::PageContext, top, bottom) = bottom >= ctx.band_lo && top <= ctx.band_hi

function register_font!(ctx::PageContext, path::AbstractString)
    get!(ctx.fonts, String(path)) do
        idx = length(ctx.fonts) + 1
        base = replace(splitext(basename(path))[1], r"[^A-Za-z0-9]" => "")
        isempty(base) && (base = "Font$idx")
        FontRegistration("F$idx", base, load_truetype_font(path), Set{UInt16}(), Dict{UInt16,UInt32}())
    end
end

# The writer embeds a font as `/FontFile2`, which holds TrueType outlines: a
# `glyf` table. A font with CFF outlines has no `glyf` table.
_is_embeddable_font(ttf::TrueTypeFont) = ttf.glyf_off != 0

# The registration of the font that draws `character` in a text set in `font`. It is the font that `find_glyph_font_file` names, which is the font
# that `FontFileMeasure` measures the character in. A fallback font that
# the writer can not embed is skipped, and the character is drawn in the font
# of the text.
function _register_glyph_font!(ctx::PageContext, primary::FontRegistration,
                               font::StyleFont, character::UInt32)
    character <= 0xFFFF && has_font_glyph(primary.ttf, character) && return primary
    file = find_glyph_font_file(font, character)
    (file === nothing || file == compute_font_path(font)) && return primary
    _is_embeddable_font(load_truetype_font(file)) || return primary
    register_font!(ctx, file)
end

# Split `text` into runs of consecutive characters that one font draws. Each run
# is the registration of its font and its glyph identifiers. A presentation
# selector has no width, and the measurer skips it, so it is dropped.
function _split_font_runs!(ctx::PageContext, text::AbstractString, font::StyleFont)
    primary = register_font!(ctx, compute_font_path(font))
    runs = Tuple{FontRegistration,Vector{UInt16}}[]
    for c in text
        character = UInt32(c)
        is_presentation_selector(character) && continue
        reg = _register_glyph_font!(ctx, primary, font, character)
        gid = get_glyph_id(reg.ttf, character)
        push!(reg.used, gid)
        get!(reg.gid_to_uni, gid, character)
        (isempty(runs) || runs[end][1] !== reg) && push!(runs, (reg, UInt16[]))
        push!(runs[end][2], gid)
    end
    runs
end

# The operand of a `TJ` for one run: its glyphs in hexadecimal, and between two
# glyphs that kern the adjustment, in thousandths of the font size. A positive
# adjustment moves the next glyph left, so a pair that moves together (a
# negative kerning) is written as a positive number.
function _make_kerned_glyphs(reg::FontRegistration, glyphs::Vector{UInt16})
    io = IOBuffer()
    print(io, "[<")
    for (index, glyph) in enumerate(glyphs)
        if index > 1
            kerning = get_kerning(reg.ttf, glyphs[index - 1], glyph)
            kerning == 0 || print(io, "> ", n2(-kerning * 1000 / reg.ttf.units_per_em), " <")
        end
        print(io, string(glyph, base = 16, pad = 4))
    end
    print(io, ">]")
    String(take!(io))
end

gs_for!(ctx::PageContext, a::UInt8) = get!(() -> "GS$(length(ctx.gstates) + 1)", ctx.gstates, a)

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

# Stroke the border of a rounded rect as a ring: the same path inset by half the
# border width, stroked at that width, so the interior stays unpainted — the
# rectangular equivalent of `_stroke_ring!`.
function _stroke_rrect!(ctx, L, B, w, h, rtl, rtr, rbr, rbl, bw, r, g, b, a)
    (a == 0 || bw <= 0 || w <= bw || h <= bw) && return
    hb = bw / 2
    print(ctx.buf, "/", gs_for!(ctx, a), " gs ", c01(r), " ", c01(g), " ", c01(b), " RG ",
          n2(bw), " w [] 0 d ")
    _rrect_path!(ctx.buf, L + hb, B + hb, w - bw, h - bw,
                 max(0, rtl - hb), max(0, rtr - hb),
                 max(0, rbr - hb), max(0, rbl - hb))
    print(ctx.buf, " S\n")
end

function paint_rect!(ctx, rect, ox, oy)
    x = ox + Int(rect.x); y = oy + Int(rect.y); w = Int(rect.w); h = Int(rect.h)
    (w <= 0 || h <= 0) && return
    _on_page(ctx, y, y + h) || return
    L = x; B = _flip(ctx, y + h)
    rtl, rtr = Int(rect.radius_tl), Int(rect.radius_tr)
    rbr, rbl = Int(rect.radius_br), Int(rect.radius_bl)
    bw = Int(rect.border_width)
    if bw > 0 && rect.border_color.alpha > 0
        if rect.color.alpha >= 1
            # Opaque fill: the border-colored shape with the fill inset over it.
            _fill_rrect!(ctx, L, B, w, h, rtl, rtr, rbr, rbl, _rgba8(rect.border_color)...)
            _fill_rrect!(ctx, L + bw, B + bw, w - 2bw, h - 2bw,
                         max(0, rtl - bw), max(0, rtr - bw),
                         max(0, rbr - bw), max(0, rbl - bw),
                         _rgba8(rect.color)...)
        else
            # Translucent (or absent) fill: the border has to be a true ring, or
            # the fill would composite against the border color instead of
            # against whatever is behind the rect.
            rect.color.alpha > 0 && _fill_rrect!(ctx, L + bw, B + bw, w - 2bw, h - 2bw,
                                       max(0, rtl - bw), max(0, rtr - bw),
                                       max(0, rbr - bw), max(0, rbl - bw),
                                       _rgba8(rect.color)...)
            _stroke_rrect!(ctx, L, B, w, h, rtl, rtr, rbr, rbl, bw,
                           _rgba8(rect.border_color)...)
        end
    else
        _fill_rrect!(ctx, L, B, w, h, rtl, rtr, rbr, rbl, _rgba8(rect.color)...)
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

# Stroke a ring (annulus) whose outer edge sits at `rad`, with border width `bw`.
# Stroking the Bézier circle centred at radius `rad - bw/2` leaves the centre
# unpainted — the native vector equivalent of SDL's `_stroke_ring!`.
function _stroke_ring!(ctx, cx, cy, rad, bw, r, g, b, a)
    (rad <= 0 || a == 0 || bw <= 0) && return
    rm = rad - bw / 2
    rm <= 0 && (rm = rad / 2)
    k = KAPPA * rm
    p(x, y) = print(ctx.buf, n2(x), " ", n2(y), " ")
    print(ctx.buf, "/", gs_for!(ctx, a), " gs ", c01(r), " ", c01(g), " ", c01(b), " RG ",
          n2(bw), " w [] 0 d ")
    p(cx + rm, cy); print(ctx.buf, "m ")
    p(cx + rm, cy + k); p(cx + k, cy + rm); p(cx, cy + rm); print(ctx.buf, "c ")
    p(cx - k, cy + rm); p(cx - rm, cy + k); p(cx - rm, cy); print(ctx.buf, "c ")
    p(cx - rm, cy - k); p(cx - k, cy - rm); p(cx, cy - rm); print(ctx.buf, "c ")
    p(cx + k, cy - rm); p(cx + rm, cy - k); p(cx + rm, cy); print(ctx.buf, "c h S\n")
end

function paint_circle!(ctx, circ, ox, oy)
    cyG = oy + Int(circ.cy); rad = Int(circ.radius); bw = Int(circ.border_width)
    _on_page(ctx, cyG - rad - bw, cyG + rad + bw) || return
    cx = ox + Int(circ.cx); cy = _flip(ctx, cyG)
    if bw > 0 && circ.border_color.alpha > 0
        if circ.color.alpha > 0
            _fill_disc!(ctx, cx, cy, rad, _rgba8(circ.border_color)...)
            _fill_disc!(ctx, cx, cy, rad - bw, _rgba8(circ.color)...)
        else
            # transparent fill: a true hollow ring, centre unpainted
            _stroke_ring!(ctx, cx, cy, rad, bw, _rgba8(circ.border_color)...)
        end
    else
        _fill_disc!(ctx, cx, cy, rad, _rgba8(circ.color)...)
    end
end

function paint_line!(ctx, line, ox, oy)
    line.color.alpha == 0 && return
    lr, lg, lb, la = _rgba8(line.color)
    wdt = max(1, Int(line.width))
    g1 = oy + Int(line.y1); g2 = oy + Int(line.y2)
    _on_page(ctx, min(g1, g2) - wdt, max(g1, g2) + wdt) || return
    x1 = ox + Int(line.x1); y1 = _flip(ctx, g1)
    x2 = ox + Int(line.x2); y2 = _flip(ctx, g2)
    # Dash array via the PDF `d` operator; always emitted (`[] 0 d` = solid) so a
    # dashed line never leaks its pattern onto a later solid stroke.
    dash = line.dash
    dashop = dash === nothing ? "[] 0 d " : string("[", Int(dash[1]), " ", Int(dash[2]), "] 0 d ")
    print(ctx.buf, "/", gs_for!(ctx, la), " gs ",
          c01(lr), " ", c01(lg), " ", c01(lb), " RG ",
          n2(wdt), " w 2 J ", dashop, n2(x1), " ", n2(y1), " m ", n2(x2), " ", n2(y2), " l S\n")
end

# Stroke a polyline of absolute (gx, gy) points (page-top coordinates) with
# width `wdt`, plus optional filled-triangle arrowheads and an optional
# (on, off) dash pattern. Splines tessellate to a polyline first, so this
# serves both edge primitives — native vector output.
function _paint_polyline_points!(ctx, gpts, wdt::Int, r, g, b, a,
                                 start_arrow::Bool, end_arrow::Bool, arrow_size::Int,
                                 dash=nothing)
    (a == 0 || isempty(gpts)) && return
    ys = [p[2] for p in gpts]
    _on_page(ctx, minimum(ys) - wdt, maximum(ys) + wdt) || return
    flip = [(p[1], _flip(ctx, p[2])) for p in gpts]
    if length(flip) >= 2
        # Dash array via the PDF `d` operator; always emitted (`[] 0 d` = solid) so
        # a dashed stroke never leaks its pattern onto a later solid stroke. The
        # path is a single `m`/`l ` chain stroked once, so the dash phase runs
        # continuously across vertices with no extra bookkeeping (unlike Sdl,
        # which draws each segment as its own quad).
        dashop = dash === nothing ? "[] 0 d " : string("[", Int(dash[1]), " ", Int(dash[2]), "] 0 d ")
        print(ctx.buf, "/", gs_for!(ctx, a), " gs ",
              c01(r), " ", c01(g), " ", c01(b), " RG ", n2(wdt), " w 1 J 1 j ", dashop)
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
    end_arrow   && fill_tri(build_polyline_arrowhead(gpts, arrow_size; at_end=true))
    start_arrow && fill_tri(build_polyline_arrowhead(gpts, arrow_size; at_end=false))
end

function paint_polyline!(ctx, pl, ox, oy)
    gpts = [(ox + Int(p[1]), oy + Int(p[2])) for p in pl.points]
    _paint_polyline_points!(ctx, gpts, max(1, Int(pl.width)), _rgba8(pl.color)...,
                            pl.start_arrow, pl.end_arrow, Int(pl.arrow_size), pl.dash)
end

# Fill a closed polygon, then stroke its outline when a border is asked for.
# The nonzero winding rule of the `f` operator fills a concave outline (a star
# marker) directly, so no triangulation is needed in vector output.
function paint_polygon!(ctx, pg, ox, oy)
    gpts = [(ox + Int(p[1]), oy + Int(p[2])) for p in pg.points]
    length(gpts) < 3 && return
    bw = Int(pg.border_width)
    bordered = bw > 0 && pg.border_color.alpha > 0
    filled = pg.color.alpha > 0
    (filled || bordered) || return
    ys = [p[2] for p in gpts]
    _on_page(ctx, minimum(ys) - bw, maximum(ys) + bw) || return
    flip = [(p[1], _flip(ctx, p[2])) for p in gpts]
    emit_path() = begin
        print(ctx.buf, n2(flip[1][1]), " ", n2(flip[1][2]), " m ")
        for i in 2:length(flip)
            print(ctx.buf, n2(flip[i][1]), " ", n2(flip[i][2]), " l ")
        end
        print(ctx.buf, "h")
    end
    if filled
        fr, fg, fb, fa = _rgba8(pg.color)
        print(ctx.buf, "/", gs_for!(ctx, fa), " gs ", c01(fr), " ", c01(fg), " ", c01(fb), " rg ")
        emit_path()
        print(ctx.buf, " f\n")
    end
    if bordered
        br, bg, bb, ba = _rgba8(pg.border_color)
        # A separate stroke pass rather than `B`, so fill and border keep their
        # own ExtGState alpha.
        print(ctx.buf, "/", gs_for!(ctx, ba), " gs ", c01(br), " ", c01(bg), " ", c01(bb), " RG ",
              n2(bw), " w 1 j [] 0 d ")
        emit_path()
        print(ctx.buf, " S\n")
    end
end

function paint_spline!(ctx, sp, ox, oy)
    tess = tessellate_spline(sp.points, sp.kind, sp.segments)
    gpts = [(ox + p[1], oy + p[2]) for p in tess]
    _paint_polyline_points!(ctx, gpts, max(1, Int(sp.width)), _rgba8(sp.color)...,
                            sp.start_arrow, sp.end_arrow, Int(sp.arrow_size), sp.dash)
end

# The text is written at the size that the layout measured it at, the size of
# its font, which a theme scales with the font scale. Each run of one font is a `Tf` and a `TJ` in one text
# object. A `TJ` moves the text position by the advances of its glyphs and by the
# kerning between them, so a run starts where the run before it ends. Every run
# sits on the baseline of the text, the ascent of its box (`compute_text_extent`)
# below its `y`.
function paint_text!(ctx, t, ox, oy)
    (isempty(t.text) || t.color.alpha == 0) && return
    tr, tg, tb, ta = _rgba8(t.color)
    gy = oy + Int(t.y)
    size = font_logical_size(t.font)
    _, ascent, descent = compute_text_extent(t.text, t.font)
    _on_page(ctx, gy, gy + ascent + descent) || return
    runs = _split_font_runs!(ctx, t.text, t.font)
    isempty(runs) && return
    baseline = _flip(ctx, gy + ascent)
    print(ctx.buf, "/", gs_for!(ctx, ta), " gs ",
          c01(tr), " ", c01(tg), " ", c01(tb), " rg BT 1 0 0 1 ",
          n2(ox + Int(t.x)), " ", n2(baseline), " Tm")
    for (reg, glyphs) in runs
        print(ctx.buf, " /", reg.resname, " ", n2(size), " Tf ", _make_kerned_glyphs(reg, glyphs), " TJ")
    end
    print(ctx.buf, " ET\n")
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
    if M !== affine_identity && is_affine_axis_aligned(M) &&
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
    elseif elem isa GraphicsPolygon
        paint_polygon!(ctx, elem, ox, oy)
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

function _tounicode_cmap(reg::FontRegistration)
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
    write_stream!(w, info.ff; dict = "/Length1 $(length(ttf.bytes))", data = ttf.bytes)

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
        print(wio, Int(gid), " [", get_glyph_advance_1000(ttf, gid), "] ")
    end
    print(wio, "]")
    warr = String(take!(wio))
    dw = get_glyph_advance_1000(ttf, UInt16(0))

    write_stream!(w, info.tu; dict = "", data = _tounicode_cmap(reg))
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
    ctx = PageContext(page_h)
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
                             ctx::PageContext, page_w::Int, page_h::Int)
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
        write_stream!(w, cn; dict = "", data = c)
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
        write_stream!(w, ni.smask;
                      dict = "/Type /XObject /Subtype /Image /Width $(im.nw) /Height $(im.nh) /ColorSpace /DeviceGray /BitsPerComponent 8",
                      data = im.alpha)
        write_stream!(w, ni.base;
                      dict = "/Type /XObject /Subtype /Image /Width $(im.nw) /Height $(im.nh) /ColorSpace /DeviceRGB /BitsPerComponent 8 /SMask $(ni.smask) 0 R",
                      data = im.rgb)
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
              background::NTuple{4,UInt8} = (0xf9,0xf9,0xfb,0xff)) -> ImageFile

Low-level overload. Emit `canvas` as a vector PDF where each page is
`width × height` points (1 pt == 1 logical px). Shapes become PDF paths, text
becomes selectable glyphs in embedded fonts. Returns `ImageFile(filename)`.

With `paginate = false` (default) the result is a single page; content taller
than `height` overflows and is clipped. With `paginate = true`, content taller
than `height` flows onto successive `width × height` pages, sliced into vertical
bands at the height of the content, as the font files measure its texts.
"""
function write_pdf(canvas::GraphicsCanvas, filename::AbstractString;
                   width::Integer, height::Integer, paginate::Bool = false,
                   background::NTuple{4,UInt8} = DEFAULT_BG)
    ext = lowercase(splitext(filename)[2])
    ext == ".pdf" || error("write_pdf: unsupported format \"$ext\" (only .pdf is supported)")

    page_w = Int(width); page_h = Int(height)
    top = 0; npages = 1
    if paginate
        _, miny, _, maxy = get_canvas_content_bounds(canvas)
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
              background::NTuple{4,UInt8} = (0xf9,0xf9,0xfb,0xff)) -> ImageFile

Run `print_document(projection, document)` to obtain a `GraphicsCanvas` and
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
proj = ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure = FontFileMeasure()),
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
                   background::NTuple{4,UInt8} = DEFAULT_BG)
    print_canvas = (aw, ah) -> begin
        ctx = PrinterContext(EmptyReference(), aw, ah, Dict{Symbol,Any}())
        iomap = print_document(projection, nothing, document, ctx)
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
        _, _, nw, _ = get_canvas_content_bounds(canvas)
        if width === nothing && nw > max_width
            canvas = print_canvas(Cell(Int(max_width)), nothing)
            _, _, nw, _ = get_canvas_content_bounds(canvas)
        end
        page_w = width === nothing ? clamp(nw, 1, Int(max_width)) : Int(width)
        return write_pdf(canvas, filename; width = page_w, height = page_h,
                         paginate = true, background = background)
    end

    aw = width  === nothing ? nothing : Cell(Int(width))
    ah = height === nothing ? nothing : Cell(Int(height))
    canvas = print_canvas(aw, ah)
    _, _, nw, nh = get_canvas_content_bounds(canvas)

    cap_w = width  === nothing && nw > max_width
    cap_h = height === nothing && nh > max_height
    if cap_w || cap_h
        aw2 = cap_w ? Cell(Int(max_width))  : aw
        ah2 = cap_h ? Cell(Int(max_height)) : ah
        canvas = print_canvas(aw2, ah2)
        _, _, nw, nh = get_canvas_content_bounds(canvas)
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
                            background=(0xf9,0xf9,0xfb,0xff), paginate=false)

Printer-only projection. On `print_document` it renders the input
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

function print_document(p::GraphicsCanvasToPdfFile, recursion, canvas::GraphicsCanvas, ctx)
    output = write_pdf(canvas, p.filename;
                       width = p.width, height = p.height,
                       background = p.background, paginate = p.paginate)
    SimpleIoMap(p, canvas, output)
end
