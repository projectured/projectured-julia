"""
    TextToGraphicsModule

Text → Graphics projection. Pure layout pass: arranges already-wrapped spans
left-to-right and breaks the line only on explicit `TextNewline` elements or
embedded `\\n` characters. Word wrapping itself lives in `WordWrapping`,
inserted upstream of `TextToGraphics` in the pipeline.

A coordinate table in the IoMap records the character range and pixel
position of each emitted segment. The reader uses it for keyboard navigation
(arrow keys, home/end) and to translate downstream mouse-click selections
into character positions.

Text measurement is provided via the mandatory `measure(text, font) -> (w, h)`
function parameter. Backends inject a real measurer (e.g. `sdl_measure_text`)
at construction time.
"""
module TextToGraphicsModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..CollectionModule: CellVector, ListNode, CollectionDocument
import ..ProjectionApiModule: projection_print, projection_read, map_reference_forward, map_reference_backward, Projection
import ..TextModule: TextText, TextString, TextNewline, TextDocument
import ..GraphicsModule: GraphicsText, GraphicsRect, GraphicsCanvas, layout_none, layout_vertical
import ..FontModule: StyleFont
import ..ColorModule: StyleColor
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference, PositionReference, RangeReference, PointReference, EmptyReferencePath, FieldReference, head, tail
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown
import ..IoMapApiModule: IoMap
export TextToGraphics, TextToGraphicsIoMap

"""
    SegCoord(span_idx, char_start, char_end, x, y, font, text)

One entry per emitted text segment. `span_idx` is the 1-based index of the
`TextString` element in the input `TextText`. `char_start`/`char_end` are
0-based offsets local to that span (exclusive end). `(x, y)` are pixel
coordinates of the segment's top-left.
"""
struct SegCoord
    span_idx::Int
    char_start::Int
    char_end::Int
    x::Int
    y::Int
    font::StyleFont
    text::String
end

"""
    TextToGraphicsIoMap

IoMap for `TextToGraphics`. `char_to_coord` holds one `SegCoord` per emitted
text segment with character range, pixel position, font, and text.
"""
struct TextToGraphicsIoMap <: IoMap
    projection::Any
    input::TextText
    output::GraphicsCanvas
    char_to_coord::Cell  # Cell{Vector{SegCoord}}
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

function projection_read(p::TextToGraphics, iomap::TextToGraphicsIoMap, op::ReplaceSelectionOperation)
    return _translate_click(p, iomap, op.path)
end

function projection_read(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt)
    evt isa KeyDown || return nothing
    styled = iomap.input
    span_infos = [(elem_idx, length(span.content::AbstractString))
                  for (elem_idx, span) in enumerate(styled)
                  if span isa TextString]
    isempty(span_infos) && return nothing

    if evt.key == :home && evt.modifiers.ctrl
        first = span_infos[1]
        return ReplaceSelectionOperation(_build_selection_path(first[1], 0))
    elseif evt.key == :end && evt.modifiers.ctrl
        last = span_infos[end]
        return ReplaceSelectionOperation(_build_selection_path(last[1], last[2]))
    end

    current = _cursor_position(styled.selection)
    current === nothing && return nothing

    if evt.key == :left
        span_idx, char_idx = current.span, current.char
        if char_idx > 0
            return ReplaceSelectionOperation(_build_selection_path(span_idx, char_idx - 1))
        else
            pos = findfirst(si -> si[1] == span_idx, span_infos)
            if pos === nothing || pos == 1
                return ReplaceSelectionOperation(_build_selection_path(span_idx, 0))  # clamp
            end
            prev = span_infos[pos - 1]
            # Use prev[2]-1 to skip the boundary duplicate (prev[2] == current (span,0) visually)
            return ReplaceSelectionOperation(_build_selection_path(prev[1], max(0, prev[2] - 1)))
        end
    elseif evt.key == :right
        span_idx, char_idx = current.span, current.char
        pos = findfirst(si -> si[1] == span_idx, span_infos)
        pos === nothing && return ReplaceSelectionOperation(_build_selection_path(span_idx, char_idx))  # clamp
        span_len = span_infos[pos][2]
        if char_idx < span_len
            return ReplaceSelectionOperation(_build_selection_path(span_idx, char_idx + 1))
        else
            if pos == length(span_infos)
                return ReplaceSelectionOperation(_build_selection_path(span_idx, char_idx))  # clamp
            end
            next = span_infos[pos + 1]
            # Use char 1 to skip the boundary duplicate (char 0 == current (span,span_len) visually)
            return ReplaceSelectionOperation(_build_selection_path(next[1], next[2] > 0 ? 1 : 0))
        end
    elseif evt.key == :home || evt.key == :end
        coord_map = iomap.char_to_coord[]
        isempty(coord_map) && return nothing
        seg_idx = findfirst(sc -> sc.span_idx == current.span && sc.char_start <= current.char <= sc.char_end, coord_map)
        seg_idx === nothing && return nothing
        current_y = coord_map[seg_idx].y
        line_segs = filter(sc -> sc.y == current_y, coord_map)
        sc = evt.key == :home ? line_segs[1] : line_segs[end]
        new_char = evt.key == :home ? sc.char_start : sc.char_end
        return ReplaceSelectionOperation(_build_selection_path(sc.span_idx, new_char))
    elseif evt.key == :up || evt.key == :down
        coord_map = iomap.char_to_coord[]
        isempty(coord_map) && return nothing
        seg_idx = findfirst(sc -> sc.span_idx == current.span && sc.char_start <= current.char <= sc.char_end, coord_map)
        seg_idx === nothing && return nothing
        cur_sc   = coord_map[seg_idx]
        cursor_x = _seg_cursor_x(cur_sc, current.char, p.measure)
        current_y = cur_sc.y
        target_segs = if evt.key == :up
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
        return ReplaceSelectionOperation(_build_selection_path(best_sc.span_idx, best_pos))
    end
    return evt
end

# ── Layout engine (wrap-free) ──────────────────────────────────────────

"""
    projection_print(p::TextToGraphics, styled::TextText) -> Cell{Vector{GraphicsText}}

Lay an already-wrapped `TextText` out into reactive `GraphicsText` primitives.
Lines advance left-to-right; the line breaks come from `TextNewline` elements
and from `\\n` characters embedded in `TextString` content. The wrap itself —
splitting at word boundaries when text would overflow — is the job of
`WordWrapping` upstream.

The returned `Cell` holds a `Vector{GraphicsText}`. Its thunk reads every
relevant cell in the `TextText`, so any value or structural change
invalidates the layout; recomputation happens only when the `Cell` is read.
"""
function projection_print(p::TextToGraphics, styled::TextText, recursion, ctx)
    # ListNode path: lazy paragraph-level mapping
    if styled.elements isa ListNode
        return _print_listnode(p, styled, ctx)
    end
    both = Cell(function ()
        result = Any[]
        coord_map = SegCoord[]
        cx = p.start_x
        cy = p.start_y
        max_cx = cx
        line_h = 0

        cursor_pos = _cursor_position(styled.selection)
        cursor_x = -1
        cursor_y = -1
        cursor_line_h = 0

        for (elem_idx, span) in enumerate(styled)         # reads styled.elements cell
            if span isa TextNewline
                cx = p.start_x
                cy += line_h
                line_h = 0
                continue
            end
            span isa TextString || continue
            span_idx = elem_idx                            # 1-based index in elements
            char_offset = 0                               # local offset within this span
            txt  = span.content::AbstractString             # reads span content cell
            sf   = span.font::StyleFont                     # reads span font cell
            col  = span.font_color::StyleColor              # reads span font_color cell

            r, g, b, a = (UInt8(round(col.red * 255)), UInt8(round(col.green * 255)), UInt8(round(col.blue * 255)), UInt8(round(col.alpha * 255)))

            lines = split(txt, '\n')
            for (li, line) in enumerate(lines)
                # Hard newline embedded in the span content.
                if li > 1
                    # cursor BEFORE the \n (char_offset still points to \n pos)
                    if cursor_pos !== nothing && cursor_x < 0 &&
                       cursor_pos.span == span_idx && cursor_pos.char == char_offset
                        cursor_x = cx
                        cursor_y = cy
                        cursor_line_h = line_h
                    end
                    cx = p.start_x
                    cy += line_h
                    line_h = 0
                    char_offset += 1  # count the \n
                    # cursor AFTER the \n (now at beginning of next line)
                    if cursor_pos !== nothing && cursor_x < 0 &&
                       cursor_pos.span == span_idx && cursor_pos.char == char_offset
                        cursor_x = cx
                        cursor_y = cy
                        cursor_line_h = line_h
                    end
                end

                isempty(line) && continue

                # No wrap: emit the whole line as a single segment.
                seg_w, seg_h = p.measure(line, sf)
                line_h = max(line_h, seg_h)
                seg_x = cx
                seg_char_start = char_offset
                seg_len = length(line)
                push!(result, _make_sdl(line, seg_x, cy, sf, r, g, b, a))
                push!(coord_map, SegCoord(span_idx, seg_char_start, seg_char_start + seg_len, seg_x, cy, sf, line))
                if cursor_pos !== nothing && cursor_x < 0 &&
                   cursor_pos.span == span_idx &&
                   cursor_pos.char >= seg_char_start && cursor_pos.char <= seg_char_start + seg_len
                    local_pos = cursor_pos.char - seg_char_start
                    cursor_x = seg_x + (local_pos > 0 ? p.measure(first(line, local_pos), sf)[1] : 0)
                    cursor_y = cy
                    cursor_line_h = line_h
                end
                cx += seg_w
                char_offset += seg_len
            end
        end

        # Emit cursor line
        if cursor_x >= 0
            push!(result, GraphicsRect(cursor_x, cursor_y, 2, max(cursor_line_h, 1),
                                       0x00, 0x00, 0x00, 0xff))
        end

        max_cx = max(max_cx, cx)
        total_w = max_cx
        total_h = cy + line_h
        return (result, coord_map, total_w, total_h)
    end)
    char_to_coord = Cell(() -> both[][2])
    canvas_w = Cell(() -> Int32(both[][3]))
    canvas_h = Cell(() -> Int32(both[][4]))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), canvas_w, canvas_h, CellVector(() -> both[][1]), layout_none, false, Cell(nothing))
    TextToGraphicsIoMap(p, styled, canvas, char_to_coord)
end

# ── ListNode path: lazy paragraph-level mapping ──────────────────────

"""
    _print_listnode(p, styled, ctx)

When `TextText.elements` is a `ListNode`, produce a top-level
`GraphicsCanvas` with `layout_vertical`, `overlapping_elements=false`,
and a `ListNode` of sub-canvases — one per paragraph (spans between
`TextNewline` nodes). Each paragraph lays out left-to-right; word wrapping
inside a paragraph is upstream's responsibility.
"""
function _print_listnode(p::TextToGraphics, styled::TextText, ctx)
    head_node = styled.elements::ListNode
    output_head = _build_paragraph_node(p, head_node, 0)
    canvas = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), output_head, layout_vertical, false, Cell(nothing))
    TextToGraphicsIoMap(p, styled, canvas, Cell(SegCoord[]))
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
    setfn!(getfield(out_node, :next), () -> begin
        next_input === nothing && return nothing
        next_out = _build_paragraph_node(p, next_input, y_offset + para_height)
        setval!(getfield(next_out, :prev), out_node)
        next_out
    end)

    setfn!(getfield(out_node, :prev), () -> begin
        prev_start = input_node.prev
        prev_start === nothing && return nothing
        prev_out = _build_paragraph_node_prev(p, prev_start, y_offset)
        prev_out === nothing && return nothing
        setval!(getfield(prev_out, :next), out_node)
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
    setfn!(getfield(out_node, :prev), () -> begin
        prev_boundary === nothing && return nothing
        prev_out = _build_paragraph_node_prev(p, prev_boundary, new_y_offset)
        prev_out === nothing && return nothing
        setval!(getfield(prev_out, :next), out_node)
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
        r, g, b, a = (UInt8(round(col.red * 255)), UInt8(round(col.green * 255)),
                       UInt8(round(col.blue * 255)), UInt8(round(col.alpha * 255)))

        isempty(txt) && continue

        seg_w, seg_h = p.measure(txt, sf)
        line_h = max(line_h, seg_h)
        push!(result, _make_sdl(txt, cx, 0, sf, r, g, b, a))
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

function _cursor_position(sel)
    sel === nothing && return nothing
    @reference_case sel begin
        elements{s:_}.content{c:_} => (span=s + 1, char=c)
    end
end

_build_selection_path(span_idx::Int, char_idx::Int) =
    @reference elements[span_idx].content{char_idx}

function _make_sdl(text, x, y, font, r, g, b, a)
    GraphicsText(Cell(text), Cell(Int32(x)), Cell(Int32(y)),
                Cell(font),
                Cell(UInt8(r)), Cell(UInt8(g)), Cell(UInt8(b)), Cell(UInt8(a)),
                Cell(nothing))
end

# ── Reader helpers ──────────────────────────────────────────────────────

function _seg_cursor_x(sc::SegCoord, cursor_pos::Int, measure::Function)
    local_pos = cursor_pos - sc.char_start
    local_pos <= 0 && return sc.x
    prefix = first(sc.text, min(local_pos, length(sc.text)))
    sc.x + measure(prefix, sc.font)[1]
end

function _char_position_at_x(sc::SegCoord, target_x::Int, measure::Function)
    txt = sc.text
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
# (ElementReference(segment_i) → PointReference(rx, ry)) back into a flat
# character-position selection on the Text domain.
#
# The path is produced by GraphicsCanvasToGraphicsImage.projection_read:
#   ElementReference(i)   — 1-based index of the graphics element that was hit
#   PointReference(rx,…) — pixel offset within that element
#
# We look up the matching SegCoord in char_to_coord, convert the pixel
# x-offset to a character position using _char_position_at_x, and return
# a fresh ReplaceSelectionOperation on the flat PositionReference domain.
function _translate_click(p::TextToGraphics, iomap::TextToGraphicsIoMap, path)
    path isa ConcreteReferencePath || return nothing
    h1 = head(path)
    h1 isa RangeReference || return nothing
    i  = h1.start + 1
    rest = tail(path)
    rest isa ConcreteReferencePath || return nothing
    h2 = head(rest)
    h2 isa PointReference || return nothing
    rx = h2.x::Int
    coord_map = iomap.char_to_coord[]
    i > length(coord_map) && return nothing
    seg = coord_map[i]
    char_pos = _char_position_at_x(seg, seg.x + rx, p.measure)
    return ReplaceSelectionOperation(_build_selection_path(seg.span_idx, char_pos))
end

end # module
