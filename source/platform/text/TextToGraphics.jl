# Fragment of `TextModule`.
#
# Text → Graphics projection. Pure layout pass: arranges already-wrapped spans
# left-to-right and breaks the line at a `TextLine` element, at an explicit
# `TextNewline` element, or at an embedded `\\n` character. Word wrapping itself
# lives in `WordWrapping`, inserted upstream of `TextToGraphics` in the pipeline.
#
# A coordinate table in the IoMap records the character range and pixel
# position of each emitted segment. The reader uses it for keyboard navigation
# (arrow keys, home/end) and to translate downstream mouse-click selections
# into character positions.
#
# Text is measured by the mandatory `measure`, a `TextMeasure`: `FontFileMeasure()`
# in the application and the exports, as every backend draws, and a `FixedMeasure`
# in a test.
"""
    SegmentCoordinate(span_path, char_start, char_end, x, y, font, text, width, height)

One entry per emitted text segment. `span_path` is the segment's span as an index
path into the input `TextBlock` (a `SpanPath`): `[i]` for a top-level span, `[i, j]`
for span `j` of the `TextLine` at element `i`. `char_start`/`char_end` are
0-based offsets local to that span (exclusive end). `x` is the left edge of the
segment and `width` its width. `y` and `height` are the line box of the visual
line the segment is on: every segment of one line has the same `y`, and the
boxes of consecutive lines meet, so a click picks a line by its box and a
selection covers each line it spans without a gap. For an inline image span
(`TextGraphics` — empty `text`, range `[0, 1)`) `width` is the image width, so
hit-testing splits on the real left/right halves and the cursor sits at
`x + width`.
"""
struct SegmentCoordinate
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

IoMap for `TextToGraphics`. `char_to_coord` holds one `SegmentCoordinate` per emitted
text segment with character range, pixel position, font, and text.
"""
@iomap struct TextToGraphicsIoMap
    projection::Any
    input::TextBlock
    output::GraphicsCanvas
    char_to_coord::Cell  # Cell{Vector{SegmentCoordinate}}
    highlight_offset::Cell  # Cell{Int} — number of highlight rects prepended before text segments
    first_baseline::Cell    # Cell{Union{Int,Nothing}} — the baseline of the first line, from the top
    lines::Cell             # Cell{Vector} — the line groups (`_line_groups`)
    line_cells::Any         # L -> the cells of line group L (`layout`, `y`, `h`), or `nothing`
end

# The baseline of the first line of the text, for a row that aligns its children
# on their baselines.
find_first_baseline(iomap::TextToGraphicsIoMap) = unwrap_cell(iomap.first_baseline)

# ── Projection struct ──────────────────────────────────────────────────

# The style fields read the scaled `TextTheme` with no edge, or hold the plain
# values of the default theme; a change of the theme reaches a view when it prints
# again.
@projection UntrackedCell struct TextToGraphics
    start_x::Int
    start_y::Int
    measure::TextMeasure
    line_spacing::LineSpacing
    caret_color::StyleColor
    dormant_caret_color::StyleColor
    caret_width::Int
    highlight_color::StyleColor
    dormant_highlight_color::StyleColor
    highlight_radius::Int
end

"""
    TextToGraphics(; measure, theme = nothing, start_x = 0, start_y = 0,
                   line_spacing = SingleSpacing())

Draw a `TextBlock` as graphics, with its caret and the band under its selection.
`theme` is a `TextTheme`, scaled or not, whose caret and selection it draws; with
none, it draws those of the default theme, and builds no theme. `line_spacing` is
a `LineSpacing`, or a cell that reads one of the theme, such as its
`code_line_spacing` or `prose_line_spacing`; a builder of code or of prose passes
the one it draws, and a widget keeps single spacing. A container that sets the
spacing of the text inside it, as a table sets single spacing for its cells,
puts the property `:line_spacing` in the printer context, and the text draws at
that spacing in place of its own.
"""
function TextToGraphics(; start_x::Int=0, start_y::Int=0, measure::TextMeasure,
                        line_spacing = SingleSpacing(), theme = nothing)
    TextToGraphics(start_x, start_y, measure, line_spacing,
                   get_text_style(theme, :caret),
                   get_text_style(theme, :dormant_caret),
                   get_text_style(theme, :caret_width),
                   get_text_style(theme, :highlight),
                   get_text_style(theme, :dormant_highlight),
                   get_text_style(theme, :highlight_radius))
end

# `p` at the line spacing `spacing`, with the same cells for every other field, so
# the copy follows the theme as `p` does.
_with_line_spacing(p::TextToGraphics, spacing::LineSpacing) =
    TextToGraphics(getfield(p, :start_x), getfield(p, :start_y), getfield(p, :measure), spacing,
                   getfield(p, :caret_color), getfield(p, :dormant_caret_color),
                   getfield(p, :caret_width), getfield(p, :highlight_color),
                   getfield(p, :dormant_highlight_color), getfield(p, :highlight_radius))

# The x of the character boundary `position` of `text` in `font`, from the start
# of the text: the pen position where the character after it starts.
_get_caret_x(measure::TextMeasure, text::AbstractString, font::StyleFont, position::Int) =
    round(Int, compute_caret_offsets(measure, text, font)[position + 1])

# A text reference maps to the most specific reference of what draws it. A caret,
# and a range that one segment holds, map to that segment's text node followed by
# the characters in it: `…elements[k].text{a:b}`, where a caret is a range of no
# width. A range that covers several segments maps to the smallest node that
# holds all of its rows (the canvas of its line, or the stack of lines) followed
# by a `RegionReferenceStep`: the box of its rows, as its highlight draws them.
# The reference is a range of the caret space (a caret or a range of characters)
# or of the box space (a whole node), as `_highlight_char_range` reads them. The
# text node of a segment is found in the canvas of its line by its place and its
# text, because a line puts a fill before some texts, so the table of segments is
# not in step with the elements of a line.
function map_reference_forward(p::TextToGraphics, iomap, reference)
    iomap isa TextToGraphicsIoMap || return nothing
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa EmptyReference && return EmptyReference()
    if iomap.input.elements isa ListNode
        head = iomap.input.elements::ListNode
        return head.value isa TextLine ? _map_list_lines_forward(p, iomap, reference) :
                                         _map_list_text_forward(p, iomap, reference)
    end
    range = _find_text_forward_range(iomap.input, reference)
    range === nothing && return nothing
    start, stop, space = range
    box_bases, caret_bases = _compute_span_bases(iomap.input)
    bases = space === :caret ? caret_bases : box_bases
    for segment in unwrap_cell(iomap.char_to_coord)
        isempty(segment.text) && continue
        base = get(bases, segment.span_path, nothing)
        base === nothing && continue
        if start == stop
            (segment.char_start <= start - base <= segment.char_end) || continue
            a = b = start - base
        else
            a = max(start, base + segment.char_start) - base
            b = min(stop, base + segment.char_end) - base
            (a < b && !_hl_piece_blank(segment, a, b)) || continue
        end
        start == stop || (base + segment.char_start <= start && stop <= base + segment.char_end) ||
            return _map_text_region(p, iomap, bases, start, stop)
        node = _find_segment_node(iomap, segment)
        node === nothing && return nothing
        return concat_references(node,
            ConcreteReference(FieldReferenceStep("text"),
                ConcreteReference(RangeReferenceStep(a - segment.char_start, b - segment.char_start),
                                  EmptyReference())))
    end
    nothing
end

# The region of the rows of the range `start:stop` (see `_compute_span_rows`),
# after the smallest node that holds them: the canvas of their line, when one line
# holds all of them, and else the stack of lines. The rows are in the frame of the
# stack; a line starts where the one after it ends.
function _map_text_region(p::TextToGraphics, iomap::TextToGraphicsIoMap, bases, start::Int, stop::Int)
    rows = _compute_span_rows(unwrap_cell(iomap.char_to_coord), bases, start, stop, p)
    isempty(rows) && return nothing
    left = minimum(row[1] for row in rows)
    top = minimum(row[2] for row in rows)
    right = maximum(row[1] + row[3] for row in rows)
    bottom = maximum(row[2] + row[4] for row in rows)
    stack = ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(1, 2),
                                                                                 EmptyReference()))
    top_elements = unwrap_cell(getfield(unwrap_cell(iomap.output), :elements))
    lines = length(top_elements) >= 2 ? unwrap_cell(getfield(unwrap_cell(top_elements[2]), :elements)) : nothing
    if lines isa CellVector
        starts = Int[Int(unwrap_cell(getfield(unwrap_cell(lines[k]), :y))) for k in 1:length(lines)]
        line = findlast(y -> y <= top, starts)
        if line !== nothing && (line == length(starts) || bottom <= starts[line + 1])
            line_top = starts[line]
            return concat_references(stack,
                ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(RangeReferenceStep(line - 1, line),
                        ConcreteReference(RegionReferenceStep(left, top - line_top, right - left, bottom - top),
                                          EmptyReference()))))
        end
    end
    concat_references(stack, ConcreteReference(RegionReferenceStep(left, top, right - left, bottom - top),
                                               EmptyReference()))
end

# The range of a text reference, `(start, stop, space)`: a caret or a range of
# characters in the caret space, or a whole node in the box space.
function _find_text_forward_range(text::TextBlock, reference)
    if reference isa ConcreteReference && reference.head isa TextSpanReferenceStep &&
       reference.tail isa EmptyReference
        return (reference.head.start, reference.head.stop, :box)
    end
    flat = _text_flat_selection(text, reference)
    flat === nothing ? nothing : (flat[1], flat[2], :caret)
end

# The reference of the text node that draws `segment`: the canvas of each line
# is in the stack of lines, the second element of the text's canvas, and the node
# is the text of the segment at its place in that line.
function _find_segment_node(iomap::TextToGraphicsIoMap, segment::SegmentCoordinate)
    top = unwrap_cell(getfield(unwrap_cell(iomap.output), :elements))
    length(top) >= 2 || return nothing
    stack = unwrap_cell(top[2])
    stack isa GraphicsCanvas || return nothing
    lines = unwrap_cell(getfield(stack, :elements))
    lines isa CellVector || return nothing
    for line_index in 1:length(lines)
        line = unwrap_cell(lines[line_index])
        line isa GraphicsCanvas || continue
        top_of_line = segment.y - Int(unwrap_cell(getfield(line, :y)))
        elements = unwrap_cell(getfield(line, :elements))
        for k in 1:length(elements)
            node = unwrap_cell(elements[k])
            node isa GraphicsText || continue
            Int(unwrap_cell(getfield(node, :x))) == segment.x || continue
            String(unwrap_cell(getfield(node, :text))) == segment.text || continue
            (top_of_line <= Int(unwrap_cell(getfield(node, :y))) < top_of_line + segment.height) || continue
            return ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(1, 2),
                ConcreteReference(FieldReferenceStep("elements"),
                    ConcreteReference(RangeReferenceStep(line_index - 1, line_index),
                        ConcreteReference(FieldReferenceStep("elements"),
                            ConcreteReference(RangeReferenceStep(k - 1, k), EmptyReference()))))))
        end
    end
    nothing
end

# A point of the canvas maps to the caret nearest to it: the segment on the band
# of the point's line, or of the nearest line, and the character boundary nearest
# to its x. The path of an element and a point inside it, which the graphics leaf
# answers for a click on a rasterized canvas, maps to the caret in that element.
# The reader of a click and the reader of that path read this map.
function map_reference_backward(p::TextToGraphics, iomap, reference)
    iomap isa TextToGraphicsIoMap || return nothing
    point = find_reference_point(reference)
    point === nothing || return _find_caret_at_point(p, iomap, point.x, point.y)
    _find_caret_at_element_point(p, iomap, reference)
end

function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# KeyPress producer: the character-insert mapping is geometry-free, so it lives
# on the Text domain (`read_gesture(::TextBlock, ::KeyPress)` in `TextModule`).
# Delegate to it; the operation it produces (a `ReplaceStringRangeOperation`
# against `.elements[i].content[range]`) flows back through the chain unchanged.
# Text-domain gesture, with any flat edit op lowered to the structural single-span
# form over the input block (== the outermost text stage's output), so the existing
# `ReplaceStringRangeOperation` chain carries it up. A declined (cross-span) edit
# lowers to `nothing`, so the caller lets the gesture propagate.
_gesture_op(iomap::TextToGraphicsIoMap, evt) = _read_lowered_gesture(iomap.input, evt)

function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::KeyPress)
    return _gesture_op(iomap, evt)
end

# The flat caret at `char` in the span at `span_path`, or `nothing` when the span
# has no flat base. The graphics layer resolves clicks and line motion to a
# `(span, char)` hit; this converts it to the canonical flat selection
# (`get_flat_base + char`).
function _find_flat_caret(text::TextBlock, span_path::SpanPath, char::Int)
    base = get_flat_base(text, span_path)
    base === nothing ? nothing : make_flat_caret_reference(base + char)
end

# A `ReplaceSelectionOperation` selecting that caret, or `nothing`.
function _flat_hit_op(text::TextBlock, span_path::SpanPath, char::Int)
    caret = _find_flat_caret(text, span_path, char)
    caret === nothing ? nothing : ReplaceSelectionOperation(caret)
end

# What a selection cell holds, past the live/dormant wrapper, and whether it is
# the live one. Only the painters need this: everything else reads the property,
# which answers a live path or `nothing`.
_get_stored_path(value) = value
_get_stored_path(value::SelectionDocument) = value.primary
_is_live_selection(value) = true
_is_live_selection(value::SelectionDocument) = value.live

# Raw MouseClick directly on the canvas (no GraphicsCanvasToGraphicsImage
# step above us): the caret at the point of the click. A click always becomes a
# plain character cursor; whole-element promotion (Alt+click) is decided in
# SyntaxToText, where the tree is in hand.
function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::MouseClick)
    evt.button === :left || return nothing
    path = map_reference_backward(p, iomap, PointReferenceStep(evt.x, evt.y))
    path === nothing ? nothing : ReplaceSelectionOperation(path)
end

# The caret at `(x, y)`: the segment that owns the point, and the character
# offset within it.
function _find_caret_at_point(p::TextToGraphics, iomap::TextToGraphicsIoMap, x::Int, y::Int)
    coord_map = iomap.char_to_coord
    isempty(coord_map) && return nothing
    sc = _hit_segment(coord_map, x, y)
    sc === nothing && return nothing
    _find_flat_caret(iomap.input, sc.span_path, _char_position_at_x(sc, x, p.measure))
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
    declined = @gesture_case evt begin
        when(KeyDown(k), evt.modifiers.alt && k in (:up, :down, :left, :right, :home)) => :decline
        when(KeyDown(k), k in (:up, :down, :left, :right) &&
                         is_structural_selection(iomap.input.selection)) => :decline
        KeyDown(:tab) => :decline
    end
    declined === nothing || return nothing

    styled = iomap.input
    # A block whose elements are a list is drawn paragraph by paragraph and keeps
    # no line geometry, so no key moves along its lines. The list can be endless,
    # so it is not walked either.
    styled.elements isa ListNode && return nothing
    _has_caret_span(styled) || return nothing

    # Shift moves one end of the selection: Home and Up the start, End and Down
    # the stop, as the geometry-free Shift keys of the text domain do.
    extend = evt.modifiers.shift && !evt.modifiers.ctrl
    pair = extend ? _text_flat_selection(styled) : nothing
    current = if extend
        pair === nothing && return nothing
        moving = _text_flat_span(styled, (evt.key === :home || evt.key === :up) ? pair[1] : pair[2])
        moving === nothing && return nothing
        moving
    else
        get_flat_cursor_coordinate(styled)
    end
    current === nothing && return nothing

    target = @gesture_case evt begin
        when(KeyDown(k), k === :home || k === :end) => begin
            coord_map = iomap.char_to_coord
            isempty(coord_map) && return nothing
            seg_idx = findfirst(sc -> sc.span_path == current.span && sc.char_start <= current.char <= sc.char_end, coord_map)
            seg_idx === nothing && return nothing
            current_y = coord_map[seg_idx].y
            line_segs = filter(sc -> sc.y == current_y, coord_map)
            sc = k === :home ? line_segs[1] : line_segs[end]
            new_char = k === :home ? sc.char_start : sc.char_end
            (sc.span_path, new_char)
        end
        when(KeyDown(k), k === :up || k === :down) => begin
            coord_map = iomap.char_to_coord
            isempty(coord_map) && return nothing
            seg_idx = findfirst(sc -> sc.span_path == current.span && sc.char_start <= current.char <= sc.char_end, coord_map)
            seg_idx === nothing && return nothing
            cur_sc   = coord_map[seg_idx]
            cursor_x = _seg_cursor_x(cur_sc, current.char, p.measure)
            current_y = cur_sc.y
            target_segs = if k === :up
                ys = [sc.y for sc in coord_map if sc.y < current_y]
                isempty(ys) ? SegmentCoordinate[] : filter(sc -> sc.y == maximum(ys), coord_map)
            else
                ys = [sc.y for sc in coord_map if sc.y > current_y]
                isempty(ys) ? SegmentCoordinate[] : filter(sc -> sc.y == minimum(ys), coord_map)
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
            (best_sc.span_path, best_pos)
        end
    end
    target === nothing && return nothing
    extend || return _flat_hit_op(styled, target...)
    base = get_flat_base(styled, target[1])
    base === nothing && return nothing
    f = base + target[2]
    s, e = (evt.key === :home || evt.key === :up) ? (min(f, pair[2]), pair[2]) :
                                                    (pair[1], max(f, pair[1]))
    return ReplaceSelectionOperation(make_flat_range_reference(s, e))
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
    # A container that sets the spacing of its text, such as a table for its
    # cells, says so in the context.
    spacing = ctx === nothing ? nothing : get_property(ctx, :line_spacing, nothing)
    spacing === nothing || (p = _with_line_spacing(p, spacing))
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
    block_font = Cell(@computation _block_font(styled))
    # The overlay is laid out from the **stored** selection, live or dormant, so a
    # dormant caret still has a place on the screen. `is_live` decides only how it
    # is painted. Reading the raw cell is what makes a dormant selection visible at
    # all: the property answers `nothing` for one, which is the default that keeps
    # every other reader correct.
    selection_cell = getfield(styled, :selection)
    overlay = Cell(@computation _layout_overlay(p, styled, _get_stored_path(selection_cell[]), block_font))
    is_live = Cell(@computation _is_live_selection(selection_cell[]))

    # Persistent overlay elements. Their geometry cells read the selection-
    # dependent `overlay`; a zero width hides them when inactive (the renderer
    # skips a zero-width rect, and the bounds machinery ignores it).
    caret_color = p.caret_color
    dormant_caret_color = p.dormant_caret_color
    caret_width = Int32(p.caret_width)
    cursor_rect = GraphicsRect(0, 0, 0, 0; color = caret_color)
    # A dormant caret is drawn muted: the pane it belongs to still remembers where
    # the caret is, and shows it, but the keyboard is not on it.
    set_cell_computation!(getfield(cursor_rect, :color),
                       () -> is_live[] ? caret_color : dormant_caret_color)
    set_cell_computation!(getfield(cursor_rect, :x), () -> (g = overlay[].cursor; g === nothing ? Int32(0) : Int32(g[1])))
    set_cell_computation!(getfield(cursor_rect, :y), () -> (g = overlay[].cursor; g === nothing ? Int32(0) : Int32(g[2])))
    set_cell_computation!(getfield(cursor_rect, :w), () -> overlay[].cursor === nothing ? Int32(0) : caret_width)
    set_cell_computation!(getfield(cursor_rect, :h), () -> (g = overlay[].cursor; g === nothing ? Int32(0) : Int32(max(g[3], 1))))

    # A structural selection hugs its content per visual row (see `_compute_span_rows`),
    # so the highlight is a *vector* of rects, not one box. They live in their own
    # sub-canvas (a single top-canvas slot, below), each a persistent `GraphicsRect`
    # keyed by row index and reused across re-layouts; the k-th reads `overlay`'s k-th
    # rect (a zero width hides a rect whose row no longer exists, matching the cursor).
    hl_color = p.highlight_color
    hl_color_dormant = p.dormant_highlight_color
    hl_radius = p.highlight_radius
    hl_cache = Dict{Int,GraphicsRect}()
    _hl_geo(k) = (v = overlay[].highlight; 1 <= k <= length(v) ? v[k] : nothing)
    function get_highlight_rect(k::Int)
        haskey(hl_cache, k) && return hl_cache[k]
        r = GraphicsRect(0, 0, 0, 0; color = hl_color, radius = hl_radius)
        set_cell_computation!(getfield(r, :color), () -> is_live[] ? hl_color : hl_color_dormant)
        set_cell_computation!(getfield(r, :x), () -> (g = _hl_geo(k); g === nothing ? Int32(0) : Int32(g[1])))
        set_cell_computation!(getfield(r, :y), () -> (g = _hl_geo(k); g === nothing ? Int32(0) : Int32(g[2])))
        set_cell_computation!(getfield(r, :w), () -> (g = _hl_geo(k); g === nothing ? Int32(0) : Int32(g[3])))
        set_cell_computation!(getfield(r, :h), () -> (g = _hl_geo(k); g === nothing ? Int32(0) : Int32(g[4])))
        hl_cache[k] = r
        r
    end
    # Membership reads only the highlight-rect *count* (a caret / no selection → 0),
    # so a caret move that keeps the same row count reuses the exact rects. Evict rows
    # that no longer exist so the cache cannot grow unbounded across selections.
    highlight_elements = CellVector(Computation(function ()
        n = length(overlay[].highlight)
        out = Any[get_highlight_rect(k) for k in 1:n]
        for k in collect(keys(hl_cache)); k <= n || delete!(hl_cache, k); end
        out
    end))
    highlight_canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                                      highlight_elements, layout_none, false, Cell(nothing))

    # The block resolved into visual lines (see `_line_groups`). Reads only the
    # element structure, the element types and a line's indentation — never a span's
    # `.content` — so it is invariant under content edits.
    lines_cell = Cell(@computation _line_groups(styled))

    # The `TextLine` of each group, when the group holds the spans of that line only,
    # and the place in the stack of each such line.
    group_lines = Cell(Computation(() -> Any[_find_group_line(styled, group) for group in lines_cell[]]))
    line_places = Cell(Computation(function ()
        places = IdDict{Any,Int}()
        for (L, line) in enumerate(group_lines[])
            line === nothing || (places[line] = L)
        end
        places
    end))

    # Per-line reactive cells, built once and reused. A `TextLine` keeps its cells
    # while it stays in the block, at any place, so a line inserted above it lays out
    # nothing of it again and keeps its graphics; a group that is no line keeps its
    # cells by its place. A line's `layout` reads only that line's spans' content;
    # its `y` reads the offset of its place, which chains off the real line distances
    # of the places above, rounded once, so a long text does not drift (editing the
    # last line moves nothing; editing a middle line reflows the lines below —
    # matching ListNode spines).
    # Each placement becomes a PERSISTENT GraphicsText/GraphicsRect reused across
    # re-layouts, its fields `set_cell_computation!` cells reading the placement back out of the
    # line's `layout` (printer locality — dimension C, now line-local).
    line_entries = IdDict{Any,NamedTuple}()
    place_entries = Dict{Int,NamedTuple}()
    offsets = Dict{Int,Cell}()
    function get_offset(L::Int)
        get!(offsets, L) do
            L == 1 ? Cell(0.0) : Cell(@computation get_offset(L - 1)[] + get_line_cells(L - 1).distance[])
        end
    end
    function make_line_entry(line_layout::Cell, line_y::Cell)
        line_h = Cell(@computation Int32(line_layout[].height))
        line_distance = Cell(@computation line_layout[].distance)
        cache = Dict{Any,Any}()
        segs = CellVector(Computation(function ()
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
        end))
        sub = GraphicsCanvas(Cell(Int32(0)), line_y, Cell(Int32(0)), Cell(Int32(0)),
                             segs, layout_none, false, Cell(nothing))
        (layout = line_layout, h = line_h, distance = line_distance, y = line_y, canvas = sub)
    end
    # The cells of the line `line`, wherever it stands.
    function get_line_cells(line::TextLine)
        get!(line_entries, line) do
            line_layout = Cell(@computation _layout_group(p, _make_line_group(line), 0, nothing, true, block_font))
            line_y = Cell(Computation(function ()
                L = get(line_places[], line, nothing)
                L === nothing ? Int32(0) : Int32(round(Int, get_offset(L)[]))
            end))
            make_line_entry(line_layout, line_y)
        end
    end
    # The cells of the group at place `L`.
    function get_line_cells(L::Int)
        line = group_lines[][L]
        line === nothing || return get_line_cells(line::TextLine)
        get!(place_entries, L) do
            line_layout = Cell(@computation _layout_group(p, lines_cell[][L], 0, nothing, true, block_font))
            make_line_entry(line_layout, Cell(@computation Int32(round(Int, get_offset(L)[]))))
        end
    end

    # Vertical stack of line sub-canvases. Its membership reads only `lines_cell`
    # (structure); `get_line_cells` builds/looks up cells without forcing them, so
    # no content is read here and the stack stays up to date across content edits.
    # The cells of a line that left the block, and of a place that holds a line now
    # or no group, go.
    # `layout_vertical` + non-overlapping lets the dirty walk and renderer
    # early-stop past off-screen lines.
    lines_stack_elements = CellVector(Computation(function ()
        n = length(lines_cell[])
        out = Any[get_line_cells(L).canvas for L in 1:n]
        places = line_places[]
        for line in collect(keys(line_entries))
            haskey(places, line) || delete!(line_entries, line)
        end
        lines = group_lines[]
        for L in collect(keys(place_entries))
            (L <= n && lines[L] === nothing) || delete!(place_entries, L)
        end
        out
    end))
    lines_stack = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(0)),
                                 lines_stack_elements, layout_vertical, false, Cell(nothing))

    # coord_map (reader-only — not in the rendered tree) assembled from the per-line
    # layouts, shifted into absolute coordinates by each line's y-offset so clicks
    # and key-navigation see exactly the same SegCoords as before.
    char_to_coord = Cell(Computation(function ()
        out = SegmentCoordinate[]
        n = length(lines_cell[])
        for L in 1:n
            lc = get_line_cells(L)
            ly = Int(lc.y[])
            # The layout of a line names its spans `[1, j]`; here they get the index of
            # the line in the block.
            index = group_lines[][L] === nothing ? nothing : lines_cell[][L].line
            for sc in lc.layout[].coord_map
                path = index === nothing ? sc.span_path : Int[index, sc.span_path[2]]
                push!(out, SegmentCoordinate(path, sc.char_start, sc.char_end,
                                    sc.x, sc.y + ly, sc.font, sc.text, sc.width, sc.height))
            end
        end
        out
    end))
    # `highlight_offset` keeps its value of 1 — the rasterized-image click path
    # (`_find_caret_at_element_point`) indexes the coord_map past the single
    # leading highlight element (the highlight sub-canvas, holding the per-row
    # rects).
    # That path is only reached when a *leaf* canvas is rasterized by
    # GraphicsCanvasToGraphicsImage; this canvas is non-leaf (it nests the highlight
    # and line sub-canvases), so the bare text examples use the MouseClick/coord_map
    # reader instead, but the value is preserved for the rasterized-image path.
    highlight_offset = Cell(1)
    canvas_w = Cell(Computation(function ()
        w = 0
        for L in 1:length(lines_cell[])
            w = max(w, get_line_cells(L).layout[].width)
        end
        Int32(w)
    end))
    canvas_h = Cell(Computation(function ()
        n = length(lines_cell[])
        n == 0 ? Int32(0) : (lc = get_line_cells(n); Int32(lc.y[] + lc.h[]))
    end))
    # Top canvas: the line stack with the selection-driven caret/highlight overlays
    # floating above it in absolute coordinates. A fixed vector, so its membership
    # never regenerates — the highlight's per-selection churn is confined to the
    # highlight sub-canvas's own element vector. A left click on the text puts the
    # caret at the point, so the last element is an I-beam over the box of the
    # lines.
    ibeam = GraphicsPointerShape(0, 0, () -> canvas_w[], () -> canvas_h[], :ibeam)
    # A span that names a pointer shape, such as a link with the hand, has a region
    # of its shape over each of its segments, after the I-beam, so it wins there.
    # A text with no such span reads no segment for it.
    span_shapes = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), canvas_w, canvas_h,
                                 CellVector(Computation(() -> _make_span_shape_regions(styled, char_to_coord))),
                                 layout_none, true, Cell(nothing))
    top_elements = CellVector(Cell[Cell(highlight_canvas), Cell(lines_stack), Cell(cursor_rect),
                                   Cell(ibeam), Cell(span_shapes)])
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), canvas_w, canvas_h,
                            top_elements, layout_none, true, Cell(nothing))
    # The baseline of the first line: the one of the layout of the first line,
    # at the place of that line.
    first_baseline = Cell(Computation(function ()
        isempty(lines_cell[]) && return nothing
        first_line = get_line_cells(1)
        baseline = first_line.layout[].first_baseline
        baseline === nothing ? nothing : Int(first_line.y[]) + baseline
    end))
    TextToGraphicsIoMap(p, styled, canvas, char_to_coord, highlight_offset, first_baseline,
                        lines_cell, get_line_cells)
end

# The pointer regions of the spans of `text` that name a shape: one over each
# segment that the coordinates in `coordinates` place.
function _make_span_shape_regions(text::TextBlock, coordinates)
    _has_span_shape(text) || return Any[]
    regions = Any[]
    for segment in coordinates[]
        span = _find_segment_span(text, segment.span_path)
        shape = span isa TextString ? span.pointer_shape : nothing
        shape === nothing && continue
        push!(regions, GraphicsPointerShape(segment.x, segment.y, segment.width, segment.height, shape))
    end
    regions
end

_has_span_shape(text::TextBlock) =
    any(element -> element isa TextString ? element.pointer_shape !== nothing :
                   element isa TextLine && any(span -> span isa TextString && span.pointer_shape !== nothing,
                                                element.elements),
        text.elements)

function _find_segment_span(text::TextBlock, path::SpanPath)
    element = text.elements[path[1]]
    length(path) == 1 ? element : element.elements[path[2]]
end

# ── Line grouping ─────────────────────────────────────────────────────────────
#
# The block resolved into visual lines — the one grouping both layout passes read,
# so the rendered lines and the caret/highlight overlay can never disagree about
# where a span sits.
#
# A group is one visual line: the spans that render on it (each tagged with its
# `SpanPath`, so a span inside a `TextLine` addresses `[i, j]`), the `indentation`
# it opens with, the `TextNewline` element that terminates it (or `nothing`),
# whether an implicit line break precedes it, `line`, the index of the `TextLine`
# element that it lays out, or 0, and `soft_breaks`, the cell of the soft breaks of
# that line, or `nothing`. The cell is not read here: the layout of the line reads
# it, so a new wrap lays out only its line.
#
# Lines arrive by two mechanisms and the grouping honours both:
#   • a `TextNewline` *element* terminates the current line;
#   • a `TextLine` element carries a line of its own and implies a break *before*
#     itself unless it leads the block — the separator rule of `get_flat_offsets`
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
    line = 0
    soft_breaks = nothing
    for (i, element) in enumerate(styled.elements)
        if element isa TextNewline
            push!(groups, (spans = spans, newline = element, indentation = indentation,
                           break_before = break_before, is_line = is_line, line = line,
                           soft_breaks = soft_breaks))
            spans = Tuple{SpanPath,Any}[]
            indentation = 0
            break_before = false
            is_line = false
            line = 0
            soft_breaks = nothing
        elseif element isa TextLine
            if i > 1
                push!(groups, (spans = spans, newline = nothing, indentation = indentation,
                               break_before = break_before, is_line = is_line, line = line,
                               soft_breaks = soft_breaks))
                spans = Tuple{SpanPath,Any}[]
            end
            indentation = element.indentation
            break_before = i > 1
            is_line = true
            line = i
            soft_breaks = getfield(element, :soft_breaks)
            for (j, span) in enumerate(element.elements)
                push!(spans, (Int[i, j], span))
            end
        else
            push!(spans, (Int[i], element))
        end
    end
    push!(groups, (spans = spans, newline = nothing, indentation = indentation,
                   break_before = break_before, is_line = is_line, line = line,
                   soft_breaks = soft_breaks))
    groups
end

# The `TextLine` that `group` lays out, when the group holds the spans of that line
# only, or `nothing`.
function _find_group_line(styled::TextBlock, group)
    (group.is_line && group.line > 0) || return nothing
    all(entry -> length(entry[1]) == 2, group.spans) || return nothing
    line = styled.elements[group.line]
    line isa TextLine ? line : nothing
end

# ── Layout engine (wrap-free) ─────────────────────────────────────────────────

# Lay one line group's spans out, with `y0` as the vertical origin. The single span
# loop both passes run: a line's reactive sub-canvas calls it line-relative
# (`y0 = 0`, `collect_spans = true`) and with no caret; the overlay calls it once
# per group with the running absolute y and the caret to locate (`collect_spans =
# false` — it needs the geometry, not the glyphs). Sharing the loop is what keeps
# the caret on the character it was placed against.
#
# A group is one visual line, or more when a span embeds '\n' or the line has soft
# breaks. A soft break starts a row at the indentation of the line, and a caret at
# a soft break stands at the start of the lower row. Each visual line
# is set as a word processor sets a line: every box on it sits on one baseline,
# its height comes from the largest ascent, descent and line gap of its boxes,
# and `p.line_spacing` sets the distance to the next line. A piece of a line
# waits until the line closes, because its baseline needs every box of the line.
#
# `cursor_pos` is a `(span::SpanPath, char)` caret, or `nothing`. The returned
# `cursor` is `(x, y, h)` when it fell inside this group: it stands on the
# baseline and is as high as the font at its place. `distance` is the real sum of
# the line distances of the group, where the next group starts, and `height`
# reaches the lowest ink of the group.
function _layout_group(p::TextToGraphics, group, y0::Int, cursor_pos,
                       collect_spans::Bool, block_font::Cell)
    start_x = p.start_x + _indent_width(p, group, block_font)
    g = _GroupLayout(y0, start_x)
    occ = Dict{UInt64,Int}()   # per-span occurrence counter so a shared decorative
                               # span (one TextString at several flat positions)
                               # gets a distinct stable key per occurrence.
    last_font = nothing        # the font of the last text span: it sizes an empty last line
    is_caret_at(path, k) = cursor_pos !== nothing && g.cursor === nothing && g.caret === nothing &&
                           cursor_pos.span == path && cursor_pos.char == k
    soft_breaks = group.soft_breaks === nothing ? Int[] : group.soft_breaks[]::Vector{Int}
    line_offset = 0            # the offset in the text of the spans of the group
    pending_caret = nothing    # the font of a caret that waits for the next row
    # Close the open row at a soft break and start the next at the indentation,
    # with the caret that waits for it.
    function break_row!(font)
        _close_line!(g, p, font, true, collect_spans)
        g.pen = Float64(start_x)
        if pending_caret !== nothing && g.cursor === nothing
            g.caret = (round(Int, g.pen), pending_caret)
        end
        pending_caret = nothing
    end

    for (index, (path, span)) in enumerate(group.spans)
        span_base = line_offset
        line_offset += get_flat_length(span)
        if span isa TextGraphics
            span_base in soft_breaks && !isempty(g.boxes) && break_row!(last_font)
            width = Int(span.width::Int32)
            height = Int(span.height::Int32)
            x = round(Int, g.pen)
            # An inline image sits on the baseline, as a picture in line with text
            # does: its ascent is its height.
            push!(g.boxes, FontMetrics(height, 0, 0))
            font = _get_image_caret_font(group, index, block_font)
            push!(g.pieces, (kind = :image, path = path, span = span, x = x, width = width, height = height,
                             font = font))
            if cursor_pos !== nothing && g.cursor === nothing && g.caret === nothing && cursor_pos.span == path
                # The caret sits before or after the image, never inside it.
                g.caret = (cursor_pos.char == 0 ? x : x + width, font)
            end
            g.pen += width
            g.max_x = max(g.max_x, round(Int, g.pen))
            continue
        end
        span isa TextString || continue
        span_oid = objectid(span)
        span_occ = (occ[span_oid] = get(occ, span_oid, 0) + 1)
        char_offset = 0                                 # local offset within this span
        txt = span.content::AbstractString               # reads span content cell
        sf  = span.font::StyleFont                       # reads span font cell
        col = span.font_color::StyleColor                # reads span font_color cell
        last_font = sf

        for (li, line) in enumerate(split(txt, '\n'))
            # Hard newline embedded in the span content.
            if li > 1
                # caret BEFORE the '\n' (char_offset still points at it)
                is_caret_at(path, char_offset) && (g.caret = (round(Int, g.pen), sf))
                # A line with no glyph yet takes the height of the span's font.
                _close_line!(g, p, sf, true, collect_spans)
                g.pen = Float64(p.start_x)
                char_offset += 1           # count the '\n'
                # caret AFTER the '\n' — now at the start of the next line
                is_caret_at(path, char_offset) && (g.caret = (round(Int, g.pen), sf))
            end

            # An empty first sub-line is an empty span, or one that starts with
            # '\n'. A caret at its start has no glyph to stand against, so it
            # takes the font of the span.
            if isempty(line)
                li == 1 && is_caret_at(path, char_offset) && (g.caret = (round(Int, g.pen), sf))
                # An empty line draws no glyph, but it has a place: a zero-width
                # coordinate where a caret on it stands, so a key moves the caret
                # onto the line and off it. One on a line that draws a glyph is
                # dropped below.
                push!(g.pieces, (kind = :place, path = path, char = char_offset,
                                 x = round(Int, g.pen), font = sf))
                continue
            end

            # Emit the sub-line as one segment for each row it is on, at the rounded
            # real pen position, so a long line of many runs does not drift. A soft
            # break inside it, or at its start, starts a row there.
            seg_len = length(line)
            sub_start = span_base + char_offset
            cuts = Int[b - sub_start for b in soft_breaks if sub_start <= b < sub_start + seg_len]
            (isempty(cuts) || cuts[1] != 0) && pushfirst!(cuts, 0)
            push!(cuts, seg_len)
            characters = collect(line)
            for k in 1:(length(cuts) - 1)
                piece_start, piece_end = cuts[k], cuts[k + 1]
                (sub_start + piece_start) in soft_breaks && !isempty(g.boxes) && break_row!(sf)
                piece = String(characters[(piece_start + 1):piece_end])
                box = measure_string(p.measure, piece, sf)
                _, ascent, descent = compute_text_extent(box)
                x = round(Int, g.pen)
                g.pen += box.width
                width = round(Int, g.pen) - x
                push!(g.boxes, FontMetrics(box.ascent, box.descent, box.line_gap))
                g.ink_descent = max(g.ink_descent, descent)
                key = k == 1 ? (span_oid, span_occ, li) : (span_oid, span_occ, li, k)
                start, stop = char_offset + piece_start, char_offset + piece_end
                push!(g.pieces, (kind = :text, key = key, path = path,
                                 char_start = start, char_end = stop,
                                 span = span, text = piece, x = x, width = width,
                                 ascent = ascent, descent = descent, font = sf, color = col))
                if cursor_pos !== nothing && g.cursor === nothing && g.caret === nothing &&
                   cursor_pos.span == path && start <= cursor_pos.char <= stop
                    # A caret at the end of a row that a soft break ends stands at
                    # the start of the next row.
                    if cursor_pos.char == stop && (span_base + stop) in soft_breaks
                        pending_caret = sf
                    else
                        g.caret = (x + _get_caret_x(p.measure, piece, sf, cursor_pos.char - start), sf)
                    end
                end
                g.max_x = max(g.max_x, round(Int, g.pen))
            end
            char_offset += seg_len
        end
    end

    if !isempty(g.boxes)
        _close_line!(g, p, last_font, true, collect_spans)
    elseif g.closed == 0 && (group.newline !== nothing || group.is_line || _has_text_span(group))
        # A blank line still occupies one row, sized by the font it has no glyph to
        # take one from. A group that holds only an empty span is such a line,
        # because a caret can stand in it.
        _close_line!(g, p, _line_height_font(group, block_font), true, collect_spans)
    else
        # The empty line after a trailing '\n', and the empty group that a
        # trailing newline leaves behind, are not lines: they add no height. A
        # caret or a place on them still stands where the next line begins.
        _close_line!(g, p, last_font, false, collect_spans)
    end

    # On a line that draws a glyph, the glyphs give every caret of the line its
    # place, so a zero-width coordinate stays only on a line that draws none.
    glyph_rows = Set(sc.y for sc in g.coord_map if _draws_glyph(sc))
    filter!(sc -> _draws_glyph(sc) || !(sc.y in glyph_rows), g.coord_map)

    (spans = g.result, by_key = g.by_key, coord_map = g.coord_map, width = g.max_x,
     height = g.bottom - y0, distance = g.distance, cursor = g.cursor,
     first_baseline = g.first_baseline)
end

# The state of `_layout_group` while it lays out one group: the pen, the lines
# closed so far, and the open line, whose pieces wait for its baseline.
mutable struct _GroupLayout
    y0::Int
    pen::Float64                        # the real pen position on the open line
    max_x::Int
    distance::Float64                   # the real line distances of the lines closed so far
    bottom::Int                         # the lowest pixel that a closed line reaches
    closed::Int                         # the lines closed so far
    boxes::Vector{FontMetrics}          # the boxes of the open line
    ink_descent::Int                    # the rounded descent of the lowest box of the open line
    pieces::Vector{Any}                 # the pieces of the open line
    caret::Any                          # `(x, font)` of the caret on the open line, or `nothing`
    cursor::Any                         # the caret `(x, y, h)` once placed, or `nothing`
    result::Vector{Any}
    by_key::Dict{Any,Any}
    coord_map::Vector{SegmentCoordinate}
    first_baseline::Union{Int,Nothing}  # the baseline of the first line closed, once one is
end

_GroupLayout(y0::Int, start_x::Int) =
    _GroupLayout(y0, Float64(start_x), start_x, 0.0, y0, 0, FontMetrics[], 0, Any[],
                 nothing, nothing, Any[], Dict{Any,Any}(), SegmentCoordinate[], nothing)

# Close the open line of `g`: find its baseline, place its pieces on it, and move
# the distance on. `font` sizes a line that has no box. A line that does not
# `count` places its pieces where the next line begins and adds no height.
function _close_line!(g::_GroupLayout, p::TextToGraphics, font, counts::Bool, collect_spans::Bool)
    spacing = p.line_spacing
    if !isempty(g.boxes)
        metrics = compute_line_metrics(g.boxes)
    elseif font !== nothing
        metrics = get_font_metrics(p.measure, font)
        g.ink_descent = compute_text_extent(p.measure, "", font)[3]
    else
        metrics = nothing
    end
    distance = metrics === nothing ? 0.0 : compute_line_distance(spacing, metrics)
    top = g.y0 + round(Int, g.distance)
    height = g.y0 + round(Int, g.distance + distance) - top
    baseline = top + (metrics === nothing ? 0 : compute_line_baseline(spacing, metrics))
    for piece in g.pieces
        if piece.kind === :text
            y = baseline - piece.ascent
            if collect_spans
                fill = _fill_placement(piece.span, (piece.key..., :fill), piece.x, y,
                                       piece.width, piece.ascent + piece.descent)
                if fill !== nothing
                    push!(g.result, fill)
                    g.by_key[fill.key] = fill
                end
                text = (kind = :text, key = piece.key, text = piece.text, x = piece.x, y = y,
                        font = piece.font, color = piece.color)
                push!(g.result, text)
                g.by_key[text.key] = text
            end
            push!(g.coord_map, SegmentCoordinate(piece.path::SpanPath, piece.char_start, piece.char_end,
                                                 piece.x, top, piece.font, piece.text, piece.width, height))
        elseif piece.kind === :image
            # Embed the span: a raster GraphicsImage for an image document, or a
            # live nested canvas for a pre-projected GraphicsCanvas (widget etc.).
            collect_spans && push!(g.result, _graphics_span_element(piece.span, piece.x,
                                                                    baseline - piece.height,
                                                                    piece.width, piece.height))
            # Hit-testing takes an image as one atomic position (0..1). The font is
            # the one a caret beside the image takes.
            push!(g.coord_map, SegmentCoordinate(piece.path::SpanPath, 0, 1, piece.x, top,
                                                 piece.font, "", piece.width, height))
        else
            push!(g.coord_map, SegmentCoordinate(piece.path::SpanPath, piece.char, piece.char, piece.x, top,
                                                 piece.font, "", 0, height))
        end
    end
    if g.cursor === nothing && g.caret !== nothing
        x, caret_font = g.caret
        _, ascent, descent = compute_text_extent(p.measure, "", caret_font)
        g.cursor = (x, baseline - ascent, max(ascent + descent, 1))
    end
    if counts
        metrics === nothing || g.first_baseline !== nothing || (g.first_baseline = baseline)
        g.distance += distance
        g.closed += 1
        g.bottom = max(g.bottom, top + height, baseline + g.ink_descent)
    end
    empty!(g.boxes)
    empty!(g.pieces)
    g.ink_descent = 0
    g.caret = nothing
    nothing
end

# Locate the caret and the selection highlight over the whole block, in the same
# absolute coordinates the line sub-canvases render into — by running the very
# layout the lines run, group by group.
#
# Two tables map a span's `SpanPath` to the flat offset it starts at, one for each
# space a range is expressed in. Both count a character and an inline image as 1,
# and the implicit break and the indentation of a `TextLine` (the rule of
# `get_flat_offsets`), because the projection that emits the line counts both.
#   • The caret space of the text domain (`get_flat_offsets`), in which a
#     `TextRangeReferenceStep` is expressed, also counts a `TextNewline` and a
#     `TextSpacing` as 1.
#   • The box space, in which a `TextSpanReferenceStep` box is expressed, counts
#     them as 0: `WordWrapping` splices soft newlines into the block at wrap
#     points, and a box must stay invariant under them.
# The flat base of each span of `styled`, in the box space and in the caret space
# (see `_highlight_char_range`): where the span's first character is counted.
function _compute_span_bases(styled::TextBlock)
    box_offsets = Dict{SpanPath,Int}()
    caret_offsets = Dict{SpanPath,Int}()
    box = 0
    caret = 0
    for group in _line_groups(styled)
        group.break_before && (box += 1; caret += 1)
        box += group.indentation
        caret += group.indentation
        for (path, span) in group.spans
            box_offsets[path::SpanPath] = box
            caret_offsets[path::SpanPath] = caret
            box += _box_flat_length(span)
            caret += get_flat_length(span)
        end
        group.newline === nothing || (caret += 1)
    end
    (box_offsets, caret_offsets)
end

function _layout_overlay(p::TextToGraphics, styled::TextBlock, sel, block_font::Cell)
    cursor_pos = get_flat_cursor_coordinate(styled, sel)
    coord_map = SegmentCoordinate[]
    box_offsets, caret_offsets = _compute_span_bases(styled)
    cursor = nothing
    offset = Float64(p.start_y)   # the real top of the next group

    for group in _line_groups(styled)
        laid = _layout_group(p, group, round(Int, offset), cursor_pos, false, block_font)
        append!(coord_map, laid.coord_map)
        cursor === nothing && (cursor = laid.cursor)
        offset += laid.distance
    end

    highlight = NTuple{4,Int}[]
    hl_range = _highlight_char_range(sel, coord_map)
    if hl_range !== nothing
        offsets = hl_range[3] === :caret ? caret_offsets : box_offsets
        highlight = _compute_span_rows(coord_map, offsets, hl_range[1], hl_range[2], p)
    end
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
        font === nothing || return first(compute_text_extent(p.measure, " "^(group.indentation::Int), font))
    end
    font = block_font[]
    font === nothing ? 0 : first(compute_text_extent(p.measure, " "^(group.indentation::Int), font))
end

# The font an empty line is sized with. A flat block carries it on the
# `TextNewline` that terminates the line; a `TextLine` has none, so fall back to
# the block's prevailing font.
_line_height_font(group, block_font::Cell) =
    group.newline === nothing ? block_font[] : group.newline.font::StyleFont

_has_text_span(group) = any(entry -> entry[2] isa TextString, group.spans)

# Whether a coordinate stands for something drawn: text, or an embedded image, which
# covers the range 0..1 even at zero width. The zero-width coordinate of an empty
# line draws nothing.
_draws_glyph(sc::SegmentCoordinate) = sc.width > 0 || !isempty(sc.text) || sc.char_end > sc.char_start

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
_element_font(newline::TextNewline) = newline.font::StyleFont
_element_font(::TextDocument) = nothing

function _element_font(line::TextLine)
    for span in line.elements
        font = _element_font(span)
        font === nothing || return font
    end
    nothing
end

# The font of a caret beside the image at `index` of `group`. An image has no
# font, so the caret takes the one of the nearest text run of its line, the run
# before the image first; on a line with no text run, the prevailing font of the
# block; in a block with no font at all, the font of `TextString(content)`. A run
# typed beside the image takes its style by the same rule (`_find_style_span`).
function _get_image_caret_font(group, index::Int, block_font::Cell)
    spans = group.spans
    for k in (index - 1):-1:1
        span = spans[k][2]
        span isa TextString && return span.font::StyleFont
    end
    for k in (index + 1):length(spans)
        span = spans[k][2]
        span isa TextString && return span.font::StyleFont
    end
    something(block_font[], UNSTYLED_TEXT_FONT)
end

# At least one span to put a caret beside, at either depth: a `TextString`, or an
# inline image, which has a caret before and after it.
_has_caret_span(styled::TextBlock) =
    any(styled.elements) do element
        _is_caret_span(element) || (element isa TextLine && any(_is_caret_span, element.elements))
    end
_is_caret_span(span) = span isa Union{TextString, TextGraphics}

# ── Persistent per-segment graphics (printer locality — dimension C) ───────────
#
# `_layout_group` emits a *placement* (a stable key + geometry/content values) per
# text/fill segment instead of a graphic. The element builder turns each placement
# into a GraphicsText/GraphicsRect that is created ONCE per key and reused across
# re-layouts; its fields are `set_cell_computation!` cells that read the placement back out of the
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
# back to `color_transparent`, so the persistent graphic paints nothing.

function _make_persistent_text(layout, pl0)
    key = pl0.key
    gt = GraphicsText(pl0.text, Int(pl0.x), Int(pl0.y); font = pl0.font, color = pl0.color)
    set_cell_computation!(getfield(gt, :text),  () -> (q = _plget(layout, key); q === nothing ? "" : q.text))
    set_cell_computation!(getfield(gt, :x),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.x)))
    set_cell_computation!(getfield(gt, :y),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.y)))
    set_cell_computation!(getfield(gt, :font),  () -> (q = _plget(layout, key); q === nothing ? pl0.font : q.font))
    set_cell_computation!(getfield(gt, :color), () -> (q = _plget(layout, key); q === nothing ? color_transparent : q.color))
    gt
end

function _make_persistent_rect(layout, pl0)
    key = pl0.key
    rect = GraphicsRect(Int(pl0.x), Int(pl0.y), Int(pl0.w), Int(pl0.h); color = pl0.color)
    set_cell_computation!(getfield(rect, :x),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.x)))
    set_cell_computation!(getfield(rect, :y),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.y)))
    set_cell_computation!(getfield(rect, :w),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.w)))
    set_cell_computation!(getfield(rect, :h),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.h)))
    set_cell_computation!(getfield(rect, :color), () -> (q = _plget(layout, key); q === nothing ? color_transparent : q.color))
    rect
end

# ── ListNode path: lazy paragraph-level mapping ──────────────────────

# A part of a text whose spans are a lazy list maps into the list of paragraph
# canvases. Both count from their heads: the head paragraph holds the head span.
# A span, or characters of it (`elements[i].content{a:b}`), maps to the text node
# of the span, followed by the characters (`text{a:b}`). Spans of one paragraph
# map to its canvas followed by the region of their texts, and spans of more
# paragraphs to the canvas of the text followed by the region of their texts. A
# span that draws no text, such as a newline, adds nothing to a range.
function _map_list_text_forward(p::TextToGraphics, iomap::TextToGraphicsIoMap, reference)
    reference isa ConcreteReference || return nothing
    field = get_reference_head(reference)
    (field isa FieldReferenceStep && field.name == "elements") || return nothing
    range = get_reference_tail(reference)
    range isa ConcreteReference || return nothing
    step = get_reference_head(range)
    (step isa ARangeReferenceStep && step.start < step.stop) || return nothing
    rest = get_reference_tail(range)
    head = iomap.input.elements::ListNode
    places = Any[]
    for index in (step.start + 1):step.stop
        place = _find_list_span_place(head, index)
        place === nothing || push!(places, place)
    end
    isempty(places) && return nothing
    first, last = places[1], places[end]
    rest isa EmptyReference || step.stop == step.start + 1 || return nothing
    paragraphs = unwrap_cell(getfield(unwrap_cell(iomap.output), :elements))
    if first == last
        element = _find_paragraph_text_index(paragraphs, first.paragraph, first.piece)
        element === nothing && return nothing
        node = ConcreteReference(FieldReferenceStep("elements"),
                   ConcreteReference(ElementReferenceStep(first.paragraph),
                       ConcreteReference(FieldReferenceStep("elements"),
                           ConcreteReference(ElementReferenceStep(element), EmptyReference()))))
        rest isa EmptyReference && return node
        return _map_list_span_characters(node, rest)
    end
    box = _compute_list_text_box(p, paragraphs, first, last)
    box === nothing && return nothing
    region = ConcreteReference(RegionReferenceStep(box...), EmptyReference())
    first.paragraph == last.paragraph || return region
    ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(ElementReferenceStep(first.paragraph), region))
end

# `content{a:b}` of a span maps to `text{a:b}` of its text node, which draws the
# whole content of the span.
function _map_list_span_characters(node, rest)
    field = get_reference_head(rest)
    (field isa FieldReferenceStep && field.name == "content") || return nothing
    range = get_reference_tail(rest)
    range isa ConcreteReference && get_reference_tail(range) isa EmptyReference || return nothing
    step = get_reference_head(range)
    step isa ARangeReferenceStep || return nothing
    concat_references(node, ConcreteReference(FieldReferenceStep("text"),
                                ConcreteReference(RangeReferenceStep(step.start, step.stop), EmptyReference())))
end

# The place of span `index` of a lazy list of spans, counted from `head`:
# `(paragraph, piece)`, the index of its paragraph from the head paragraph and its
# index among the spans of that paragraph that draw a text. `nothing` for a span
# that draws no text, such as a newline, and for an index past the list. A
# paragraph ends at a newline; the head paragraph starts at the head, and the
# paragraph before it ends at the span before the head.
function _find_list_span_place(head::ListNode, index::Int)
    node = find_list_node(head, index)
    (node === nothing || !_is_drawn_list_span(node.value)) && return nothing
    if index >= 1
        paragraph, piece, current = 1, 0, head
        while true
            span = current.value
            if span isa TextNewline
                paragraph, piece = paragraph + 1, 0
            elseif _is_drawn_list_span(span)
                piece += 1
            end
            current === node && return (paragraph = paragraph, piece = piece)
            current = current.next
        end
    end
    paragraph, current = 0, head.prev
    while current !== node
        current.value isa TextNewline && current !== head.prev && (paragraph -= 1)
        current = current.prev
    end
    piece, current = 1, node.prev
    while current !== nothing && !(current.value isa TextNewline)
        _is_drawn_list_span(current.value) && (piece += 1)
        current = current.prev
    end
    (paragraph = paragraph, piece = piece)
end

# Whether a span of a lazy list draws a text, as `_compute_paragraph_line` lays
# them out.
_is_drawn_list_span(span) = span isa TextString && !isempty(span.content::AbstractString)

# The index in the canvas of paragraph `paragraph` of its text number `piece`: a
# fill comes before the text of a span that has one.
function _find_paragraph_text_index(paragraphs, paragraph::Int, piece::Int)
    node = find_list_node(paragraphs, paragraph)
    node === nothing && return nothing
    elements = unwrap_cell(getfield(unwrap_cell(node.value), :elements))
    count = 0
    for k in 1:length(elements)
        unwrap_cell(elements[k]) isa GraphicsText || continue
        count += 1
        count == piece && return k
    end
    nothing
end

# The box of the texts from the place `first` to the place `last`, as
# `(x, y, width, height)`: in the frame of their paragraph when one paragraph holds
# them, else in the frame of the canvas of the text.
function _compute_list_text_box(p::TextToGraphics, paragraphs, first, last)
    left, top, right, bottom = typemax(Int), typemax(Int), typemin(Int), typemin(Int)
    for paragraph in first.paragraph:last.paragraph
        node = find_list_node(paragraphs, paragraph)
        node === nothing && return nothing
        canvas = unwrap_cell(node.value)
        offset = first.paragraph == last.paragraph ? 0 : Int(unwrap_cell(getfield(canvas, :y)))
        elements = unwrap_cell(getfield(canvas, :elements))
        piece = 0
        for k in 1:length(elements)
            text = unwrap_cell(elements[k])
            text isa GraphicsText || continue
            piece += 1
            paragraph == first.paragraph && piece < first.piece && continue
            paragraph == last.paragraph && piece > last.piece && break
            content = String(unwrap_cell(getfield(text, :text)))
            width, ascent, descent = compute_text_extent(p.measure, content, unwrap_cell(getfield(text, :font)))
            x, y = Int(unwrap_cell(getfield(text, :x))), Int(unwrap_cell(getfield(text, :y))) + offset
            left, top = min(left, x), min(top, y)
            right, bottom = max(right, x + round(Int, width)), max(bottom, y + round(Int, ascent + descent))
        end
    end
    left > right && return nothing
    (left, top, right - left, bottom - top)
end

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
    output_head = head_node.value isa TextLine ? _build_line_node(p, head_node, 0.0) :
                                                 _build_paragraph_node(p, head_node, 0.0)
    canvas = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), output_head, layout_vertical, false, Cell(nothing))
    TextToGraphicsIoMap(p, styled, canvas, Cell(SegmentCoordinate[]), Cell(0), Cell(nothing),
                        Cell(NamedTuple[]), nothing)
end

# ── A lazy list of lines ──────────────────────────────────────────────────────
#
# A lazy list whose nodes are `TextLine`s is drawn as a lazy list of line canvases,
# one for each line, laid out by `_layout_group` as a line of a block is: its
# indentation, its rows at its soft breaks, its images. The lines and the canvases
# count from their heads.

# The group of `line` alone, as `_line_groups` makes the group of a line, with its
# spans named `[1, j]`: the layout of a line of a lazy list, and the layout that a
# line of a block keeps wherever it stands.
_make_line_group(line::TextLine) =
    (spans = Tuple{SpanPath,Any}[(Int[1, j], span) for (j, span) in enumerate(line.elements)],
     newline = nothing, indentation = line.indentation, break_before = false, is_line = true,
     line = 1, soft_breaks = getfield(line, :soft_breaks))

# The layout of a line of a lazy list. A line with no glyph takes the font of its
# first span, as the prevailing font of a block sizes such a line.
_layout_list_line(p::TextToGraphics, line::TextLine, collect_spans::Bool) =
    _layout_group(p, _make_line_group(line), 0, nothing, collect_spans, Cell(_element_font(line)))

# The graphic of a placement of a layout: a fill, a text, or the image it holds.
_make_list_line_graphic(placement) =
    !(placement isa NamedTuple) ? placement :
    placement.kind === :fill ? GraphicsRect(placement.x, placement.y, placement.w, placement.h;
                                            color = placement.color) :
    _make_sdl(placement.text, placement.x, placement.y, placement.font, placement.color)

"""
    _build_line_node(p, input_node, y_offset) -> ListNode

The canvas of the line of `input_node` at `(0, y_offset)`, the real offset
rounded, in a `ListNode` whose `next` and `prev` build the canvases of the lines
around it when they are read.
"""
function _build_line_node(p::TextToGraphics, input_node::ListNode, y_offset::Float64)
    laid = _layout_list_line(p, input_node.value::TextLine, true)
    canvas = GraphicsCanvas(Int32(0), Int32(round(Int, y_offset)), Int32(0), Int32(0),
                            CellVector(Cell[Cell(_make_list_line_graphic(placement)) for placement in laid.spans]),
                            layout_none, false, Cell(nothing))
    out_node = ListNode(canvas)
    set_cell_computation!(getfield(out_node, :next), () -> begin
        next_input = input_node.next
        next_input === nothing && return nothing
        next_out = _build_line_node(p, next_input, y_offset + laid.distance)
        set_cell_value!(getfield(next_out, :prev), out_node)
        next_out
    end)
    set_cell_computation!(getfield(out_node, :prev), () -> begin
        prev_input = input_node.prev
        prev_input === nothing && return nothing
        distance = _layout_list_line(p, prev_input.value::TextLine, false).distance
        prev_out = _build_line_node(p, prev_input, y_offset - distance)
        set_cell_value!(getfield(prev_out, :next), out_node)
        prev_out
    end)
    out_node
end

# A part of a lazy list of lines maps into the list of line canvases. Lines
# `elements{a:b}` map to the text node of their one text, or to a region of their
# texts; span `j` of line `k`, `elements{k-1:k}.elements{j-1:j}`, and characters of
# it, `….content{s:e}`, map to the text node of the row that holds them, followed
# by the characters (`text{…}`), or to a region when they take more than one row.
# A region is in the frame of its line when one line holds it, and else in the
# frame of the canvas of the text.
function _map_list_lines_forward(p::TextToGraphics, iomap::TextToGraphicsIoMap, reference)
    reference isa ConcreteReference || return nothing
    field = get_reference_head(reference)
    (field isa FieldReferenceStep && field.name == "elements") || return nothing
    range = get_reference_tail(reference)
    range isa ConcreteReference || return nothing
    step = get_reference_head(range)
    (step isa ARangeReferenceStep && step.start < step.stop) || return nothing
    first_line, last_line = step.start + 1, step.stop
    spans, characters = _parse_list_line_part(get_reference_tail(range))
    spans === false && return nothing
    (spans === nothing || first_line == last_line) || return nothing
    head = iomap.input.elements::ListNode
    texts = Any[]
    for k in first_line:last_line
        node = find_list_node(head, k)
        (node === nothing || !(node.value isa TextLine)) && return nothing
        laid = _layout_list_line(p, node.value::TextLine, true)
        text_indices = [index for (index, placement) in enumerate(laid.spans)
                        if placement isa NamedTuple && placement.kind === :text]
        n = 0
        for coordinate in laid.coord_map
            isempty(coordinate.text) && continue
            n += 1
            spans === nothing || coordinate.span_path[2] in spans || continue
            if characters !== nothing
                start, stop = characters
                # A caret is in the first row that holds it, and a range in each row
                # that it overlaps.
                overlaps = start == stop ? coordinate.char_start <= start <= coordinate.char_end :
                                           coordinate.char_start < stop && start < coordinate.char_end
                overlaps || continue
            end
            push!(texts, (line = k, index = text_indices[n], coordinate = coordinate))
            characters !== nothing && characters[1] == characters[2] && break
        end
    end
    isempty(texts) && return nothing
    canvases = unwrap_cell(getfield(unwrap_cell(iomap.output), :elements))
    if length(texts) == 1
        text = texts[1]
        node = ConcreteReference(FieldReferenceStep("elements"),
                   ConcreteReference(ElementReferenceStep(text.line),
                       ConcreteReference(FieldReferenceStep("elements"),
                           ConcreteReference(ElementReferenceStep(text.index), EmptyReference()))))
        characters === nothing && return node
        start, stop = characters
        offset = text.coordinate.char_start
        stop <= text.coordinate.char_end || return nothing
        return concat_references(node, ConcreteReference(FieldReferenceStep("text"),
                   ConcreteReference(RangeReferenceStep(start - offset, stop - offset), EmptyReference())))
    end
    left, top, right, bottom = typemax(Int), typemax(Int), typemin(Int), typemin(Int)
    for text in texts
        offset = 0
        if first_line != last_line
            canvas = find_list_node(canvases, text.line)
            canvas === nothing && return nothing
            offset = Int(unwrap_cell(getfield(unwrap_cell(canvas.value), :y)))
        end
        c = text.coordinate
        left, top = min(left, c.x), min(top, c.y + offset)
        right, bottom = max(right, c.x + c.width), max(bottom, c.y + offset + c.height)
    end
    region = ConcreteReference(RegionReferenceStep(left, top, right - left, bottom - top), EmptyReference())
    first_line == last_line || return region
    ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(ElementReferenceStep(first_line), region))
end

# The spans and the characters that the rest of a path into a line names:
# `(nothing, nothing)` for the whole line, `(j1:j2, nothing)` for spans
# `elements{j1-1:j2}`, `(j:j, (s, e))` for characters `content{s:e}` of span `j`,
# and `(false, nothing)` for any other path.
function _parse_list_line_part(rest)
    rest isa EmptyReference && return (nothing, nothing)
    rest isa ConcreteReference || return (false, nothing)
    field = get_reference_head(rest)
    (field isa FieldReferenceStep && field.name == "elements") || return (false, nothing)
    range = get_reference_tail(rest)
    range isa ConcreteReference || return (false, nothing)
    step = get_reference_head(range)
    (step isa ARangeReferenceStep && step.start < step.stop) || return (false, nothing)
    spans = (step.start + 1):step.stop
    tail = get_reference_tail(range)
    tail isa EmptyReference && return (spans, nothing)
    length(spans) == 1 || return (false, nothing)
    tail isa ConcreteReference || return (false, nothing)
    content = get_reference_head(tail)
    (content isa FieldReferenceStep && content.name == "content") || return (false, nothing)
    characters = get_reference_tail(tail)
    (characters isa ConcreteReference && get_reference_tail(characters) isa EmptyReference) ||
        return (false, nothing)
    step = get_reference_head(characters)
    step isa ARangeReferenceStep || return (false, nothing)
    (spans, (step.start, step.stop))
end

"""
    _build_paragraph_node(p, input_node, y_offset) -> ListNode

Starting from `input_node`, collect all spans until a `TextNewline` or
end of list (one paragraph). Lay them out into a sub-`GraphicsCanvas`
at position `(0, y_offset)`, where `y_offset` is the real sum of the line
distances above, rounded once. Return a `ListNode` whose value is that
sub-canvas, with a lazy `next` thunk that builds the next paragraph.
"""
function _build_paragraph_node(p::TextToGraphics, input_node::ListNode, y_offset::Float64)
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
    distance = _paragraph_distance(p, spans)

    out_node = ListNode(sub_canvas)

    next_input = cur
    set_cell_computation!(getfield(out_node, :next), () -> begin
        next_input === nothing && return nothing
        next_out = _build_paragraph_node(p, next_input, y_offset + distance)
        set_cell_value!(getfield(next_out, :prev), out_node)
        next_out
    end)

    set_cell_computation!(getfield(out_node, :prev), () -> begin
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
function _build_paragraph_node_prev(p::TextToGraphics, input_node_prev, y_offset::Float64)
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

    new_y_offset = y_offset - _paragraph_distance(p, spans)

    sub_canvas = _layout_paragraph(p, spans, new_y_offset)

    out_node = ListNode(sub_canvas)

    prev_boundary = cur
    set_cell_computation!(getfield(out_node, :prev), () -> begin
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
sub-canvas positioned at `(0, y_offset)`, the real offset rounded. No wrap;
each span goes down as a single segment on the baseline of the paragraph's one
line.
"""
function _layout_paragraph(p::TextToGraphics, spans::Vector, y_offset::Float64)
    result = Any[]
    line = _compute_paragraph_line(p, spans)
    for piece in line.pieces
        y = line.baseline - piece.ascent
        _push_fill_rect!(result, piece.span, piece.x, y, piece.width, piece.ascent + piece.descent)
        push!(result, _make_sdl(piece.text, piece.x, y, piece.span.font::StyleFont,
                                piece.span.font_color::StyleColor))
    end
    GraphicsCanvas(Int32(0), Int32(round(Int, y_offset)), Int32(0), Int32(0), CellVector(Cell[Cell(e) for e in result]),
                   layout_none, false, Cell(nothing))
end

"""
    _paragraph_distance(p, spans) -> Float64

The real distance from the top of a paragraph to the top of the next one: the
line distance of its one visual line, or 0 for a paragraph with no text.
"""
_paragraph_distance(p::TextToGraphics, spans::Vector) = _compute_paragraph_line(p, spans).distance

# The one line of a paragraph of the list path: each span that draws, at its x
# and with the rounded ascent and descent of its box, the baseline of the line
# below its top, and the real distance to the next line.
function _compute_paragraph_line(p::TextToGraphics, spans::Vector)
    boxes = FontMetrics[]
    pieces = Any[]
    pen = 0.0
    for span in spans
        span isa TextString || continue
        txt = span.content::AbstractString
        isempty(txt) && continue
        box = measure_string(p.measure, txt, span.font::StyleFont)
        _, ascent, descent = compute_text_extent(box)
        x = round(Int, pen)
        pen += box.width
        push!(boxes, FontMetrics(box.ascent, box.descent, box.line_gap))
        push!(pieces, (span = span, text = txt, x = x, width = round(Int, pen) - x,
                       ascent = ascent, descent = descent))
    end
    isempty(boxes) && return (pieces = pieces, baseline = 0, distance = 0.0)
    metrics = compute_line_metrics(boxes)
    (pieces = pieces, baseline = compute_line_baseline(p.line_spacing, metrics),
     distance = compute_line_distance(p.line_spacing, metrics))
end

# ── Selection → cursor position ───────────────────────────────────────
#
# `get_flat_cursor_coordinate` and `is_structural_selection` are pure `TextBlock`-selection
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
    push!(result, GraphicsRect(Int(x), Int(y), Int(w), Int(h); color = fill))
end

# ── Reader helpers ──────────────────────────────────────────────────────

function _seg_cursor_x(sc::SegmentCoordinate, cursor_pos::Int, measure::TextMeasure)
    local_pos = cursor_pos - sc.char_start
    local_pos <= 0 && return sc.x
    # Image segment: char_end=1 means "after the image" → right edge at x+width.
    isempty(sc.text) && return sc.x + sc.width
    sc.x + _get_caret_x(measure, sc.text, sc.font, min(local_pos, length(sc.text)))
end

function _char_position_at_x(sc::SegmentCoordinate, target_x::Int, measure::TextMeasure)
    txt = sc.text
    # Image segment: binary left/right half decision about the image box.
    if isempty(txt) && sc.char_start == 0 && sc.char_end == 1
        mid = sc.x + sc.width ÷ 2
        return target_x < mid ? 0 : 1
    end
    best_k    = 0
    best_dist = abs(sc.x - target_x)
    offsets = compute_caret_offsets(measure, txt, sc.font)
    for k in 1:length(txt)
        xk = sc.x + round(Int, offsets[k + 1])
        d  = abs(xk - target_x)
        if d < best_dist
            best_dist = d
            best_k    = k
        end
        xk >= target_x && break
    end
    sc.char_start + best_k
end

# The caret that a path of the graphics leaf names: an element
# (`ElementReferenceStep(segment_i)`, 1-based) and a pixel offset inside it
# (`PointReferenceStep(rx, ry)`), as `GraphicsCanvasToGraphicsImage` maps a point.
# The matching SegmentCoordinate in char_to_coord gives the segment, and the
# x-offset gives the character position with `_char_position_at_x`.
function _find_caret_at_element_point(p::TextToGraphics, iomap::TextToGraphicsIoMap, path)
    path isa ConcreteReference || return nothing
    h1 = get_reference_head(path)
    h1 isa RangeReferenceStep || return nothing
    i  = h1.start + 1
    rest = get_reference_tail(path)

    # Adjust for highlight rects prepended before text segments
    hl_off = iomap.highlight_offset
    i -= hl_off
    # The drawn elements, and not the places of empty lines, which draw nothing.
    coord_map = filter(_draws_glyph, iomap.char_to_coord)
    (i < 1 || i > length(coord_map)) && return nothing
    seg = coord_map[i]

    rest isa ConcreteReference || return nothing
    h2 = get_reference_head(rest)
    h2 isa PointReferenceStep || return nothing
    rx = h2.x::Int
    char_pos = _char_position_at_x(seg, seg.x + rx, p.measure)
    _find_flat_caret(iomap.input, seg.span_path, char_pos)
end

# Pick the segment a (canvas-x, canvas-y) click landed on. Matches the
# logic in GraphicsCanvasToGraphicsImage.read_intent for text elements:
#   on a y-band that contains the click, pick the segment with the largest
#   x ≤ click_x (i.e. the rightmost left-edge that still sits to the left
#   of the click). If no band matches y, snap to the nearest line by y.
function _hit_segment(coord_map::Vector{SegmentCoordinate}, x::Int, y::Int)
    on_band = SegmentCoordinate[]
    for sc in coord_map
        if y >= sc.y && y < sc.y + sc.height
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
            dy = y < sc.y ? sc.y - y : (y >= sc.y + sc.height ? y - (sc.y + sc.height - 1) : 0)
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
    _highlight_char_range(sel, coord_map) -> (start, stop, space) or nothing

Extract the flat character range to highlight from the TextBlock's selection,
and the space its offsets are in (see `_layout_overlay`). Recognized shapes:
- `EmptyReference` (∅) → the full extent, in the box space.
- `ConcreteReference(TextRangeReferenceStep(s, e), ∅)` with `s != e` → `(s, e)`,
  in the caret space.
- `ConcreteReference(TextSpanReferenceStep(s, e), ∅)` → `(s, e)`, in the box space.
Returns `nothing` for any other selection shape (normal cursor, etc.).
"""
function _highlight_char_range(sel, coord_map::Vector{SegmentCoordinate})
    sel = sel
    if sel isa EmptyReference
        isempty(coord_map) && return nothing
        # Cover all segments: use a large sentinel that exceeds any absolute offset.
        return (0, typemax(Int) >> 1, :box)
    end
    sel isa ConcreteReference || return nothing
    h = sel.head
    sel.tail isa EmptyReference || return nothing
    if h isa TextRangeReferenceStep
        # A non-empty text selection highlights its flat range; a caret has none
        # (it is drawn as the cursor rect instead).
        return h.start == h.stop ? nothing : (h.start, h.stop, :caret)
    end
    h isa TextSpanReferenceStep || return nothing
    return (h.start, h.stop, :box)
end

# Whether the highlighted sub-range `[s, e)` (offsets in this segment's own base
# space) of `sc` is entirely whitespace — a leading indent span, a newline span, or
# a zero-width indent slot. Such a piece must not anchor a row's left/right edge, so
# the highlight hugs the content and each interior line starts at its indentation
# level. A partly-highlighted content segment keeps only its highlighted substring
# for the whitespace test, so a content run whose *highlighted* part is blank is
# skipped too (rare, but correct at a range boundary).
function _hl_piece_blank(sc::SegmentCoordinate, s::Int, e::Int)
    e <= s && return true
    # An inline image draws, so it anchors its row.
    isempty(sc.text) && sc.width > 0 && return false
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
function _compute_span_rows(coord_map::Vector{SegmentCoordinate}, span_flat_offsets::Dict{SpanPath,Int}, hl_start::Int, hl_stop::Int, p::TextToGraphics)
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
        if haskey(rows, sc.y)
            (l, r, t, b) = rows[sc.y]
            rows[sc.y] = (min(l, px_left), max(r, px_right), min(t, sc.y), max(b, sc.y + sc.height))
        else
            rows[sc.y] = (px_left, px_right, sc.y, sc.y + sc.height)
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
function _compute_column_geo(coord_map::Vector{SegmentCoordinate}, span_flat_offsets::Dict{SpanPath,Int}, hl_start::Int, hl_stop::Int, p::TextToGraphics)
    # Resolve a flat offset to its (x, y_top, y_bottom) via the segment it falls in.
    function _col(off)
        for sc in coord_map
            base = get(span_flat_offsets, sc.span_path, 0)
            (base + sc.char_start <= off <= base + sc.char_end) || continue
            x = _seg_cursor_x(sc, off - base, p.measure)
            return (x, sc.y, sc.y + sc.height)
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
        push!(rects, (left, sc.y, w, sc.height))
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

