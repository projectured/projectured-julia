"""
    TextToGraphicsModule

Text → Graphics projection. Pure layout pass: arranges already-wrapped spans
left-to-right and breaks the line at a `TextLine` element, at an explicit
`TextNewline` element, or at an embedded `\\n` character. Word wrapping itself
lives in `WordWrapping`, inserted upstream of `TextToGraphics` in the pipeline.

A coordinate table in the IoMap records the character range and pixel
position of each emitted segment. The reader uses it for keyboard navigation
(arrow keys, home/end) and to translate downstream mouse-click selections
into character positions.

Text measurement is provided via the mandatory `measure(text, font) -> (w, h)`
function parameter. Backends inject a real measurer (e.g. `sdl_measure_text`)
at construction time.
"""
module TextToGraphicsModule

import ..CellModule: Cell, set_cell_function!, set_cell_value!
import ..CollectionModule: CellVector, ListNode, CollectionDocument
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextBlock, TextLine, TextString, TextNewline, TextGraphics, TextDocument,
                     SpanPath, _flat_cursor_coord, _flat_base, _flat_caret_ref, _is_structural_selection,
                     ReplaceTextRangeOperation, _lower_text_range
import ..TextRangeReferenceStepModule: TextRangeReferenceStep
import ..GraphicsModule: GraphicsText, GraphicsRect, GraphicsImage, GraphicsCanvas, layout_none, layout_vertical
import ..ImageModule: ImageDocument
import ..FontModule: StyleFont, font_logical_size
import ..ColorModule: StyleColor, color_black
import ..ReferenceModule: Reference, ConcreteReference, ElementReferenceStep, PositionReferenceStep, RangeReferenceStep, EmptyReference, FieldReferenceStep, head, tail
import ..TextSpanReferenceStepModule: TextSpanReferenceStep
import ..PointReferenceStepModule: PointReferenceStep
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..GestureBindingModule: read_gesture
import ..EventModule: KeyDown, KeyPress
import ..EventModule: MousePress
import ..EventPatternModule: var"@event_case"
import ..IoMapApiModule: IoMap
export TextToGraphics, TextToGraphicsIoMap

"""
    SegCoord(span_path, char_start, char_end, x, y, font, text, width, height)

One entry per emitted text segment. `span_path` is the segment's span as an index
path into the input `TextBlock` (a `SpanPath`): `[i]` for a top-level span, `[i, j]`
for span `j` of the `TextLine` at element `i`. `char_start`/`char_end` are
0-based offsets local to that span (exclusive end). `(x, y)` are pixel
coordinates of the segment's top-left. `width`/`height` are the segment's
pixel box; for an inline image span (`TextGraphics` — empty `text`, range
`[0, 1)`) they carry the image size so hit-testing splits on the real
left/right halves, the cursor sits at `x + width`, and the clickable y-band
covers the whole image.
"""
struct SegCoord
    span_path::SpanPath
    char_start::Int
    char_end::Int
    x::Int
    y::Int
    font::StyleFont
    text::String
    width::Int
    height::Int
end

"""
    TextToGraphicsIoMap

IoMap for `TextToGraphics`. `char_to_coord` holds one `SegCoord` per emitted
text segment with character range, pixel position, font, and text.
"""
struct TextToGraphicsIoMap <: IoMap
    projection::Any
    input::TextBlock
    output::GraphicsCanvas
    char_to_coord::Cell  # Cell{Vector{SegCoord}}
    highlight_offset::Cell  # Cell{Int} — number of highlight rects prepended before text segments
end

# ── Projection struct ──────────────────────────────────────────────────

struct TextToGraphics <: Projection
    start_x::Int
    start_y::Int
    measure::Function   # (text, font) -> (width, height)
end

function TextToGraphics(; start_x::Int=0, start_y::Int=0, measure::Function)
    TextToGraphics(start_x, start_y, measure)
end

function map_reference_forward(::TextToGraphics, iomap, reference)
    return nothing
end

function map_reference_backward(::TextToGraphics, iomap, reference)
    return nothing
end

function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, op::ReplaceSelectionOperation)
    return _translate_click(p, iomap, op.path)
end

# KeyPress producer: the character-insert mapping is geometry-free, so it lives
# on the Text domain (`read_gesture(::TextBlock, ::KeyPress)` in `TextModule`).
# Delegate to it; the operation it produces (a `ReplaceStringRangeOperation`
# against `.elements[i].content[range]`) flows back through the chain unchanged.
# Text-domain gesture, with any flat edit op lowered to the structural single-span
# form over the input block (== the outermost text stage's output), so the existing
# `ReplaceStringRangeOperation` chain carries it up. A declined (cross-span) edit
# lowers to `nothing`, so the caller lets the gesture propagate.
function _gesture_op(iomap::TextToGraphicsIoMap, evt)
    op = read_gesture(iomap.input, evt)
    op isa ReplaceTextRangeOperation ? _lower_text_range(iomap.input, op) : op
end

function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::KeyPress)
    return _gesture_op(iomap, evt)
end

# A `ReplaceSelectionOperation` selecting the flat caret at `char` in the span at
# `span_path`, or `nothing` when the span has no flat base. The graphics layer
# resolves clicks/line-motion to a `(span, char)` hit; this converts it to the
# canonical flat selection (`_flat_base + char`).
function _flat_hit_op(text::TextBlock, span_path::SpanPath, char::Int)
    base = _flat_base(text, span_path)
    base === nothing ? nothing : ReplaceSelectionOperation(_flat_caret_ref(base + char))
end

# Raw MousePress directly on the canvas (no GraphicsCanvasToGraphicsImage
# step above us). Translate to a text-domain selection by picking the
# segment that owns the click and the character offset within it.
function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::MousePress)
    evt.button === :left || return nothing
    coord_map = iomap.char_to_coord[]
    isempty(coord_map) && return nothing
    sc = _hit_segment(coord_map, evt.x, evt.y)
    sc === nothing && return nothing
    # A click always becomes a plain character cursor; whole-element promotion
    # (Alt+click) is decided in SyntaxToText, where the tree is in hand.
    char_pos = _char_position_at_x(sc, evt.x, p.measure)
    return _flat_hit_op(iomap.input, sc.span_path, char_pos)
end

function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt)
    evt isa KeyDown || return nothing

    # Geometry-INDEPENDENT gestures (character cursor left/right, Ctrl+Home/End,
    # Backspace/Delete, the Ctrl+. fold recognition, and the tree-gesture decline
    # rules) live on the Text domain. Delegate to `read_gesture`, which reads
    # only the span structure and the flat-character selection — no layout.
    op = _gesture_op(iomap, evt)
    op === nothing || return op

    # `read_gesture` returned nothing: either it *declined* a tree gesture
    # (Alt+arrow, plain arrow while structural, Tab) so an outer syntax layer can
    # own it, or it is a key this layer must resolve with pixel geometry (plain
    # up/down, plain Home/End). Re-apply the decline guards so the geometry arms
    # below never mis-handle a declined tree gesture as line motion. (`Ctrl+.` is
    # already consumed by `read_gesture`, so it cannot reach here.)
    declined = @event_case evt begin
        when(KeyDown(k), evt.modifiers.alt && k in (:up, :down, :left, :right, :home)) => :decline
        when(KeyDown(k), k in (:up, :down, :left, :right) &&
                         _is_structural_selection(iomap.input.selection)) => :decline
        KeyDown(:tab) => :decline
    end
    declined === nothing || return nothing

    styled = iomap.input
    _has_text_span(styled) || return nothing

    current = _flat_cursor_coord(styled)
    current === nothing && return nothing

    @event_case evt begin
        when(KeyDown(k), k === :home || k === :end) => begin
            coord_map = iomap.char_to_coord[]
            isempty(coord_map) && return nothing
            seg_idx = findfirst(sc -> sc.span_path == current.span && sc.char_start <= current.char <= sc.char_end, coord_map)
            seg_idx === nothing && return nothing
            current_y = coord_map[seg_idx].y
            line_segs = filter(sc -> sc.y == current_y, coord_map)
            sc = k === :home ? line_segs[1] : line_segs[end]
            new_char = k === :home ? sc.char_start : sc.char_end
            return _flat_hit_op(styled, sc.span_path, new_char)
        end
        when(KeyDown(k), k === :up || k === :down) => begin
            coord_map = iomap.char_to_coord[]
            isempty(coord_map) && return nothing
            seg_idx = findfirst(sc -> sc.span_path == current.span && sc.char_start <= current.char <= sc.char_end, coord_map)
            seg_idx === nothing && return nothing
            cur_sc   = coord_map[seg_idx]
            cursor_x = _seg_cursor_x(cur_sc, current.char, p.measure)
            current_y = cur_sc.y
            target_segs = if k === :up
                ys = [sc.y for sc in coord_map if sc.y < current_y]
                isempty(ys) ? SegCoord[] : filter(sc -> sc.y == maximum(ys), coord_map)
            else
                ys = [sc.y for sc in coord_map if sc.y > current_y]
                isempty(ys) ? SegCoord[] : filter(sc -> sc.y == minimum(ys), coord_map)
            end
            isempty(target_segs) && return nothing
            best_sc   = target_segs[1]
            best_pos  = best_sc.char_start
            best_dist = typemax(Int)
            for sc in target_segs
                pos  = _char_position_at_x(sc, cursor_x, p.measure)
                xpos = _seg_cursor_x(sc, pos, p.measure)
                d    = abs(xpos - cursor_x)
                if d < best_dist
                    best_dist = d
                    best_pos  = pos
                    best_sc   = sc
                end
            end
            return _flat_hit_op(styled, best_sc.span_path, best_pos)
        end
    end
    # A KeyDown this layer neither edits nor resolves with geometry (e.g. Return,
    # Escape, Insert while a text caret exists) is declined, NOT passed on as a raw
    # gesture: a reader must yield an Operation or `nothing`, never an event. Putting
    # the gesture in the operation slot marks the change "already produced" and stops
    # the enclosing chain from re-offering it to the domain — which is why committing
    # an insertion (Enter) or aborting it (Escape) silently did nothing once the buffer
    # had a cursor. Returning `nothing` lets it propagate inward to the domain reader.
    return nothing
end

# ── Layout engine (wrap-free) ──────────────────────────────────────────

"""
    print_document(p::TextToGraphics, styled::TextBlock) -> Cell{Vector{GraphicsText}}

Lay an already-wrapped `TextBlock` out into reactive `GraphicsText` primitives.
Lines advance left-to-right; the line breaks come from `TextNewline` elements
and from `\\n` characters embedded in `TextString` content. The wrap itself —
splitting at word boundaries when text would overflow — is the job of
`WordWrapping` upstream.

The returned `Cell` holds a `Vector{GraphicsText}`. Its thunk reads every
relevant cell in the `TextBlock`, so any value or structural change
invalidates the layout; recomputation happens only when the `Cell` is read.
"""
function print_document(p::TextToGraphics, recursion, styled::TextBlock, ctx)
    # ListNode path: lazy paragraph-level mapping
    if styled.elements isa ListNode
        return _print_listnode(p, styled, ctx)
    end
    # Per-line decomposition (printer locality — dimension B). The output is a
    # vertical stack of one reactive sub-canvas per visual line, where lines are
    # split at `TextNewline` *elements* — a structural boundary that never reads
    # span content. Each line's sub-canvas lays out only that line's spans, so a
    # content edit invalidates just the edited line's cells (and, via the y-offset
    # height chain, the lines below it). The backend dirty-rectangle pass then
    # repaints only the edited line instead of the whole block.
    #
    # The crucial property is that the *list* of line sub-canvases depends only on
    # the line grouping (structure), so a content edit leaves it up to date and the
    # dirty walk descends into it to find just the edited line stale. Editing the
    # last line moves nothing below it, so its dirty rect is tight.
    #
    # Embedded '\n' inside a span (e.g. SyntaxToText emits `TextString("\n")`
    # separators and no `TextNewline` elements) collapses into one big line group,
    # which stays whole-block dirty exactly as before — no regression for those
    # pipelines (already non-local via SyntaxToText flattening).
    #
    # The caret/highlight stay a single selection-driven `overlay`, laid out in
    # absolute coordinates over the whole stack, so a pure caret move still
    # invalidates only the two overlay rects (dimension A): the spans never read
    # the selection. `overlay` re-runs the same `_layout_group` pass the lines do,
    # so the caret lands exactly where the glyph it sits against was drawn.
    #
    # The block's prevailing font sizes a blank line that has no font of its own
    # (an empty `TextLine`). It lives in its own cell because only such a line
    # reads it: a font edit still re-lays out just the lines that render glyphs.
    block_font = Cell(() -> _block_font(styled))
    overlay = Cell(() -> _layout_overlay(p, styled, styled.selection, block_font))

    # Persistent overlay elements. Their geometry cells read the selection-
    # dependent `overlay`; a zero width hides them when inactive (the renderer
    # skips a zero-width rect, and the bounds machinery ignores it).
    cursor_rect = GraphicsRect(0, 0, 0, 0, color_black)
    set_cell_function!(getfield(cursor_rect, :x), () -> (g = overlay[].cursor; g === nothing ? Int32(0) : Int32(g[1])))
    set_cell_function!(getfield(cursor_rect, :y), () -> (g = overlay[].cursor; g === nothing ? Int32(0) : Int32(g[2])))
    set_cell_function!(getfield(cursor_rect, :w), () -> overlay[].cursor === nothing ? Int32(0) : Int32(2))
    set_cell_function!(getfield(cursor_rect, :h), () -> (g = overlay[].cursor; g === nothing ? Int32(0) : Int32(max(g[3], 1))))

    # A structural selection hugs its content per visual row (see `_compute_span_rows`),
    # so the highlight is a *vector* of rects, not one box. They live in their own
    # sub-canvas (a single top-canvas slot, below), each a persistent `GraphicsRect`
    # keyed by row index and reused across re-layouts; the k-th reads `overlay`'s k-th
    # rect (a zero width hides a rect whose row no longer exists, matching the cursor).
    hl_color = StyleColor(0x88 / 255, 0xbb / 255, 0xee / 255, 0x40 / 255)
    hl_cache = Dict{Int,GraphicsRect}()
    _hl_geo(k) = (v = overlay[].highlight; 1 <= k <= length(v) ? v[k] : nothing)
    function get_highlight_rect(k::Int)
        haskey(hl_cache, k) && return hl_cache[k]
        r = GraphicsRect(0, 0, 0, 0, hl_color, 4)
        set_cell_function!(getfield(r, :x), () -> (g = _hl_geo(k); g === nothing ? Int32(0) : Int32(g[1])))
        set_cell_function!(getfield(r, :y), () -> (g = _hl_geo(k); g === nothing ? Int32(0) : Int32(g[2])))
        set_cell_function!(getfield(r, :w), () -> (g = _hl_geo(k); g === nothing ? Int32(0) : Int32(g[3])))
        set_cell_function!(getfield(r, :h), () -> (g = _hl_geo(k); g === nothing ? Int32(0) : Int32(g[4])))
        hl_cache[k] = r
        r
    end
    # Membership reads only the highlight-rect *count* (a caret / no selection → 0),
    # so a caret move that keeps the same row count reuses the exact rects. Evict rows
    # that no longer exist so the cache cannot grow unbounded across selections.
    highlight_elements = CellVector(function ()
        n = length(overlay[].highlight)
        out = Any[get_highlight_rect(k) for k in 1:n]
        for k in collect(keys(hl_cache)); k <= n || delete!(hl_cache, k); end
        out
    end)
    highlight_canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                                      highlight_elements, layout_none, false, Cell(nothing))

    # The block resolved into visual lines (see `_line_groups`). Reads only the
    # element structure, the element types and a line's indentation — never a span's
    # `.content` — so it is invariant under content edits.
    lines_cell = Cell(() -> _line_groups(styled))

    # Per-line reactive cells, built once per line index and reused. A line's
    # `layout` reads only that line's spans' content; its `y` chains off the
    # cumulative height of the lines above (editing the last line moves nothing;
    # editing a middle line reflows the lines below — matching ListNode spines).
    # Each placement becomes a PERSISTENT GraphicsText/GraphicsRect reused across
    # re-layouts, its fields `set_cell_function!` cells reading the placement back out of the
    # line's `layout` (printer locality — dimension C, now line-local).
    line_cells = Dict{Int,NamedTuple}()
    function get_line_cells(L::Int)
        haskey(line_cells, L) && return line_cells[L]
        line_layout = Cell(() -> _layout_group(p, lines_cell[][L], 0, nothing, true, block_font))
        line_h = Cell(() -> Int32(line_layout[].height))
        line_y = if L == 1
            Cell(Int32(0))
        else
            prev = get_line_cells(L - 1)
            Cell(() -> Int32(prev.y[] + prev.h[]))
        end
        cache = Dict{Any,Any}()
        segs = CellVector(function ()
            pls = line_layout[].spans
            out = Any[]
            live = Set{Any}()
            for pl in pls
                if pl isa NamedTuple
                    push!(live, pl.key)
                    push!(out, _persistent_graphic!(cache, line_layout, pl))
                else
                    push!(out, pl)
                end
            end
            for k in collect(keys(cache))
                k in live || delete!(cache, k)
            end
            out
        end)
        sub = GraphicsCanvas(Cell(Int32(0)), line_y, Cell(Int32(0)), Cell(Int32(0)),
                             segs, layout_none, false, Cell(nothing))
        nt = (layout = line_layout, h = line_h, y = line_y, canvas = sub)
        line_cells[L] = nt
        nt
    end

    # Vertical stack of line sub-canvases. Its membership reads only `lines_cell`
    # (structure); `get_line_cells` builds/looks up cells without forcing them, so
    # no content is read here and the stack stays up to date across content edits.
    # `layout_vertical` + non-overlapping lets the dirty walk and renderer
    # early-stop past off-screen lines.
    lines_stack_elements = CellVector(function ()
        n = length(lines_cell[])
        Any[get_line_cells(L).canvas for L in 1:n]
    end)
    lines_stack = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                                 lines_stack_elements, layout_vertical, false, Cell(nothing))

    # Top canvas: the line stack with the selection-driven caret/highlight overlays
    # floating above it in absolute coordinates. A fixed three-slot vector, so its
    # membership never regenerates — the highlight's per-selection churn is confined
    # to the highlight sub-canvas's own element vector.
    top_elements = CellVector(Cell[Cell(highlight_canvas), Cell(lines_stack), Cell(cursor_rect)])

    # coord_map (reader-only — not in the rendered tree) assembled from the per-line
    # layouts, shifted into absolute coordinates by each line's y-offset so clicks
    # and key-navigation see exactly the same SegCoords as before.
    char_to_coord = Cell(function ()
        out = SegCoord[]
        n = length(lines_cell[])
        for L in 1:n
            lc = get_line_cells(L)
            ly = Int(lc.y[])
            for sc in lc.layout[].coord_map
                push!(out, SegCoord(sc.span_path, sc.char_start, sc.char_end,
                                    sc.x, sc.y + ly, sc.font, sc.text, sc.width, sc.height))
            end
        end
        out
    end)
    # `highlight_offset` keeps its value of 1 — the rasterized-image click
    # path (`_translate_click`) indexes the coord_map past the single leading
    # highlight element (now the highlight sub-canvas, holding the per-row rects).
    # That path is only reached when a *leaf* canvas is rasterized by
    # GraphicsCanvasToGraphicsImage; this canvas is non-leaf (it nests the highlight
    # and line sub-canvases), so the bare text examples use the MousePress/coord_map
    # reader instead, but the value is preserved for the rasterized-image path.
    highlight_offset = Cell(1)
    canvas_w = Cell(function ()
        w = 0
        for L in 1:length(lines_cell[])
            w = max(w, get_line_cells(L).layout[].width)
        end
        Int32(w)
    end)
    canvas_h = Cell(function ()
        n = length(lines_cell[])
        n == 0 ? Int32(0) : (lc = get_line_cells(n); Int32(lc.y[] + lc.h[]))
    end)
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), canvas_w, canvas_h,
                            top_elements, layout_none, true, Cell(nothing))
    TextToGraphicsIoMap(p, styled, canvas, char_to_coord, highlight_offset)
end

# ── Line grouping ─────────────────────────────────────────────────────────────
#
# The block resolved into visual lines — the one grouping both layout passes read,
# so the rendered lines and the caret/highlight overlay can never disagree about
# where a span sits.
#
# A group is one visual line: the spans that render on it (each tagged with its
# `SpanPath`, so a span inside a `TextLine` addresses `[i, j]`), the `indentation`
# it opens with, the `TextNewline` element that terminates it (or `nothing`), and
# whether an implicit line break precedes it.
#
# Lines arrive by two mechanisms and the grouping honours both:
#   • a `TextNewline` *element* terminates the current line;
#   • a `TextLine` element carries a line of its own and implies a break *before*
#     itself unless it leads the block — the separator rule of `text_flat_offsets`
#     and `TextBlockToString`, so `n` lines render with `n-1` breaks.
# `is_line` marks the second kind: only such a line, when empty, still occupies a
# row. The empty group a trailing `TextNewline` leaves behind must not, or every
# newline-terminated block would grow a phantom blank line.
#
# Block-level spans that follow a `TextLine` join the line it opened (a block is
# meant to hold either spans or lines; a mixed one degrades, it does not error).
#
# A span's `.content` is never read here — only the element structure, the element
# types and a line's indentation — so the grouping survives content edits
# untouched, which is what keeps a line's layout local to that line.
function _line_groups(styled::TextBlock)
    groups = NamedTuple[]
    spans = Tuple{SpanPath,Any}[]
    indentation = 0
    break_before = false
    is_line = false
    for (i, element) in enumerate(styled.elements)
        if element isa TextNewline
            push!(groups, (spans = spans, newline = element, indentation = indentation,
                           break_before = break_before, is_line = is_line))
            spans = Tuple{SpanPath,Any}[]
            indentation = 0
            break_before = false
            is_line = false
        elseif element isa TextLine
            if i > 1
                push!(groups, (spans = spans, newline = nothing, indentation = indentation,
                               break_before = break_before, is_line = is_line))
                spans = Tuple{SpanPath,Any}[]
            end
            indentation = element.indentation
            break_before = i > 1
            is_line = true
            for (j, span) in enumerate(element.elements)
                push!(spans, (Int[i, j], span))
            end
        else
            push!(spans, (Int[i], element))
        end
    end
    push!(groups, (spans = spans, newline = nothing, indentation = indentation,
                   break_before = break_before, is_line = is_line))
    groups
end

# ── Layout engine (wrap-free) ─────────────────────────────────────────────────

# Lay one line group's spans out, with `y0` as the vertical origin. The single span
# loop both passes run: a line's reactive sub-canvas calls it line-relative
# (`y0 = 0`, `collect_spans = true`) and with no caret; the overlay calls it once
# per group with the running absolute y and the caret to locate (`collect_spans =
# false` — it needs the geometry, not the glyphs). Sharing the loop is what keeps
# the caret on the character it was placed against.
#
# `cursor_pos` is a `(span::SpanPath, char)` caret, or `nothing`. The returned
# `cursor` is `(x, y, h)` when it fell inside this group. An embedded '\n' inside a
# span still breaks into sub-lines within the group (the renderer cannot draw a
# multi-line glyph run); the group's `height` covers them all.
function _layout_group(p::TextToGraphics, group, y0::Int, cursor_pos,
                       collect_spans::Bool, block_font::Cell)
    result = Any[]
    by_key = Dict{Any,Any}()
    occ = Dict{UInt64,Int}()   # per-span occurrence counter so a shared decorative
                               # span (one TextString at several flat positions)
                               # gets a distinct stable key per occurrence.
    coord_map = SegCoord[]
    cursor = nothing
    cx = p.start_x + _indent_width(p, group, block_font)
    cy = y0
    max_cx = cx
    line_h = 0

    for (path, span) in group.spans
        if span isa TextGraphics
            img_w = Int(span.width::Int32)
            img_h = Int(span.height::Int32)
            # Embed the span: a raster GraphicsImage for an image document, or a
            # live nested canvas for a pre-projected GraphicsCanvas (widget etc.).
            collect_spans && push!(result, _graphics_span_element(span, cx, cy, img_w, img_h))
            # Record a SegCoord for hit-testing: atomic position (0..1)
            push!(coord_map, SegCoord(path, 0, 1, cx, cy, span.font::StyleFont, "", img_w, img_h))
            line_h = max(line_h, img_h)
            if cursor === nothing && cursor_pos !== nothing && cursor_pos.span == path
                # The caret sits before or after the image, never inside it.
                cursor = (cursor_pos.char == 0 ? cx : cx + img_w, cy, max(line_h, 1))
            end
            cx += img_w
            continue
        end
        span isa TextString || continue
        span_oid = objectid(span)
        span_occ = (occ[span_oid] = get(occ, span_oid, 0) + 1)
        char_offset = 0                                 # local offset within this span
        txt = span.content::AbstractString               # reads span content cell
        sf  = span.font::StyleFont                       # reads span font cell
        col = span.font_color::StyleColor                # reads span font_color cell
        at_caret(k) = cursor === nothing && cursor_pos !== nothing &&
                      cursor_pos.span == path && cursor_pos.char == k

        lines = split(txt, '\n')
        for (li, line) in enumerate(lines)
            # Hard newline embedded in the span content.
            if li > 1
                # caret BEFORE the '\n' (char_offset still points at it)
                at_caret(char_offset) && (cursor = (cx, cy, max(line_h, 1)))
                max_cx = max(max_cx, cx)   # fold this sub-line's extent in before the reset
                cx = p.start_x
                # An empty sub-line still keeps one row of height.
                cy += line_h > 0 ? line_h : p.measure(" ", sf)[2]
                line_h = 0
                char_offset += 1           # count the '\n'
                # caret AFTER the '\n' — now at the start of the next sub-line
                at_caret(char_offset) && (cursor = (cx, cy, max(line_h, 1)))
            end

            isempty(line) && continue

            # No wrap: emit the whole sub-line as a single segment.
            seg_w, seg_h = p.measure(line, sf)
            line_h = max(line_h, seg_h)
            seg_x = cx
            seg_char_start = char_offset
            seg_len = length(line)
            if collect_spans
                fpl = _fill_placement(span, (span_oid, span_occ, li, :fill), seg_x, cy, seg_w, seg_h)
                if fpl !== nothing
                    push!(result, fpl)
                    by_key[fpl.key] = fpl
                end
                tpl = (kind = :text, key = (span_oid, span_occ, li),
                       text = String(line), x = seg_x, y = cy, font = sf,
                       color = col)
                push!(result, tpl)
                by_key[tpl.key] = tpl
            end
            push!(coord_map, SegCoord(path, seg_char_start, seg_char_start + seg_len, seg_x, cy, sf, line, seg_w, seg_h))
            if cursor === nothing && cursor_pos !== nothing && cursor_pos.span == path &&
               seg_char_start <= cursor_pos.char <= seg_char_start + seg_len
                local_pos = cursor_pos.char - seg_char_start
                cursor = (seg_x + (local_pos > 0 ? p.measure(first(line, local_pos), sf)[1] : 0),
                          cy, max(line_h, 1))
            end
            cx += seg_w
            char_offset += seg_len
        end
    end

    max_cx = max(max_cx, cx)
    height = cy + line_h - y0
    if isempty(coord_map) && (group.newline !== nothing || group.is_line)
        # A blank line still occupies one row, sized by the font it has no glyph to
        # take one from. The empty group left behind by a *trailing* newline is not
        # a line at all, and keeps its zero height.
        font = _line_height_font(group, block_font)
        height = font === nothing ? 0 : p.measure(" ", font)[2]
    end
    (spans = result, by_key = by_key, coord_map = coord_map,
     width = max_cx, height = height, cursor = cursor)
end

# Locate the caret and the selection highlight over the whole block, in the same
# absolute coordinates the line sub-canvases render into — by running the very
# layout the lines run, group by group.
#
# `span_flat_offsets` maps a span's `SpanPath` to the flat character offset it
# starts at: the space a `TextSpanReferenceStep` box is expressed in. A
# `TextLine` contributes its implicit break and its indentation to that space (the
# rule of `text_flat_offsets`), because the projection that emits the line counts
# both. A `TextNewline` contributes nothing: `WordWrapping` splices soft newlines
# into the block at wrap points and the box space must stay invariant under them.
function _layout_overlay(p::TextToGraphics, styled::TextBlock, sel, block_font::Cell)
    cursor_pos = _flat_cursor_coord(styled)
    coord_map = SegCoord[]
    span_flat_offsets = Dict{SpanPath,Int}()
    cursor = nothing
    y = p.start_y
    flat = 0

    for group in _line_groups(styled)
        group.break_before && (flat += 1)
        flat += group.indentation
        for (path, span) in group.spans
            span_flat_offsets[path] = flat
            flat += _box_flat_length(span)
        end
        laid = _layout_group(p, group, y, cursor_pos, false, block_font)
        append!(coord_map, laid.coord_map)
        cursor === nothing && (cursor = laid.cursor)
        y += laid.height
    end

    highlight = NTuple{4,Int}[]
    hl_range = _highlight_char_range(sel, coord_map)
    hl_range === nothing ||
        (highlight = _compute_span_rows(coord_map, span_flat_offsets, hl_range[1], hl_range[2], p))
    (cursor = cursor, highlight = highlight)
end

# The flat character length a span contributes to the box space (see
# `_layout_overlay`): an image occupies exactly one column, matching how
# `SyntaxToText` counts one for an embedded graphic.
_box_flat_length(span::TextString) = length(span.content::AbstractString)
_box_flat_length(::TextGraphics) = 1
_box_flat_length(::TextDocument) = 0

# Pixel width of a line's leading indentation. The indent is a property of the
# `TextLine`, not a span, so it carries no font of its own: measure it in the font
# of the line's first glyph span — an indented line is a code line, so that is the
# font the indent would have had.
function _indent_width(p::TextToGraphics, group, block_font::Cell)
    group.indentation > 0 || return 0
    for (_, span) in group.spans
        font = _element_font(span)
        font === nothing || return p.measure(" "^group.indentation, font)[1]
    end
    font = block_font[]
    font === nothing ? 0 : p.measure(" "^group.indentation, font)[1]
end

# The font an empty line is sized with. A flat block carries it on the
# `TextNewline` that terminates the line; a `TextLine` has none, so fall back to
# the block's prevailing font.
_line_height_font(group, block_font::Cell) =
    group.newline === nothing ? block_font[] : group.newline.font::StyleFont

# The block's prevailing font — the first font any element offers, in document
# order, or `nothing` for a block that has none. It sizes an empty `TextLine`,
# which has neither a glyph nor a terminating newline to read one from.
function _block_font(styled::TextBlock)
    for element in styled.elements
        font = _element_font(element)
        font === nothing || return font
    end
    nothing
end

_element_font(span::TextString) = span.font::StyleFont
_element_font(span::TextGraphics) = span.font::StyleFont
_element_font(newline::TextNewline) = newline.font::StyleFont
_element_font(::TextDocument) = nothing

function _element_font(line::TextLine)
    for span in line.elements
        font = _element_font(span)
        font === nothing || return font
    end
    nothing
end

# At least one `TextString` to put a caret in, at either depth.
_has_text_span(styled::TextBlock) =
    any(styled.elements) do element
        element isa TextString ||
            (element isa TextLine && any(span -> span isa TextString, element.elements))
    end

# ── Persistent per-segment graphics (printer locality — dimension C) ───────────
#
# `_layout_group` emits a *placement* (a stable key + geometry/content values) per
# text/fill segment instead of a graphic. The element builder turns each placement
# into a GraphicsText/GraphicsRect that is created ONCE per key and reused across
# re-layouts; its fields are `set_cell_function!` cells that read the placement back out of the
# `layout` cell (via `by_key`). So a structural edit keeps the object identity of
# every unchanged segment and only re-derives the cells of those whose placement
# moved — the cursor/highlight overlay idiom, generalised to every span. No cell is
# ever written from inside another cell's computation.

_plget(layout, key) = get(layout[].by_key, key, nothing)

# A background fill placement for a span carrying a non-default `fill_color`, or
# `nothing` for the (default) transparent fill. Mirrors `_push_fill_rect!`.
function _fill_placement(span, key, x, y, w, h)
    fill = span.fill_color
    fill isa StyleColor || return nothing
    (kind = :fill, key = key, x = x, y = y, w = w, h = h, color = fill)
end

_persistent_graphic!(cache, layout, pl) =
    get!(() -> pl.kind === :fill ? _make_persistent_rect(layout, pl) :
                                   _make_persistent_text(layout, pl),
         cache, pl.key)

# When a placement disappears (segment removed in a re-layout), the cell falls
# back to a fully transparent color so the persistent graphic paints nothing.
const _transparent = StyleColor(0.0, 0.0, 0.0, 0.0)

function _make_persistent_text(layout, pl0)
    key = pl0.key
    gt = GraphicsText(pl0.text, Int(pl0.x), Int(pl0.y), pl0.font, pl0.color)
    set_cell_function!(getfield(gt, :text),  () -> (q = _plget(layout, key); q === nothing ? "" : q.text))
    set_cell_function!(getfield(gt, :x),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.x)))
    set_cell_function!(getfield(gt, :y),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.y)))
    set_cell_function!(getfield(gt, :font),  () -> (q = _plget(layout, key); q === nothing ? pl0.font : q.font))
    set_cell_function!(getfield(gt, :color), () -> (q = _plget(layout, key); q === nothing ? _transparent : q.color))
    gt
end

function _make_persistent_rect(layout, pl0)
    key = pl0.key
    rect = GraphicsRect(Int(pl0.x), Int(pl0.y), Int(pl0.w), Int(pl0.h), pl0.color)
    set_cell_function!(getfield(rect, :x),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.x)))
    set_cell_function!(getfield(rect, :y),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.y)))
    set_cell_function!(getfield(rect, :w),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.w)))
    set_cell_function!(getfield(rect, :h),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.h)))
    set_cell_function!(getfield(rect, :color), () -> (q = _plget(layout, key); q === nothing ? _transparent : q.color))
    rect
end

# ── ListNode path: lazy paragraph-level mapping ──────────────────────

"""
    _print_listnode(p, styled, ctx)

When `TextBlock.elements` is a `ListNode`, produce a top-level
`GraphicsCanvas` with `layout_vertical`, `overlapping_elements=false`,
and a `ListNode` of sub-canvases — one per paragraph (spans between
`TextNewline` nodes). Each paragraph lays out left-to-right; word wrapping
inside a paragraph is upstream's responsibility.
"""
function _print_listnode(p::TextToGraphics, styled::TextBlock, ctx)
    head_node = styled.elements::ListNode
    output_head = _build_paragraph_node(p, head_node, 0)
    canvas = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), output_head, layout_vertical, false, Cell(nothing))
    TextToGraphicsIoMap(p, styled, canvas, Cell(SegCoord[]), Cell(0))
end

"""
    _build_paragraph_node(p, input_node, y_offset) -> ListNode

Starting from `input_node`, collect all spans until a `TextNewline` or
end of list (one paragraph). Lay them out into a sub-`GraphicsCanvas`
at position `(0, y_offset)`. Return a `ListNode` whose value is that
sub-canvas, with a lazy `next` thunk that builds the next paragraph.
"""
function _build_paragraph_node(p::TextToGraphics, input_node::ListNode, y_offset::Int)
    # Collect paragraph spans and find the node after the paragraph
    spans = Any[]
    cur = input_node
    while cur !== nothing
        val = cur.value
        if val isa TextNewline
            cur = cur.next  # skip past the newline
            break
        end
        push!(spans, val)
        next_node = cur.next
        if next_node === nothing
            cur = nothing
            break
        end
        cur = next_node
    end

    sub_canvas = _layout_paragraph(p, spans, y_offset)
    para_height = _paragraph_height(p, spans)

    out_node = ListNode(sub_canvas)

    next_input = cur
    set_cell_function!(getfield(out_node, :next), () -> begin
        next_input === nothing && return nothing
        next_out = _build_paragraph_node(p, next_input, y_offset + para_height)
        set_cell_value!(getfield(next_out, :prev), out_node)
        next_out
    end)

    set_cell_function!(getfield(out_node, :prev), () -> begin
        prev_start = input_node.prev
        prev_start === nothing && return nothing
        prev_out = _build_paragraph_node_prev(p, prev_start, y_offset)
        prev_out === nothing && return nothing
        set_cell_value!(getfield(prev_out, :next), out_node)
        prev_out
    end)

    out_node
end

"""
    _build_paragraph_node_prev(p, input_node_prev, y_offset) -> ListNode or nothing

Starting from `input_node_prev` (the text node just before the current head),
traverse backward collecting spans until a `TextNewline` or nothing (one
paragraph). Lay them out into a sub-`GraphicsCanvas` at a negative y-offset.
Return a `ListNode` whose value is that sub-canvas, with a lazy `prev` thunk.
"""
function _build_paragraph_node_prev(p::TextToGraphics, input_node_prev, y_offset::Int)
    cur = input_node_prev
    if cur !== nothing && cur.value isa TextNewline
        cur = cur.prev
    end
    cur === nothing && return nothing

    spans_reversed = Any[]
    while cur !== nothing
        val = cur.value
        if val isa TextNewline
            break
        end
        push!(spans_reversed, val)
        cur = cur.prev
    end

    isempty(spans_reversed) && return nothing

    spans = reverse(spans_reversed)

    para_height = _paragraph_height(p, spans)
    new_y_offset = y_offset - para_height

    sub_canvas = _layout_paragraph(p, spans, new_y_offset)

    out_node = ListNode(sub_canvas)

    prev_boundary = cur
    set_cell_function!(getfield(out_node, :prev), () -> begin
        prev_boundary === nothing && return nothing
        prev_out = _build_paragraph_node_prev(p, prev_boundary, new_y_offset)
        prev_out === nothing && return nothing
        set_cell_value!(getfield(prev_out, :next), out_node)
        prev_out
    end)

    out_node
end

"""
    _layout_paragraph(p, spans, y_offset) -> GraphicsCanvas

Lay out a list of `TextString` spans into `GraphicsText` elements within a
sub-canvas positioned at `(0, y_offset)`. No wrap; each span goes down as a
single segment, advancing the cursor on the line.
"""
function _layout_paragraph(p::TextToGraphics, spans::Vector, y_offset::Int)
    result = Any[]
    cx = 0
    line_h = 0

    for span in spans
        span isa TextString || continue
        txt = span.content::AbstractString
        sf  = span.font::StyleFont
        col = span.font_color::StyleColor

        isempty(txt) && continue

        seg_w, seg_h = p.measure(txt, sf)
        line_h = max(line_h, seg_h)
        _push_fill_rect!(result, span, cx, 0, seg_w, seg_h)
        push!(result, _make_sdl(txt, cx, 0, sf, col))
        cx += seg_w
    end

    GraphicsCanvas(Int32(0), Int32(y_offset), Int32(0), Int32(0), CellVector(Cell[Cell(e) for e in result]),
                   layout_none, false, Cell(nothing))
end

"""
    _paragraph_height(p, spans) -> Int

Pixel height a paragraph occupies. With wrapping removed, this is just the
max span height (one visual line per paragraph).
"""
function _paragraph_height(p::TextToGraphics, spans::Vector)
    line_h = 0
    for span in spans
        span isa TextString || continue
        txt = span.content::AbstractString
        sf  = span.font::StyleFont
        isempty(txt) && continue
        _, h = p.measure(txt, sf)
        line_h = max(line_h, h)
    end
    line_h
end

# ── Selection → cursor position ───────────────────────────────────────
#
# `_flat_cursor_coord` and `_is_structural_selection` are pure `TextBlock`-selection
# helpers living in `TextModule` (the document layer); they are imported above. They
# are shared between the geometry-free `read_gesture` (in TextModule) and the
# geometry-dependent layout / mouse / line-motion code here.

function _make_sdl(text, x, y, font, color::StyleColor)
    GraphicsText(Cell(text), Cell(Int32(x)), Cell(Int32(y)),
                Cell(font), Cell(color),
                Cell(nothing))
end

# If `span` carries a background `fill_color` (a `StyleColor`, not the default
# `nothing`), emit a `GraphicsRect` covering the segment box. Caller pushes this
# before the span's `GraphicsText` so it paints behind. No-op for the default
# `nothing` fill, so existing documents render unchanged.
function _push_fill_rect!(result, span, x::Integer, y::Integer, w::Integer, h::Integer)
    fill = span.fill_color
    fill isa StyleColor || return
    push!(result, GraphicsRect(Int(x), Int(y), Int(w), Int(h), fill))
end

# ── Reader helpers ──────────────────────────────────────────────────────

function _seg_cursor_x(sc::SegCoord, cursor_pos::Int, measure::Function)
    local_pos = cursor_pos - sc.char_start
    local_pos <= 0 && return sc.x
    # Image segment: char_end=1 means "after the image" → right edge at x+width.
    isempty(sc.text) && return sc.x + sc.width
    prefix = first(sc.text, min(local_pos, length(sc.text)))
    sc.x + measure(prefix, sc.font)[1]
end

function _char_position_at_x(sc::SegCoord, target_x::Int, measure::Function)
    txt = sc.text
    # Image segment: binary left/right half decision about the image box.
    if isempty(txt) && sc.char_start == 0 && sc.char_end == 1
        mid = sc.x + sc.width ÷ 2
        return target_x < mid ? 0 : 1
    end
    best_k    = 0
    best_dist = abs(sc.x - target_x)
    for k in 1:length(txt)
        xk = sc.x + measure(first(txt, k), sc.font)[1]
        d  = abs(xk - target_x)
        if d < best_dist
            best_dist = d
            best_k    = k
        end
        xk >= target_x && break
    end
    sc.char_start + best_k
end

# Translate a downstream ReplaceSelectionOperation whose path encodes a mouse click
# (ElementReferenceStep(segment_i) → PointReferenceStep(rx, ry)) back into a flat
# character-position selection on the Text domain.
#
# The path is produced by GraphicsCanvasToGraphicsImage.read_intent:
#   ElementReferenceStep(i)   — 1-based index of the graphics element that was hit
#   PointReferenceStep(rx,…) — pixel offset within that element
#
# We look up the matching SegCoord in char_to_coord, convert the pixel
# x-offset to a character position using _char_position_at_x, and return
# a fresh ReplaceSelectionOperation on the flat PositionReferenceStep domain.
function _translate_click(p::TextToGraphics, iomap::TextToGraphicsIoMap, path)
    path isa ConcreteReference || return nothing
    h1 = head(path)
    h1 isa RangeReferenceStep || return nothing
    i  = h1.start + 1
    rest = tail(path)

    # Adjust for highlight rects prepended before text segments
    hl_off = iomap.highlight_offset[]
    i -= hl_off
    coord_map = iomap.char_to_coord[]
    (i < 1 || i > length(coord_map)) && return nothing
    seg = coord_map[i]

    rest isa ConcreteReference || return nothing
    h2 = head(rest)
    h2 isa PointReferenceStep || return nothing
    rx = h2.x::Int
    char_pos = _char_position_at_x(seg, seg.x + rx, p.measure)
    return _flat_hit_op(iomap.input, seg.span_path, char_pos)
end

# Pick the segment a (canvas-x, canvas-y) click landed on. Matches the
# logic in GraphicsCanvasToGraphicsImage.read_intent for text elements:
#   on a y-band that contains the click, pick the segment with the largest
#   x ≤ click_x (i.e. the rightmost left-edge that still sits to the left
#   of the click). If no band matches y, snap to the nearest line by y.
function _hit_segment(coord_map::Vector{SegCoord}, x::Int, y::Int)
    on_band = SegCoord[]
    for sc in coord_map
        fs = _seg_band_height(sc)
        if y >= sc.y && y < sc.y + fs
            push!(on_band, sc)
        end
    end

    candidates = if !isempty(on_band)
        on_band
    else
        # Snap to nearest line by y.
        best_dy = typemax(Int)
        best_y  = 0
        for sc in coord_map
            fs = _seg_band_height(sc)
            dy = y < sc.y ? sc.y - y : (y >= sc.y + fs ? y - (sc.y + fs - 1) : 0)
            if dy < best_dy
                best_dy = dy
                best_y  = sc.y
            end
        end
        filter(sc -> sc.y == best_y, coord_map)
    end

    isempty(candidates) && return nothing

    # Pick the segment with the largest x ≤ click_x.
    best = candidates[1]
    best_x = -1
    for sc in candidates
        sc.x <= x && sc.x > best_x || continue
        best_x = sc.x
        best   = sc
    end

    # Click is left of every segment on this line — fall back to the leftmost.
    if best_x < 0
        best = candidates[1]
        for sc in candidates
            sc.x < best.x && (best = sc)
        end
    end
    best
end

# ── Highlight helpers ─────────────────────────────────────────────────────

"""
    _highlight_char_range(sel, coord_map) -> (start, stop) or nothing

Extract the flat character range for a box selection from the TextBlock's
selection. Recognized shapes:
- `EmptyReference` (∅) → highlight the full extent `(0, N)` where N is
  the total character count across all segments.
- `ConcreteReference(TextSpanReferenceStep(s, e), ∅)` → `(s, e)`.
Returns `nothing` for any other selection shape (normal cursor, etc.).
"""
function _highlight_char_range(sel, coord_map::Vector{SegCoord})
    # The selection is canonical at rest: skip its non-navigating TypeReferenceStep
    # checkpoints before reading the box structure underneath.
    sel = sel
    if sel isa EmptyReference
        isempty(coord_map) && return nothing
        # Cover all segments: use a large sentinel that exceeds any absolute offset.
        return (0, typemax(Int) >> 1)
    end
    sel isa ConcreteReference || return nothing
    h = sel.head
    sel.tail isa EmptyReference || return nothing
    if h isa TextRangeReferenceStep
        # A non-empty text selection highlights its flat range; a caret has none
        # (it is drawn as the cursor rect instead).
        return h.start == h.stop ? nothing : (h.start, h.stop)
    end
    h isa TextSpanReferenceStep || return nothing
    return (h.start, h.stop)
end

# Whether the highlighted sub-range `[s, e)` (offsets in this segment's own base
# space) of `sc` is entirely whitespace — a leading indent span, a newline span, or
# a zero-width indent slot. Such a piece must not anchor a row's left/right edge, so
# the highlight hugs the content and each interior line starts at its indentation
# level. A partly-highlighted content segment keeps only its highlighted substring
# for the whitespace test, so a content run whose *highlighted* part is blank is
# skipped too (rare, but correct at a range boundary).
function _hl_piece_blank(sc::SegCoord, s::Int, e::Int)
    e <= s && return true
    t = sc.text
    lo = s - sc.char_start           # 0-based char offset into sc.text
    hi = e - sc.char_start
    (lo < 0 || hi > length(t)) && return all(isspace, t)   # fallback: whole piece
    chars = collect(t)
    all(isspace, @view chars[(lo + 1):hi])
end

"""
    _compute_span_rows(coord_map, span_flat_offsets, hl_start, hl_stop, p) -> Vector of (x, y, w, h)

The **content-hugging per-row** geometry of a `TextSpanReferenceStep` / `∅` box selection:
one rect per visual row the range `[hl_start, hl_stop)` touches, each hugging that
row's highlighted *content* rather than filling a bounding box. Per row, only the
in-range segment pieces carrying a non-whitespace character anchor the rect, which
then runs `[min px_left … max px_right]` of those pieces; a row whose only in-range
content is whitespace (a bare indent line) yields no rect.

This makes a structural (whole-node) selection read as the subtree's own glyphs: the
first line starts at the node's first char, interior lines start at their indentation
level (the node's own indent spans are in range but blank, so they don't anchor), and
the last line ends at the node's last char — never the empty box a single bounding
rect painted to the right of the `{`/`}` lines. Rows are returned top-to-bottom; the
caller paints each as a persistent highlight rect (light blue, ~25% alpha, rounded).
"""
function _compute_span_rows(coord_map::Vector{SegCoord}, span_flat_offsets::Dict{SpanPath,Int}, hl_start::Int, hl_stop::Int, p::TextToGraphics)
    rows = Dict{Int,NTuple{4,Int}}()   # row y => (x_left, x_right, y_top, y_bot)
    order = Int[]                      # rows in first-seen order (deduped to sort)
    for sc in coord_map
        base = get(span_flat_offsets, sc.span_path, 0)
        abs_start = base + sc.char_start
        abs_end = base + sc.char_end
        # Overlap with [hl_start, hl_stop)?
        (abs_end <= hl_start || abs_start >= hl_stop) && continue
        seg_hl_start = max(hl_start, abs_start) - base
        seg_hl_end = min(hl_stop, abs_end) - base
        # Blank (indent/newline) pieces don't anchor a row — that is what makes the
        # highlight hug content and interior lines begin at their indentation.
        _hl_piece_blank(sc, seg_hl_start, seg_hl_end) && continue
        px_left = _seg_cursor_x(sc, seg_hl_start, p.measure)
        px_right = _seg_cursor_x(sc, seg_hl_end, p.measure)
        fs = font_logical_size(sc.font)
        if haskey(rows, sc.y)
            (l, r, t, b) = rows[sc.y]
            rows[sc.y] = (min(l, px_left), max(r, px_right), min(t, sc.y), max(b, sc.y + fs))
        else
            rows[sc.y] = (px_left, px_right, sc.y, sc.y + fs)
            push!(order, sc.y)
        end
    end
    sort!(order)
    rects = NTuple{4,Int}[]
    for y in order
        (l, r, t, b) = rows[y]
        w = r - l
        h = b - t
        (w <= 0 || h <= 0) && continue
        push!(rects, (l, t, w, h))
    end
    rects
end

"""
    _compute_column_geo(coord_map, span_flat_offsets, hl_start, hl_stop, p) -> Vector of (x, y, w, h)

The **column-box** geometry of variant 2 (`TextColumnReferenceStep`): a true rectangle
`[col(hl_start) … col(hl_stop)]` painted on every row the selection spans,
independent of the glyph content on each row — the Sublime / VS Code "column
select". Returns one `(x, y, w, h)` rect per row, or an empty vector when either
endpoint's column cannot be resolved or the two columns coincide.

Reserved for a future column-select gesture; no producer emits a
`TextColumnReferenceStep` yet, so this is exercised by a direct unit test rather than
the live overlay. `_layout_overlay` today paints the single `_compute_span_geo`
bounding rect; generalising it to a per-row rect vector (the same render path a
multi-line stream highlight needs) is the remaining wiring.
"""
function _compute_column_geo(coord_map::Vector{SegCoord}, span_flat_offsets::Dict{SpanPath,Int}, hl_start::Int, hl_stop::Int, p::TextToGraphics)
    # Resolve a flat offset to its (x, y_top, y_bottom) via the segment it falls in.
    function _col(off)
        for sc in coord_map
            base = get(span_flat_offsets, sc.span_path, 0)
            (base + sc.char_start <= off <= base + sc.char_end) || continue
            x = _seg_cursor_x(sc, off - base, p.measure)
            fs = font_logical_size(sc.font)
            return (x, sc.y, sc.y + fs)
        end
        nothing
    end
    a = _col(hl_start)
    b = _col(hl_stop)
    (a === nothing || b === nothing) && return NTuple{4,Int}[]
    left  = min(a[1], b[1])
    right = max(a[1], b[1])
    w = right - left
    w <= 0 && return NTuple{4,Int}[]
    top    = min(a[2], b[2])
    bottom = max(a[3], b[3])
    # One rect per distinct row the coord_map places inside `[top, bottom)`.
    rects = NTuple{4,Int}[]
    seen  = Set{Int}()
    for sc in coord_map
        (sc.y in seen) && continue
        (top <= sc.y < bottom) || continue
        push!(seen, sc.y)
        push!(rects, (left, sc.y, w, font_logical_size(sc.font)))
    end
    sort!(rects, by = r -> r[2])
    rects
end

# ── Image helpers ────────────────────────────────────────────────────────

"""
    _extract_image_data(span::TextGraphics)

Extract the decoded image from a `TextGraphics` span's embedded document.
Returns whatever the content's `.raw` cell holds, untouched:

- a `(pixels::Vector{UInt8}, native_w, native_h)` tuple from the decoder —
  the native size travels with the bytes so the backend can build the
  surface correctly and scale it to the span's display box,
- a bare `Vector{UInt8}` or cached texture `Ptr`,
- or `nothing` until the image is decoded.
"""
function _extract_image_data(span::TextGraphics)
    content = span.content
    content === nothing && return nothing
    hasproperty(content, :raw) ? content.raw : nothing
end

"""
    _graphics_span_element(span::TextGraphics, x, y, w, h)

The rendered element for an inline `TextGraphics` span, placed at `(x, y)` with
display size `w × h`:

- when the embedded `content` is already a **`GraphicsCanvas`** — a sub-document
  projected to graphics (e.g. a `WidgetTable` run through `WidgetToGraphics`) — it
  is spliced in live as a nested canvas, so it renders as real, selectable graphics
  rather than a raster (this is "handle a widget like an image, projected to
  graphics"). The canvas is positioned via a fresh single-child wrapper so the
  persistent inner canvas's own `x`/`y` cells are never written from inside this
  layout cell.
- otherwise (an `ImageFile`/`ImageMemory`, the original case) it is rasterized to
  a `GraphicsImage` from the content's decoded `.raw` bytes.

The field type on `TextGraphics.content` is only a hint — the `Cell` holds either.
"""
function _graphics_span_element(span::TextGraphics, x::Integer, y::Integer, w::Integer, h::Integer)
    content = span.content
    if content isa GraphicsCanvas
        return GraphicsCanvas(Cell(Int32(x)), Cell(Int32(y)), Cell(Int32(w)), Cell(Int32(h)),
                              CellVector(Cell[Cell(content)]), layout_none, false, Cell(nothing))
    end
    GraphicsImage(x, y, w, h, _extract_image_data(span))
end

"""
    _is_image_seg(sc::SegCoord) -> Bool

Returns true when the `SegCoord` represents an inline image (TextGraphics)
rather than a text segment. Image segments have empty text and span [0,1).
"""
_is_image_seg(sc::SegCoord) = isempty(sc.text) && sc.char_start == 0 && sc.char_end == 1

"""
    _seg_band_height(sc::SegCoord) -> Int

Vertical extent of a segment's clickable y-band. Text segments use the
logical font size; an inline image extends its band over the whole image
height so a click anywhere on a tall image still lands on it.
"""
_seg_band_height(sc::SegCoord) =
    _is_image_seg(sc) ? max(font_logical_size(sc.font), sc.height) :
                        font_logical_size(sc.font)

end # module
