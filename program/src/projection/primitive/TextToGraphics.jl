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
import ..TextModule: TextText, TextString, TextNewline, TextGraphics, TextDocument
import ..GraphicsModule: GraphicsText, GraphicsRect, GraphicsImage, GraphicsCanvas, layout_none, layout_vertical
import ..ImageModule: ImageDocument
import ..FontModule: StyleFont, font_scaled_size
import ..ColorModule: StyleColor
import ..ReferenceModule: ReferencePath, ConcreteReferencePath, ElementReference, PositionReference, RangeReference, PointReference, EmptyReferencePath, FieldReference, TextRectangularReference, head, tail
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..KeyboardModule: KeyDown, KeyPress
import ..MouseModule: MousePress
import ..IoMapApiModule: IoMap
export TextToGraphics, TextToGraphicsIoMap

"""
    SegCoord(span_idx, char_start, char_end, x, y, font, text, width, height)

One entry per emitted text segment. `span_idx` is the 1-based index of the
`TextString` element in the input `TextText`. `char_start`/`char_end` are
0-based offsets local to that span (exclusive end). `(x, y)` are pixel
coordinates of the segment's top-left. `width`/`height` are the segment's
pixel box; for an inline image span (`TextGraphics` — empty `text`, range
`[0, 1)`) they carry the image size so hit-testing splits on the real
left/right halves, the cursor sits at `x + width`, and the clickable y-band
covers the whole image.
"""
struct SegCoord
    span_idx::Int
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
    input::TextText
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

function projection_read(p::TextToGraphics, iomap::TextToGraphicsIoMap, op::ReplaceSelectionOperation)
    return _translate_click(p, iomap, op.path)
end

# KeyPress producer: emit a StringReplaceRangeOperation against the input
# TextText's `.elements[i].content[range]` shape. The selection must already
# carry the same shape (i.e. the cursor is positioned inside a TextString
# span); other shapes return `nothing` so upstream projections still get a
# chance.
function projection_read(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::KeyPress)
    evt.modifiers.ctrl && return nothing
    rng = _text_selection_range(iomap.input)
    rng === nothing && return nothing
    span_idx, char_start, char_stop = rng
    new_ref = _text_replace_path(span_idx, char_start, char_stop)
    StringReplaceRangeOperation(new_ref, evt.text)
end

# KeyDown handler for Backspace / Delete. Emits a `StringReplaceRangeOperation`
# against the input TextText's `.elements[i].content[range]` shape; other keys
# fall through to the navigation method below (`projection_read(..., evt)`).
function _key_delete_op(iomap::TextToGraphicsIoMap, evt::KeyDown)
    (evt.key == :backspace || evt.key == :delete) || return nothing
    rng = _text_selection_range(iomap.input)
    rng === nothing && return nothing
    span_idx, char_start, char_stop = rng
    content = _span_content(iomap.input, span_idx)
    content === nothing && return nothing
    n = length(content)
    new_range = if evt.key == :backspace
        if char_start != char_stop
            (char_start, char_stop)
        elseif char_start > 0
            (char_start - 1, char_start)
        else
            return nothing
        end
    else  # :delete
        if char_start != char_stop
            (char_start, char_stop)
        elseif char_stop < n
            (char_stop, char_stop + 1)
        else
            return nothing
        end
    end
    new_ref = _text_replace_path(span_idx, new_range[1], new_range[2])
    StringReplaceRangeOperation(new_ref, "")
end

# Extract the i-th span's content length when it's a TextString; nothing
# otherwise.
function _span_content(styled::TextText, span_idx::Int)
    elements = styled.elements
    (span_idx < 1 || span_idx > length(elements)) && return nothing
    span = elements[span_idx]
    span isa TextString || return nothing
    span.content::AbstractString
end

# Parse `styled.selection[]` into (span_idx, char_start, char_stop) when it
# matches `.elements[i].content[s:e]`, else return nothing.
function _text_selection_range(styled::TextText)
    sel = styled.selection
    sel isa ConcreteReferencePath || return nothing
    h1 = sel.head
    (h1 isa FieldReference && h1.name == "elements") || return nothing
    t1 = sel.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return nothing
    h3 = t2.head
    (h3 isa FieldReference && h3.name == "content") || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return nothing
    h4 = t3.head
    h4 isa RangeReference || return nothing
    (span_idx, h4.start::Int, h4.stop::Int)
end

function _text_replace_path(span_idx::Int, char_start::Int, char_stop::Int)
    ConcreteReferencePath(FieldReference("elements"),
        ConcreteReferencePath(RangeReference(span_idx - 1, span_idx),
            ConcreteReferencePath(FieldReference("content"),
                ConcreteReferencePath(RangeReference(char_start, char_stop), EmptyReferencePath()))))
end

# Raw MousePress directly on the canvas (no GraphicsCanvasToGraphicsImage
# step above us). Translate to a text-domain selection by picking the
# segment that owns the click and the character offset within it.
function projection_read(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::MousePress)
    evt.button === :left || return nothing
    coord_map = iomap.char_to_coord[]
    isempty(coord_map) && return nothing
    sc = _hit_segment(coord_map, evt.x, evt.y)
    sc === nothing && return nothing
    if evt.modifiers.alt
        return ReplaceSelectionOperation(_build_tree_selection_path(sc.span_idx), true)
    end
    char_pos = _char_position_at_x(sc, evt.x, p.measure)
    return ReplaceSelectionOperation(_build_selection_path(sc.span_idx, char_pos), true)
end

function projection_read(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt)
    evt isa KeyDown || return nothing
    # Fold chord: Ctrl+. toggles collapse of the innermost node containing the
    # cursor. The empty-target operation is resolved upstream at the syntax
    # layer (where the tree and selection live); we only recognise the chord.
    if evt.key === :period && evt.modifiers.ctrl
        return ToggleCollapseOperation()
    end
    # Alt-modified navigation keys (arrows, Home) are tree-navigation gestures.
    # This layer handles only character/line cursor motion within flat text, so
    # decline them: returning nothing lets the raw event fall through the chain
    # to SyntaxNodeToText, which owns the tree structure and resolves them.
    if evt.modifiers.alt && evt.key in (:up, :down, :left, :right, :home)
        return nothing
    end
    del_op = _key_delete_op(iomap, evt)
    del_op === nothing || return del_op
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
function projection_print(p::TextToGraphics, recursion, styled::TextText, ctx)
    # ListNode path: lazy paragraph-level mapping
    if styled.elements isa ListNode
        return _print_listnode(p, styled, ctx)
    end
    both = Cell(function ()
        result = Any[]
        coord_map = SegCoord[]
        span_flat_offsets = Dict{Int,Int}()  # elem_idx → cumulative flat char offset
        cumulative_flat = 0
        cx = p.start_x
        cy = p.start_y
        max_cx = cx
        line_h = 0

        cursor_pos = _cursor_position(styled.selection)
        cursor_x = -1
        cursor_y = -1
        cursor_line_h = 0

        for (elem_idx, span) in enumerate(styled)         # reads styled.elements cell
            span_flat_offsets[elem_idx] = cumulative_flat
            if span isa TextNewline
                cx = p.start_x
                cy += line_h
                line_h = 0
                continue
            end
            if span isa TextGraphics
                img_w = Int(span.width::Int32)
                img_h = Int(span.height::Int32)
                # Extract raw pixel data from the embedded ImageDocument
                img_data = _extract_image_data(span)
                push!(result, GraphicsImage(cx, cy, img_w, img_h, img_data))
                # Record a SegCoord for hit-testing: atomic position (0..1)
                push!(coord_map, SegCoord(elem_idx, 0, 1, cx, cy, span.font::StyleFont, "", img_w, img_h))
                cumulative_flat += 1  # image spans occupy 1 char in the flat space
                line_h = max(line_h, img_h)
                # Handle cursor at this image span
                if cursor_pos !== nothing && cursor_x < 0 &&
                   cursor_pos.span == elem_idx
                    if cursor_pos.char == 0
                        cursor_x = cx
                    else
                        cursor_x = cx + img_w
                    end
                    cursor_y = cy
                    cursor_line_h = line_h
                end
                cx += img_w
                continue
            end
            span isa TextString || continue
            span_idx = elem_idx                            # 1-based index in elements
            char_offset = 0                               # local offset within this span
            txt  = span.content::AbstractString             # reads span content cell
            cumulative_flat += length(txt)
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
                push!(coord_map, SegCoord(span_idx, seg_char_start, seg_char_start + seg_len, seg_x, cy, sf, line, seg_w, seg_h))
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

        # ── Highlight box for whole-element / rectangular selections ────────
        highlight_count = 0
        sel = styled.selection
        hl_range = _highlight_char_range(sel, coord_map)
        if hl_range !== nothing
            hl_start, hl_stop = hl_range
            hl_rect = _compute_highlight_rect(coord_map, span_flat_offsets, hl_start, hl_stop, p)
            if hl_rect !== nothing
                pushfirst!(result, hl_rect)
                highlight_count = 1
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
        return (result, coord_map, total_w, total_h, highlight_count)
    end)
    char_to_coord = Cell(() -> both[][2])
    highlight_offset = Cell(() -> both[][5])
    canvas_w = Cell(() -> Int32(both[][3]))
    canvas_h = Cell(() -> Int32(both[][4]))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), canvas_w, canvas_h, CellVector(() -> both[][1]), layout_none, false, Cell(nothing))
    TextToGraphicsIoMap(p, styled, canvas, char_to_coord, highlight_offset)
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

_build_tree_selection_path(span_idx::Int) =
    @reference elements[span_idx]

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

    # Adjust for highlight rects prepended before text segments
    hl_off = iomap.highlight_offset[]
    i -= hl_off
    coord_map = iomap.char_to_coord[]
    (i < 1 || i > length(coord_map)) && return nothing
    seg = coord_map[i]

    # Alt+click: element-only path (no PointReference) → tree selection
    if rest isa EmptyReferencePath
        return ReplaceSelectionOperation(_build_tree_selection_path(seg.span_idx), true)
    end

    rest isa ConcreteReferencePath || return nothing
    h2 = head(rest)
    h2 isa PointReference || return nothing
    rx = h2.x::Int
    char_pos = _char_position_at_x(seg, seg.x + rx, p.measure)
    return ReplaceSelectionOperation(_build_selection_path(seg.span_idx, char_pos), true)
end

# Pick the segment a (canvas-x, canvas-y) click landed on. Matches the
# logic in GraphicsCanvasToGraphicsImage.projection_read for text elements:
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

Extract the flat character range for a box selection from the TextText's
selection. Recognized shapes:
- `EmptyReferencePath` (∅) → highlight the full extent `(0, N)` where N is
  the total character count across all segments.
- `ConcreteReferencePath(TextRectangularReference(s, e), ∅)` → `(s, e)`.
Returns `nothing` for any other selection shape (normal cursor, etc.).
"""
function _highlight_char_range(sel, coord_map::Vector{SegCoord})
    if sel isa EmptyReferencePath
        isempty(coord_map) && return nothing
        # Cover all segments: use a large sentinel that exceeds any absolute offset.
        return (0, typemax(Int) >> 1)
    end
    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    h isa TextRectangularReference || return nothing
    sel.tail isa EmptyReferencePath || return nothing
    return (h.start, h.stop)
end

"""
    _compute_highlight_rect(coord_map, hl_start, hl_stop, p) -> GraphicsRect or nothing

Compute the bounding box over all `SegCoord`s whose character range overlaps
`[hl_start, hl_stop)`. Returns a semi-transparent `GraphicsRect` with rounded
corners, or `nothing` when no segment overlaps the range.
"""
function _compute_highlight_rect(coord_map::Vector{SegCoord}, span_flat_offsets::Dict{Int,Int}, hl_start::Int, hl_stop::Int, p::TextToGraphics)
    x0, y0 = typemax(Int), typemax(Int)
    x1, y1 = 0, 0
    found = false
    for sc in coord_map
        base = get(span_flat_offsets, sc.span_idx, 0)
        abs_start = base + sc.char_start
        abs_end = base + sc.char_end
        # Check overlap with [hl_start, hl_stop)
        (abs_end <= hl_start || abs_start >= hl_stop) && continue
        # Compute the pixel sub-range within this segment that's highlighted
        seg_hl_start = max(hl_start, abs_start) - base
        seg_hl_end = min(hl_stop, abs_end) - base
        px_left = _seg_cursor_x(sc, seg_hl_start, p.measure)
        px_right = _seg_cursor_x(sc, seg_hl_end, p.measure)
        fs = font_scaled_size(sc.font.size)
        x0 = min(x0, px_left)
        y0 = min(y0, sc.y)
        x1 = max(x1, px_right)
        y1 = max(y1, sc.y + fs)
        found = true
    end
    found || return nothing
    w = x1 - x0
    h = y1 - y0
    (w <= 0 || h <= 0) && return nothing
    # Accent colour: a light blue with ~25% alpha
    GraphicsRect(x0, y0, w, h, 0x88, 0xbb, 0xee, 0x40, 4)
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
    _is_image_seg(sc::SegCoord) -> Bool

Returns true when the `SegCoord` represents an inline image (TextGraphics)
rather than a text segment. Image segments have empty text and span [0,1).
"""
_is_image_seg(sc::SegCoord) = isempty(sc.text) && sc.char_start == 0 && sc.char_end == 1

"""
    _seg_band_height(sc::SegCoord) -> Int

Vertical extent of a segment's clickable y-band. Text segments use the
scaled font size (unchanged); an inline image extends its band over the
whole image height so a click anywhere on a tall image still lands on it.
"""
_seg_band_height(sc::SegCoord) =
    _is_image_seg(sc) ? max(font_scaled_size(sc.font.size), sc.height) :
                        font_scaled_size(sc.font.size)

end # module
