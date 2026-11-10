# Fragment of `TextModule`.
#
# Text → Graphics projection. Pure layout pass: arranges the spans of each
# `TextLine` left-to-right, a row for each line and a row after each soft break
# of the line. Word wrapping itself lives in `WordWrapping`, which sets the soft
# breaks upstream of `TextToGraphics` in the pipeline.
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
path into the input `TextBlock` (a `SpanPath`): `[i, j]` for span `j` of the
`TextLine` at element `i`. `char_start`/`char_end` are
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

IoMap for `TextToGraphics`. `projection` is the projection that printed, as it is.
`line_spacing` is the spacing that the print laid its lines out at, for a reader
that lays a line out again. `char_to_coord` holds one `SegmentCoordinate` per
emitted text segment with character range, pixel position, font, and text.
"""
@iomap struct TextToGraphicsIoMap
    projection::Any
    input::TextBlock
    output::GraphicsCanvas
    line_spacing::LineSpacing
    char_to_coord::Cell  # Cell{Vector{SegmentCoordinate}}
    highlight_offset::Cell  # Cell{Int} — number of highlight rects prepended before text segments
    first_baseline::Cell    # Cell{Union{Int,Nothing}} — the baseline of the first line, from the top
    lines::Cell             # Cell{Vector} — the line groups (`_line_groups`)
    line_cells::Any         # L -> the cells of line group L (`layout`, `y`, `h`), or `nothing`
    space::NTuple{4, Int}   # the space around the text, `(left, top, right, bottom)`
    places::Any             # the places of the lines (`_TextPlaces`), or `nothing`
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
    plain_color::StyleColor
end

"""
    TextToGraphics(; measure, theme = nothing, start_x = 0, start_y = 0,
                   line_spacing = SingleSpacing())

Draw a `TextBlock` as graphics, with its caret and the band under its selection.
`theme` is a `TextTheme`, scaled or not, whose caret and selection it draws, and
whose colour of plain text a run of the colour `color_default` takes; with none,
it draws those of the default theme, and builds no theme. `line_spacing` is
the default spacing of the lines: a `LineSpacing`, or a cell that reads one of
the theme, such as its `code_line_spacing` or `prose_line_spacing`; a builder of
code or of prose passes the one it draws, and a widget keeps single spacing. A
container that sets the spacing of the text inside it, as a table sets single
spacing for its cells, puts the property `:line_spacing` in the printer context.
A print lays its lines out at the spacing of its context where the context sets
one, and else at the default. The projection does not change: the IO map of the
print carries the spacing that the print used.
"""
function TextToGraphics(; start_x::Int=0, start_y::Int=0, measure::TextMeasure,
                        line_spacing = SingleSpacing(), theme = nothing)
    TextToGraphics(start_x, start_y, measure, line_spacing,
                   get_text_style(theme, :caret),
                   get_text_style(theme, :dormant_caret),
                   get_text_style(theme, :caret_width),
                   get_text_style(theme, :highlight),
                   get_text_style(theme, :dormant_highlight),
                   get_text_style(theme, :highlight_radius),
                   _get_plain_text_color(theme))
end

# The colour of the plain text of `theme`: a cell that reads the scaled theme with
# no edge, or the plain value of the default theme.
_get_plain_text_color(::Nothing) = get_theme_defaults(TextTheme).plain_text.color
_get_plain_text_color(theme) = make_theme_cell(StyleColor, theme, values -> values.plain_text.color)

# The line spacing of one print of `p`: the one that the context `ctx` sets, as a
# table sets single spacing for its cells, or else the default of `p`.
function _get_line_spacing(p::TextToGraphics, ctx)
    spacing = ctx === nothing ? nothing : get_property(ctx, :line_spacing, nothing)
    spacing === nothing ? p.line_spacing : spacing
end

# The x of the character boundary `position` of `text` in `font`, from the start
# of the text: the pen position where the character after it starts.
_get_caret_x(measure::TextMeasure, text::AbstractString, font::StyleFont, position::Int) =
    round(Int, compute_caret_offsets(measure, text, font)[position + 1])

# ── The places of the lines ────────────────────────────────────────────

# The lines of a printed text and the sums that place a point and a flat offset on
# them: the groups (`_line_groups`), the `TextLine` of each group, the cells of each
# place, the line distances, and the flat lengths of the places, each with the
# break after the place, in the two spaces that a range is expressed in.
#   • The caret space of the text domain (`get_flat_offsets`), in which a
#     `TextRangeReferenceStep` is expressed, counts a `TextSpacing` as 1.
#   • The box space, in which a `TextSpanReferenceStep` box is expressed, counts it
#     as 0.
# Both count a character and an inline image as 1, and the implicit break and the
# indentation of a `TextLine`, because the projection that emits the line counts
# both. The places are an index of the lines for the flat lookups of the text domain
# (`_find_flat_line`), in the caret space.
struct _TextPlaces
    lines::Cell
    group_lines::Cell
    get_line_cells::Function
    distances::PlaceBlocks{Float64}
    caret_lengths::PlaceBlocks{Int}
    box_lengths::PlaceBlocks{Int}
end

_find_flat_line(places::_TextPlaces, flat::Int) =
    flat < 0 ? nothing : find_place_at(places.caret_lengths, flat, length(places.lines[]))

_get_flat_line_start(places::_TextPlaces, i::Int) = get_total_before(places.caret_lengths, i)

# The segments of the line at place `L`, with the span paths of the block, at the
# place of the line below `top`.
function _get_line_segments(places::_TextPlaces, L::Int, top::Int = 0)
    cells = places.get_line_cells(L)
    index = places.group_lines[][L] === nothing ? nothing : places.lines[][L].line
    y = top + Int(cells.y[])
    SegmentCoordinate[SegmentCoordinate(index === nothing ? segment.span_path : Int[index, segment.span_path[2]],
                                        segment.char_start, segment.char_end, segment.x, segment.y + y,
                                        segment.font, segment.text, segment.width, segment.height)
                      for segment in cells.layout[].coord_map]
end

# The nearest line from place `from` in the direction `step` whose layout places a
# segment, or the last place in that direction when none does.
function _find_segment_line(places::_TextPlaces, from::Int, step::Int)
    count = length(places.lines[])
    L = from
    while 1 <= L <= count
        isempty(places.get_line_cells(L).layout[].coord_map) || return L
        L += step
    end
    step < 0 ? 1 : count
end

# The segments of the lines from place `first_line` to place `last_line`, and the
# flat base of each of their spans by `measure_span`, the flat length of a span,
# from `base`, where the first of the lines starts, at the place of the lines below
# `top`.
function _collect_range_segments(places::_TextPlaces, first_line::Int, last_line::Int, base::Int,
                                 measure_span, top::Int)
    coordinates = SegmentCoordinate[]
    bases = Dict{SpanPath,Int}()
    for L in first_line:last_line
        append!(coordinates, _get_line_segments(places, L, top))
        group = places.lines[][L]
        position = base + group.indentation::Int
        for (path, span) in group.spans
            bases[path::SpanPath] = position
            position += measure_span(span)
        end
        base = position + 1
    end
    coordinates, bases
end

# The flat length of `group` in the caret space and in the box space: its
# indentation and its spans, without a break.
function _compute_flat_lengths(group)
    caret = box = group.indentation::Int
    for (_, span) in group.spans
        caret += get_flat_length(span)
        box += _box_flat_length(span)
    end
    (caret = caret, box = box)
end

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
    iomap.input.elements isa ListNode && return _map_list_lines_forward(p, iomap, reference)
    places = iomap.places
    range = _find_text_forward_range(iomap.input, reference, places)
    range === nothing && return nothing
    start, stop, space = range
    coordinates, bases = _collect_flat_range_segments(places, range, 0)
    for segment in coordinates
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
            return _map_text_region(p, places, coordinates, bases, start, stop)
        node = _find_segment_node(iomap, segment)
        node === nothing && return nothing
        return concat_references(node,
            ConcreteReference(FieldReferenceStep("text"),
                ConcreteReference(RangeReferenceStep(a - segment.char_start, b - segment.char_start,
                                                     a == b ? :forward : get_range_direction(reference)),
                                  EmptyReference())))
    end
    nothing
end

# The region of the rows of the range `start:stop` (see `_compute_span_rows`) in
# `coordinates`, the segments of the lines of the range with the flat `bases` of
# their spans, after the smallest node that holds them: the canvas of their line,
# when one line holds all of them, and else the stack of lines. The rows are in the
# frame of the stack; a line starts where the one after it ends. The line of the
# rows is the last line of the range that starts at or above their top.
function _map_text_region(p::TextToGraphics, places::_TextPlaces, coordinates, bases, start::Int, stop::Int)
    rows = _compute_span_rows(coordinates, bases, start, stop, p)
    isempty(rows) && return nothing
    left = minimum(row[1] for row in rows)
    top = minimum(row[2] for row in rows)
    right = maximum(row[1] + row[3] for row in rows)
    bottom = maximum(row[2] + row[4] for row in rows)
    stack = ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(1, 2),
                                                                                 EmptyReference()))
    count = length(places.lines[])
    get_top(L) = Int(places.get_line_cells(L).y[])
    lines = unique(segment.span_path[1] for segment in coordinates)
    line = findlast(L -> get_top(L) <= top, lines)
    if line !== nothing
        line = lines[line]
        if line == count || bottom <= get_top(line + 1)
            line_top = get_top(line)
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
function _find_text_forward_range(text::TextBlock, reference, places::_TextPlaces)
    if reference isa ConcreteReference && reference.head isa TextSpanReferenceStep &&
       reference.tail isa EmptyReference
        return (reference.head.start, reference.head.stop, :box)
    end
    flat = _text_flat_selection(text, reference, places)
    flat === nothing ? nothing : (flat[1], flat[2], :caret)
end

# The reference of the text node that draws `segment`: the canvas of each line
# is in the stack of lines, the second element of the text's canvas, and the node
# is the text of the segment at its place in the canvas of its line, the line that
# its span path names.
function _find_segment_node(iomap::TextToGraphicsIoMap, segment::SegmentCoordinate)
    top = unwrap_cell(getfield(unwrap_cell(iomap.output), :elements))
    length(top) >= 2 || return nothing
    stack = unwrap_cell(top[2])
    stack isa GraphicsCanvas || return nothing
    lines = unwrap_cell(getfield(stack, :elements))
    lines isa CellVector || return nothing
    line_index = segment.span_path[1]
    if 1 <= line_index <= length(lines)
        line = unwrap_cell(lines[line_index])
        line isa GraphicsCanvas || return nothing
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
    # The coordinates of the segments are in the frame of the stack of lines, which
    # stands inside the space around the text.
    left, top, _, _ = iomap.space
    point === nothing || return _find_caret_at_point(p, iomap, point.x - left, point.y - top)
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
_gesture_op(iomap::TextToGraphicsIoMap, evt) = _read_lowered_gesture(iomap.input, evt, iomap.places)

function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::KeyPress)
    return _gesture_op(iomap, evt)
end

# The flat caret at `char` in the span at `span_path`, or `nothing` when the span
# has no flat base. The graphics layer resolves clicks and line motion to a
# `(span, char)` hit; this converts it to the canonical flat selection
# (`get_flat_base + char`), with the line index `line_index` (see `_find_flat_line`).
function _find_flat_caret(text::TextBlock, span_path::SpanPath, char::Int, line_index = get_flat_offsets(text))
    base = get_flat_base(text, span_path, line_index)
    base === nothing ? nothing : make_flat_caret_reference(base + char)
end

# A `ReplaceSelectionOperation` selecting that caret, or `nothing`.
function _flat_hit_op(text::TextBlock, span_path::SpanPath, char::Int, line_index = get_flat_offsets(text))
    caret = _find_flat_caret(text, span_path, char, line_index)
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
# step above us). A single click is the caret at its point, as the press before it
# put it; with Shift, the moving end of the selection goes to the point, as the
# press moved it. A double click selects the word at the point, and a triple click
# the line. Whole-element promotion (Alt+click) is decided in SyntaxToText, where
# the tree is in hand.
function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::MouseClick)
    evt.button === :left || return nothing
    evt.count >= 2 && !evt.modifiers.alt && return _make_unit_selection(p, iomap, evt.x, evt.y, evt.count)
    path = _find_pointer_selection(p, iomap, evt.x, evt.y, evt.modifiers.shift && !evt.modifiers.alt)
    path === nothing ? nothing : ReplaceSelectionOperation(path)
end

# A left press with no Alt and no Ctrl: the caret at the point, or with Shift the
# moving end of the selection there, and the text takes the pointer for a drag, so
# each move of the drag goes to the text wherever the pointer is. The drag names
# the text as a whole, which each projection above maps back to its input.
function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::MouseDown)
    evt.button === :left || return nothing
    (evt.modifiers.alt || evt.modifiers.ctrl || evt.modifiers.meta) && return nothing
    path = _find_pointer_selection(p, iomap, evt.x, evt.y, evt.modifiers.shift)
    path === nothing && return nothing
    CompoundOperation(Any[ReplaceSelectionOperation(path), StartDragOperation(EmptyReference(), nothing)])
end

# A move and the end of a drag that a press on the text started: the moving end of
# the selection goes to the character nearest to the point, on the nearest line,
# and the anchor stays where the press put it.
function read_intent(p::TextToGraphics, iomap::TextToGraphicsIoMap, evt::Union{DragMove,DragEnd})
    path = _find_pointer_selection(p, iomap, evt.x, evt.y, true)
    path === nothing ? nothing : ReplaceSelectionOperation(path)
end

# The selection that a pointer at `(x, y)` makes: the caret there, or with `extend`
# the range from the anchor of the selection to the caret there.
function _find_pointer_selection(p::TextToGraphics, iomap::TextToGraphicsIoMap, x::Int, y::Int,
                                 extend::Bool)
    caret = map_reference_backward(p, iomap, PointReferenceStep(x, y))
    caret === nothing && return nothing
    extend || return caret
    point = get_flat_caret(iomap.input, caret)
    ends = _find_text_selection_ends(iomap.input, iomap.input.selection, iomap.places)
    (point === nothing || ends === nothing) ? caret : _make_flat_selection_reference(ends.anchor, point)
end

# The word (`count == 2`) or the line (`count >= 3`) at the point, as a selection.
function _make_unit_selection(p::TextToGraphics, iomap::TextToGraphicsIoMap, x::Int, y::Int, count::Int)
    caret = map_reference_backward(p, iomap, PointReferenceStep(x, y))
    caret === nothing && return nothing
    point = get_flat_caret(iomap.input, caret)
    point === nothing && return ReplaceSelectionOperation(caret)
    range = count == 2 ? _find_flat_word_range(iomap.input, point) : _find_flat_line_range(iomap.input, point)
    range === nothing && return ReplaceSelectionOperation(caret)
    ReplaceSelectionOperation(make_flat_range_reference(range...))
end

# The caret at `(x, y)`: the segment that owns the point, and the character
# offset within it. The segment is on the line of the point, or on the nearest line
# above or below it that places a segment, so only the lines from the one above to
# the one below are read. A line is found by its real offset, which rounds to the
# place of its canvas, so the lines next to it are read too.
function _find_caret_at_point(p::TextToGraphics, iomap::TextToGraphicsIoMap, x::Int, y::Int)
    places = iomap.places
    places === nothing && return nothing
    L = first(find_place_at(places.distances, Float64(y), length(places.lines[])))
    coordinates = SegmentCoordinate[]
    for line in _find_segment_line(places, L - 1, -1):_find_segment_line(places, L + 1, 1)
        append!(coordinates, _get_line_segments(places, line))
    end
    isempty(coordinates) && return nothing
    sc = _hit_segment(coordinates, x, y)
    sc === nothing && return nothing
    _find_flat_caret(iomap.input, sc.span_path, _char_position_at_x(sc, x, p.measure), places)
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
    # (Alt+arrow, plain arrow while structural) so an outer syntax layer can own
    # it, or it is a key this layer must resolve with pixel geometry (plain
    # up/down, plain Home/End). Re-apply the decline guards so the geometry arms
    # below never mis-handle a declined tree gesture as line motion. The `KeyDown`
    # of Tab and Return is declined too: those keys give their meaning by their
    # `KeyPress`. (`Ctrl+.` is already consumed by `read_gesture`, so it cannot
    # reach here.)
    declined = @gesture_case evt begin
        when(KeyDown(k), evt.modifiers.alt && k in (:up, :down, :left, :right, :home)) => :decline
        when(KeyDown(k), k in (:up, :down, :left, :right) &&
                         is_structural_selection(iomap.input.selection)) => :decline
        when(KeyDown(k), k === :tab || k === :return) => :decline
    end
    declined === nothing || return nothing

    styled = iomap.input
    # A block whose elements are a lazy list is drawn line by line and keeps no
    # geometry of the whole, so no key moves along its lines. The list can be
    # endless, so it is not walked either.
    styled.elements isa ListNode && return nothing
    _has_caret_span(styled) || return nothing

    # Shift moves the moving end of the selection and keeps its anchor, as the
    # geometry-free Shift keys of the text domain do. Without Shift, the key moves
    # from the moving end and the selection becomes a caret there. The caret and its
    # line are found by the places of the lines, and the keys read only the line of
    # the caret and the line next to its row.
    places = iomap.places
    extend = evt.modifiers.shift && !evt.modifiers.ctrl
    ends = extend ? _find_text_selection_ends(styled, styled.selection, places) : nothing
    extend && ends === nothing && return nothing
    current = get_flat_cursor_coordinate(styled, styled.selection, places)
    current === nothing && return nothing
    segments = _get_line_segments(places, current.span[1])
    found = _find_caret_coordinate(styled, segments, current, places)
    found === nothing && return nothing
    cur_sc = found.coordinate

    target = @gesture_case evt begin
        when(KeyDown(k), k === :home) => _find_home_target(styled, segments, cur_sc, current, places)
        when(KeyDown(k), k === :end) => begin
            sc = filter(sc -> sc.y == cur_sc.y, segments)[end]
            (sc.span_path, sc.char_end)
        end
        when(KeyDown(k), k === :up || k === :down) => begin
            cursor_x = _seg_cursor_x(cur_sc, found.char, p.measure)
            target_segs = _find_next_row(places, current.span[1], segments, cur_sc.y, k === :up ? -1 : 1)
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
    extend || return _flat_hit_op(styled, target..., places)
    base = get_flat_base(styled, target[1], places)
    base === nothing && return nothing
    return ReplaceSelectionOperation(_make_flat_selection_reference(ends.anchor, base + target[2]))
    # A KeyDown this layer neither edits nor resolves with geometry (e.g. Return,
    # Escape, Insert while a text caret exists) is declined, NOT passed on as a raw
    # gesture: a reader must yield an Operation or `nothing`, never an event. Putting
    # the gesture in the operation slot marks the change "already produced" and stops
    # the enclosing chain from re-offering it to the domain — which is why committing
    # an insertion (Enter) or aborting it (Escape) silently did nothing once the buffer
    # had a cursor. Returning `nothing` lets it propagate inward to the domain reader.
    return nothing
end

# Where Home moves the moving end `current`, a `(span, char)`, as a
# `(span_path, char)`. On the first row of a line, it is the first character of the
# line that is not a space; when the moving end is already there, and on a later row
# of a wrapped line, it is the start of the row. `row` is the segment of the moving
# end, and `segments` are the segments of its line.
function _find_home_target(styled::TextBlock, segments, row, current, places)
    first_segment = filter(sc -> sc.y == row.y, segments)[1]
    row_start = (first_segment.span_path, first_segment.char_start)
    row.y == minimum(sc -> sc.y, segments) || return row_start
    i = current.span[1]
    base = get_flat_base(styled, current.span, places)
    base === nothing && return row_start
    # The spaces are characters of one code unit, so the index of the first other
    # character in the string counts the spaces before it.
    text = get_flat_string(styled.elements[i])
    first_text = _get_flat_line_start(places, i) + something(findfirst(!=(' '), text), length(text) + 1) - 1
    base + current.char == first_text && return row_start
    found = _text_flat_span(styled, first_text, places)
    found === nothing ? row_start : (found.span, found.char)
end

# The coordinate of `coord_map`, the segments of the line of the caret, that holds
# the caret `current`, a `(span, char)`, and the character of the caret in it. A
# caret on an empty span of a line that draws a glyph has no coordinate of its
# span, because the glyphs give the places of that line: it takes the coordinate
# that holds its flat offset. `line_index` gives the flat base of a span (see
# `_find_flat_line`).
function _find_caret_coordinate(styled::TextBlock, coord_map, current, line_index = get_flat_offsets(styled))
    index = findfirst(sc -> sc.span_path == current.span && sc.char_start <= current.char <= sc.char_end, coord_map)
    index === nothing || return (coordinate = coord_map[index], char = current.char)
    base = get_flat_base(styled, current.span, line_index)
    base === nothing && return nothing
    flat = base + current.char
    for sc in coord_map
        sc_base = get_flat_base(styled, sc.span_path, line_index)
        sc_base === nothing && continue
        sc_base + sc.char_start <= flat <= sc_base + sc.char_end &&
            return (coordinate = sc, char = flat - sc_base)
    end
    nothing
end

# ── Layout engine (wrap-free) ──────────────────────────────────────────

"""
    print_document(p::TextToGraphics, recursion, styled::TextBlock, ctx) -> TextToGraphicsIoMap

Lay an already-wrapped `TextBlock` out into reactive graphics, at the line
spacing of this print (`_get_line_spacing`). Lines advance left-to-right; each
`TextLine` starts a row, and so does each of its soft breaks. The wrap itself —
finding the word boundaries where text would overflow — is the job of
`WordWrapping` upstream.

The text takes the space that its slot gives (`PrinterContext.space`) as a box:
its lines, its caret and its highlight stand inside the space, and its extent
holds it. Its IO map carries the space for its readers.
"""
function print_document(p::TextToGraphics, recursion, styled::TextBlock, ctx)
    spacing = _get_line_spacing(p, ctx)
    # A lazy list of lines: a lazy list of line canvases
    if styled.elements isa ListNode
        return _print_listnode(p, spacing, styled)
    end
    space = ctx === nothing ? (0, 0, 0, 0) : ctx.space
    space_left, space_top, space_right, space_bottom = space
    # Per-line decomposition (printer locality — dimension B). The output is a
    # vertical stack of one reactive sub-canvas per `TextLine` — a structural
    # boundary that never reads span content. Each line's sub-canvas lays out only
    # that line's spans, so a
    # content edit invalidates just the edited line's cells (and, via the y-offset
    # height chain, the lines below it). The backend dirty-rectangle pass then
    # repaints only the edited line instead of the whole block.
    #
    # The crucial property is that the *list* of line sub-canvases depends only on
    # the line grouping (structure), so a content edit leaves it valid and the
    # dirty walk descends into it to find just the edited line stale. Editing the
    # last line moves nothing below it, so its dirty rect is tight.
    #
    # The block's prevailing font sizes a blank line that has no font of its own
    # (an empty `TextLine`). It lives in its own cell because only such a line
    # reads it: a font edit still re-lays out just the lines that render glyphs.
    block_font = Cell(@computation _block_font(styled))

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
    # cells by its place. A line's `layout` reads only that line's spans' content,
    # and its `flat_lengths` only their lengths; its `y` reads the offset of its
    # place, the sum of the real line distances of the places above, rounded once,
    # so a long text does not drift (editing the last line moves nothing; editing a
    # middle line reflows the lines below — matching ListNode spines).
    # Each placement becomes a PERSISTENT GraphicsText/GraphicsRect reused across
    # re-layouts, its fields `set_cell_computation!` cells reading the placement back out of the
    # line's `layout` (printer locality — dimension C, now line-local).
    line_entries = IdDict{Any,NamedTuple}()
    place_entries = Dict{Int,NamedTuple}()
    # The line distances, the widths and the flat lengths of the places, each
    # combined over aligned blocks of places (`PlaceBlocks`). The offset of a line,
    # the width of the text and the line of a flat offset each read cells to a depth
    # of log2 of the count of lines. The flat length of a place counts the break
    # after it, so the flat offset of a line is the sum of the places above it.
    distances = PlaceBlocks{Float64}(L -> get_line_cells(L).distance[], +)
    widths = PlaceBlocks{Int}(L -> get_line_cells(L).layout[].width, max)
    caret_lengths = PlaceBlocks{Int}(L -> get_line_cells(L).flat_lengths[].caret + 1, +)
    box_lengths = PlaceBlocks{Int}(L -> get_line_cells(L).flat_lengths[].box + 1, +)
    function make_line_entry(line_layout::Cell, line_y::Cell, flat_lengths::Cell)
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
                    push!(out, _persistent_graphic!(p, cache, line_layout, pl))
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
        (layout = line_layout, h = line_h, distance = line_distance, y = line_y, canvas = sub,
         flat_lengths = flat_lengths)
    end
    # The cells of the line `line`, wherever it stands.
    function get_line_cells(line::TextLine)
        get!(line_entries, line) do
            line_layout = Cell(@computation _layout_group(p, spacing, _make_line_group(line), 0, nothing, true,
                                                          block_font))
            line_y = Cell(Computation(function ()
                L = get(line_places[], line, nothing)
                L === nothing ? Int32(0) : Int32(round(Int, get_total_before(distances, L)))
            end))
            make_line_entry(line_layout, line_y, Cell(@computation _compute_flat_lengths(_make_line_group(line))))
        end
    end
    # The cells of the group at place `L`.
    function get_line_cells(L::Int)
        line = group_lines[][L]
        line === nothing || return get_line_cells(line::TextLine)
        get!(place_entries, L) do
            line_layout = Cell(@computation _layout_group(p, spacing, lines_cell[][L], 0, nothing, true, block_font))
            make_line_entry(line_layout, Cell(@computation Int32(round(Int, get_total_before(distances, L)))),
                            Cell(@computation _compute_flat_lengths(lines_cell[][L])))
        end
    end
    text_places = _TextPlaces(lines_cell, group_lines, get_line_cells, distances, caret_lengths, box_lengths)

    # The caret/highlight stay a single selection-driven `overlay`, laid out in
    # absolute coordinates over the whole stack, so a pure caret move still
    # invalidates only the two overlay rects (dimension A): the spans never read
    # the selection. `overlay` reads only the lines that the selection touches,
    # and lays out the line of the caret with the same `_layout_group` pass the line
    # runs, so the caret lands exactly where the glyph it sits against was drawn.
    #
    # The overlay is laid out from the **stored** selection, live or dormant, so a
    # dormant caret still has a place on the screen. `is_live` decides only how it
    # is painted. Reading the raw cell is what makes a dormant selection visible at
    # all: the property answers `nothing` for one, which is the default that keeps
    # every other reader correct.
    selection_cell = getfield(styled, :selection)
    overlay = Cell(@computation _layout_overlay(p, spacing, styled, _get_stored_path(selection_cell[]),
                                                block_font, text_places))
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
    set_cell_computation!(getfield(cursor_rect, :x),
                          () -> (g = overlay[].cursor; g === nothing ? Int32(0) : Int32(g[1] + space_left)))
    set_cell_computation!(getfield(cursor_rect, :y),
                          () -> (g = overlay[].cursor; g === nothing ? Int32(0) : Int32(g[2] + space_top)))
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
    highlight_canvas = GraphicsCanvas(Cell(Int32(space_left)), Cell(Int32(space_top)), Cell(Int32(0)), Cell(Int32(0)),
                                      highlight_elements, layout_none, false, Cell(nothing))

    # Vertical stack of line sub-canvases. Its membership reads only `lines_cell`
    # (structure); `get_line_cells` builds/looks up cells without forcing them, so
    # no content is read here and the stack stays valid across content edits.
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
    lines_stack = GraphicsCanvas(Cell(Int32(space_left)), Cell(Int32(space_top)), Cell(Int32(0)), Cell(Int32(0)),
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
    canvas_w = Cell(Computation(() -> Int32(get_total_before(widths, length(lines_cell[]) + 1))))
    canvas_h = Cell(Computation(function ()
        n = length(lines_cell[])
        n == 0 ? Int32(0) : (lc = get_line_cells(n); Int32(lc.y[] + lc.h[]))
    end))
    # Top canvas: the line stack with the selection-driven caret/highlight overlays
    # floating above it in absolute coordinates. A fixed vector, so its membership
    # never regenerates — the highlight's per-selection churn is confined to the
    # highlight sub-canvas's own element vector. A left click on the text puts the
    # caret at the point, so the last element is an I-beam over the box of the
    # lines. The stack, the overlays and the regions stand inside the space, and
    # the extent of the top canvas holds it.
    ibeam = GraphicsPointerShape(space_left, space_top, () -> canvas_w[], () -> canvas_h[], :ibeam)
    # A span that names a pointer shape, such as a link with the hand, has a region
    # of its shape over each of its segments, after the I-beam, so it wins there.
    # A text with no such span reads no segment for it.
    span_shapes = GraphicsCanvas(Cell(Int32(space_left)), Cell(Int32(space_top)), canvas_w, canvas_h,
                                 CellVector(Computation(() -> _make_span_shape_regions(styled, char_to_coord))),
                                 layout_none, true, Cell(nothing))
    top_elements = CellVector(Cell[Cell(highlight_canvas), Cell(lines_stack), Cell(cursor_rect),
                                   Cell(ibeam), Cell(span_shapes)])
    space_width, space_height = space_left + space_right, space_top + space_bottom
    outer_w = space_width == 0 ? canvas_w : Cell(@computation Int32(canvas_w[] + space_width))
    outer_h = space_height == 0 ? canvas_h : Cell(@computation Int32(canvas_h[] + space_height))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), outer_w, outer_h,
                            top_elements, layout_none, true, Cell(nothing))
    # The baseline of the first line: the one of the layout of the first line,
    # at the place of that line.
    first_baseline = Cell(Computation(function ()
        isempty(lines_cell[]) && return nothing
        first_line = get_line_cells(1)
        baseline = first_line.layout[].first_baseline
        baseline === nothing ? nothing : Int(first_line.y[]) + baseline + space_top
    end))
    TextToGraphicsIoMap(p, styled, canvas, spacing, char_to_coord, highlight_offset, first_baseline,
                        lines_cell, get_line_cells, space, text_places)
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
    any(line -> any(span -> span isa TextString && span.pointer_shape !== nothing, line.elements),
        text.elements)

_find_segment_span(text::TextBlock, path::SpanPath) = text.elements[path[1]].elements[path[2]]

# ── Line grouping ─────────────────────────────────────────────────────────────
#
# The block resolved into visual lines — the one grouping both layout passes read,
# so the rendered lines and the caret/highlight overlay can never disagree about
# where a span sits.
#
# A group is one `TextLine`: the spans that render on it, each tagged with its
# `SpanPath` `[i, j]`, the `indentation` it opens with, whether the break before a
# line precedes it, `line`, the index of the line, and `soft_breaks`, the cell of
# the soft breaks of that line. The cell is not read here: the layout of the line
# reads it, so a new wrap lays out only its line. A line implies a break *before*
# itself unless it leads the block — the separator rule of `get_flat_offsets` and
# `TextBlockToString`, so `n` lines render with `n-1` breaks. A block with no line
# has one empty group that is no line, `line` 0: it adds no height.
#
# A span's `.content` is never read here — only the lines, their spans and their
# indentation — so the grouping survives content edits untouched, which is what
# keeps a line's layout local to that line.
function _line_groups(styled::TextBlock)
    groups = NamedTuple[]
    for (i, line) in enumerate(styled.elements)
        push!(groups, (spans = Tuple{SpanPath,Any}[(Int[i, j], span) for (j, span) in enumerate(line.elements)],
                       indentation = line.indentation, break_before = i > 1, is_line = true, line = i,
                       soft_breaks = getfield(line, :soft_breaks)))
    end
    isempty(groups) && push!(groups, (spans = Tuple{SpanPath,Any}[], indentation = 0, break_before = false,
                                      is_line = false, line = 0, soft_breaks = nothing))
    groups
end

# The `TextLine` that `group` lays out, or `nothing` for the group of a block with
# no line.
_find_group_line(styled::TextBlock, group) = group.line > 0 ? styled.elements[group.line] : nothing

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
# and `spacing`, the line spacing of the print, sets the distance to the next
# line. A piece of a line waits until the line closes, because its baseline needs
# every box of the line.
#
# `cursor_pos` is a `(span::SpanPath, char)` caret, or `nothing`. The returned
# `cursor` is `(x, y, h)` when it fell inside this group: it stands on the
# baseline and is as high as the font at its place. `distance` is the real sum of
# the line distances of the group, where the next group starts, and `height`
# reaches the lowest ink of the group.
function _layout_group(p::TextToGraphics, spacing::LineSpacing, group, y0::Int, cursor_pos,
                       collect_spans::Bool, block_font::Cell)
    start_x = p.start_x + _indent_width(p, group, block_font)
    g = _GroupLayout(spacing, y0, start_x)
    occ = Dict{UInt64,Int}()   # per-span occurrence counter so a shared decorative
                               # span (one TextString at several flat positions)
                               # gets a distinct stable key per occurrence.
    last_font = nothing        # the font of the last text span: it sizes an empty last line
    is_caret_at(path, k) = cursor_pos !== nothing && g.cursor === nothing && g.caret === nothing &&
                           cursor_pos.span == path && cursor_pos.char == k
    soft_breaks = group.soft_breaks === nothing ? Int[] : collect(Int, group.soft_breaks[])
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
        # The layout reads no colour: the text that draws a piece reads the colour
        # of its span (`_get_drawn_color`).
        txt = span.content::AbstractString               # reads span content cell
        sf  = span.font::StyleFont                       # reads span font cell
        last_font = sf

        # An empty span draws no glyph, but it has a place: a zero-width coordinate
        # where a caret on it stands, so a key moves the caret onto the line and
        # off it. A caret there has no glyph to stand against, so it takes the font
        # of the span. One on a line that draws a glyph is dropped below.
        if isempty(txt)
            is_caret_at(path, 0) && (g.caret = (round(Int, g.pen), sf))
            push!(g.pieces, (kind = :place, path = path, char = 0, x = round(Int, g.pen), font = sf))
            continue
        end

        # Emit the span as one segment for each row it is on, at the rounded real pen
        # position, so a long line of many runs does not drift. A soft break inside
        # it, or at its start, starts a row there.
        seg_len = length(txt)
        cuts = Int[b - span_base for b in soft_breaks if span_base <= b < span_base + seg_len]
        (isempty(cuts) || cuts[1] != 0) && pushfirst!(cuts, 0)
        push!(cuts, seg_len)
        characters = collect(txt)
        for k in 1:(length(cuts) - 1)
            start, stop = cuts[k], cuts[k + 1]
            (span_base + start) in soft_breaks && !isempty(g.boxes) && break_row!(sf)
            piece = String(characters[(start + 1):stop])
            box = measure_string(p.measure, piece, sf)
            _, ascent, descent = compute_text_extent(box)
            x = round(Int, g.pen)
            g.pen += box.width
            width = round(Int, g.pen) - x
            push!(g.boxes, FontMetrics(box.ascent, box.descent, box.line_gap))
            g.ink_descent = max(g.ink_descent, descent)
            key = k == 1 ? (span_oid, span_occ) : (span_oid, span_occ, k)
            push!(g.pieces, (kind = :text, key = key, path = path,
                             char_start = start, char_end = stop,
                             span = span, text = piece, x = x, width = width,
                             ascent = ascent, descent = descent, font = sf))
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
    end

    if !isempty(g.boxes)
        _close_line!(g, p, last_font, true, collect_spans)
    elseif g.closed == 0 && (group.is_line || _has_text_span(group))
        # A blank line still occupies one row, sized by the font it has no glyph to
        # take one from. A group that holds only an empty span is such a line,
        # because a caret can stand in it.
        _close_line!(g, p, _line_height_font(group, block_font), true, collect_spans)
    else
        # The group of a block with no line is no line: it adds no height. A caret
        # or a place on it still stands where the next line begins.
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

# The state of `_layout_group` while it lays out one group: the line spacing of
# the print, the pen, the lines closed so far, and the open line, whose pieces
# wait for its baseline.
mutable struct _GroupLayout
    const spacing::LineSpacing
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

_GroupLayout(spacing::LineSpacing, y0::Int, start_x::Int) =
    _GroupLayout(spacing, y0, Float64(start_x), start_x, 0.0, y0, 0, FontMetrics[], 0, Any[],
                 nothing, nothing, Any[], Dict{Any,Any}(), SegmentCoordinate[], nothing)

# Close the open line of `g`: find its baseline, place its pieces on it, and move
# the distance on. `font` sizes a line that has no box. A line that does not
# `count` places its pieces where the next line begins and adds no height.
function _close_line!(g::_GroupLayout, p::TextToGraphics, font, counts::Bool, collect_spans::Bool)
    spacing = g.spacing
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
                        font = piece.font, span = piece.span)
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

# Locate the caret and the selection highlight in the same absolute coordinates
# the line sub-canvases render into, from the lines that the selection touches.
function _layout_overlay(p::TextToGraphics, spacing::LineSpacing, styled::TextBlock, sel, block_font::Cell,
                         places::_TextPlaces)
    (cursor = _compute_overlay_caret(p, spacing, styled, sel, block_font, places),
     highlight = _compute_overlay_highlight(p, sel, places))
end

# The caret `(x, y, h)` of a caret selection, or `nothing`: the line that holds its
# flat offset, laid out again with the caret by the very layout the line runs, at
# the place of the line. The layout of a line names its spans `[1, j]`. The caret
# of a range stands at its moving end.
function _compute_overlay_caret(p::TextToGraphics, spacing::LineSpacing, styled::TextBlock, sel,
                                block_font::Cell, places::_TextPlaces)
    ends = _find_text_selection_ends(styled, sel, places)
    ends === nothing && return nothing
    place = _find_flat_place(styled, ends.moving, places)
    place === nothing && return nothing
    path, char = place
    L = path[1]
    group = _make_line_group(styled.elements[L]::TextLine)
    cursor = _layout_group(p, spacing, group, 0, (span = Int[1, path[2]], char = char), false, block_font).cursor
    cursor === nothing && return nothing
    top = p.start_y + Int(places.get_line_cells(L).y[])
    (cursor[1], cursor[2] + top, cursor[3])
end

# The rows of the highlight of `sel` (see `_compute_span_rows`), from the segments
# of the lines that its range touches and the flat base of each of their spans.
function _compute_overlay_highlight(p::TextToGraphics, sel, places::_TextPlaces)
    range = _highlight_char_range(sel)
    range === nothing && return NTuple{4,Int}[]
    coordinates, bases = _collect_flat_range_segments(places, range, p.start_y)
    _compute_span_rows(coordinates, bases, range[1], range[2], p)
end

# The segments of the lines that the flat range `(start, stop, space)` touches, and
# the flat base of each of their spans in the space of the range, at the place of
# the lines below `top`.
function _collect_flat_range_segments(places::_TextPlaces, range, top::Int)
    start, stop, space = range
    lengths = space === :caret ? places.caret_lengths : places.box_lengths
    measure_span = space === :caret ? get_flat_length : _box_flat_length
    count = length(places.lines[])
    first_line, base = find_place_at(lengths, start, count)
    last_line = first(find_place_at(lengths, stop, count))
    _collect_range_segments(places, first_line, last_line, base, measure_span, top)
end

# The flat character length a span contributes to the box space (see
# `_TextPlaces`): an image occupies exactly one column, matching how
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

# The font an empty line is sized with: the font of its empty run, so an empty line
# after a heading has the height of its own run, and text typed into it takes that
# font. A line with no run takes the prevailing font of its block.
function _line_height_font(group, block_font::Cell)
    for (_, span) in group.spans
        span isa TextString && return span.font::StyleFont
    end
    block_font[]
end

_has_text_span(group) = any(entry -> entry[2] isa TextString, group.spans)

# Whether a coordinate stands for something drawn: text, or an embedded image, which
# covers the range 0..1 even at zero width. The zero-width coordinate of an empty
# line draws nothing.
_draws_glyph(sc::SegmentCoordinate) = sc.width > 0 || !isempty(sc.text) || sc.char_end > sc.char_start

# The block's prevailing font — the first font any line offers, in document order,
# or `nothing` for a block that has none. It sizes a `TextLine` with no run, which
# has no font of its own.
function _block_font(styled::TextBlock)
    for element in styled.elements
        font = _element_font(element)
        font === nothing || return font
    end
    nothing
end

_element_font(span::TextString) = span.font::StyleFont
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

# At least one span of a line to put a caret beside: a `TextString`, or an inline
# image, which has a caret before and after it.
_has_caret_span(styled::TextBlock) = any(line -> any(_is_caret_span, line.elements), styled.elements)
_is_caret_span(span) = span isa Union{TextString, TextGraphics}

# ── Persistent per-segment graphics (printer locality — dimension C) ───────────
#
# `_layout_group` emits a *placement* (a stable key + geometry/content values) per
# text/fill segment instead of a graphic. The element builder turns each placement
# into a GraphicsText/GraphicsRect that is created ONCE per key and reused across
# re-layouts; its fields are `set_cell_computation!` cells that read the placement back out of the
# `layout` cell (via `by_key`), and the colour of a text reads its span
# (`_get_drawn_color`). So a structural edit keeps the object identity of
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

_persistent_graphic!(p::TextToGraphics, cache, layout, pl) =
    get!(() -> pl.kind === :fill ? _make_persistent_rect(layout, pl) :
                                   _make_persistent_text(p, layout, pl),
         cache, pl.key)

# When a placement disappears (segment removed in a re-layout), a text falls back
# to no text and a rect to `color_transparent`, so the persistent graphic paints
# nothing.

# The colour that `span` draws in: its own, or the plain text colour of the theme
# for a run that names `color_default`. The colour cell of each text that draws a
# span reads it, and no layout does, so a new colour of a span, as a delimiter lit
# by the pointer takes, repaints the texts of that span and lays out no line.
function _get_drawn_color(p::TextToGraphics, span::TextString)
    color = span.font_color::StyleColor
    is_color_equal(color, color_default) ? p.plain_color::StyleColor : color
end

# A key belongs to one occurrence of one span, so the text of a key reads the
# colour of the span of its first placement.
function _make_persistent_text(p::TextToGraphics, layout, pl0)
    key = pl0.key
    span = pl0.span
    gt = GraphicsText(pl0.text, Int(pl0.x), Int(pl0.y); font = pl0.font, color = _get_drawn_color(p, span))
    set_cell_computation!(getfield(gt, :text),  () -> (q = _plget(layout, key); q === nothing ? "" : q.text))
    set_cell_computation!(getfield(gt, :x),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.x)))
    set_cell_computation!(getfield(gt, :y),     () -> (q = _plget(layout, key); Int32(q === nothing ? 0 : q.y)))
    set_cell_computation!(getfield(gt, :font),  () -> (q = _plget(layout, key); q === nothing ? pl0.font : q.font))
    set_cell_computation!(getfield(gt, :color), () -> _get_drawn_color(p, span))
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

"""
    _print_listnode(p, spacing, styled)

When `TextBlock.elements` is a `ListNode` of `TextLine`s, produce a top-level
`GraphicsCanvas` with `layout_vertical`, `overlapping_elements=false`, and a
`ListNode` of sub-canvases, one for each line (see below), at the line spacing
`spacing` of the print.
"""
function _print_listnode(p::TextToGraphics, spacing::LineSpacing, styled::TextBlock)
    head_node = styled.elements::ListNode
    output_head = _build_line_node(p, spacing, head_node, 0.0)
    canvas = GraphicsCanvas(Int32(0), Int32(0), Int32(0), Int32(0), output_head, layout_vertical, false, Cell(nothing))
    TextToGraphicsIoMap(p, styled, canvas, spacing, Cell(SegmentCoordinate[]), Cell(0), Cell(nothing),
                        Cell(NamedTuple[]), nothing, (0, 0, 0, 0), nothing)
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
     indentation = line.indentation, break_before = false, is_line = true,
     line = 1, soft_breaks = getfield(line, :soft_breaks))

# The layout of a line of a lazy list, at the line spacing `spacing` of the print.
# A line with no glyph takes the font of its first span, as the prevailing font of
# a block sizes such a line.
_layout_list_line(p::TextToGraphics, spacing::LineSpacing, line::TextLine, collect_spans::Bool) =
    _layout_group(p, spacing, _make_line_group(line), 0, nothing, collect_spans, Cell(_element_font(line)))

# The graphic of a placement of a layout: a fill, a text, or the image it holds.
_make_list_line_graphic(p::TextToGraphics, placement) =
    !(placement isa NamedTuple) ? placement :
    placement.kind === :fill ? GraphicsRect(placement.x, placement.y, placement.w, placement.h;
                                            color = placement.color) :
    _make_sdl(placement.text, placement.x, placement.y, placement.font, _get_drawn_color(p, placement.span))

"""
    _build_line_node(p, spacing, input_node, y_offset) -> ListNode

The canvas of the line of `input_node` at `(0, y_offset)`, the real offset
rounded, in a `ListNode` whose `next` and `prev` build the canvases of the lines
around it when they are read, each at the line spacing `spacing` of the print.
"""
function _build_line_node(p::TextToGraphics, spacing::LineSpacing, input_node::ListNode, y_offset::Float64)
    laid = _layout_list_line(p, spacing, input_node.value::TextLine, true)
    canvas = GraphicsCanvas(Int32(0), Int32(round(Int, y_offset)), Int32(0), Int32(0),
                            CellVector(Cell[Cell(_make_list_line_graphic(p, placement)) for placement in laid.spans]),
                            layout_none, false, Cell(nothing))
    out_node = ListNode(canvas)
    set_lazy_link!(out_node, :next, () -> begin
        next_input = input_node.next
        next_input === nothing && return nothing
        _build_line_node(p, spacing, next_input, y_offset + laid.distance)
    end)
    set_lazy_link!(out_node, :prev, () -> begin
        prev_input = input_node.prev
        prev_input === nothing && return nothing
        distance = _layout_list_line(p, spacing, prev_input.value::TextLine, false).distance
        _build_line_node(p, spacing, prev_input, y_offset - distance)
    end)
    out_node
end

# A part of a lazy list of lines maps into the list of line canvases. Lines
# `elements{a:b}` map to the text node of their one text, or to a region of their
# texts; span `j` of line `k`, `elements{k-1:k}.elements{j-1:j}`, and characters of
# it, `….content{s:e}`, map to the text node of the row that holds them, followed
# by the characters (`text{…}`), or to a region when they take more than one row.
# A region is in the frame of its line when one line holds it, and else in the
# frame of the canvas of the text. A line is laid out again at the line spacing
# that the print used, which the IO map carries.
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
        laid = _layout_list_line(p, iomap.line_spacing, node.value::TextLine, true)
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

# The segments of the row next to the row at `y` of the line at place `L`, whose
# segments are `segments`, in the direction `step`: the row above or below it in
# the same line, or else the last row above or the first row below in the nearest
# line that places a segment. Empty when there is none.
function _find_next_row(places::_TextPlaces, L::Int, segments::Vector{SegmentCoordinate}, y::Int, step::Int)
    count = length(places.lines[])
    while true
        ys = Int[sc.y for sc in segments if step < 0 ? sc.y < y : sc.y > y]
        if !isempty(ys)
            row = step < 0 ? maximum(ys) : minimum(ys)
            return filter(sc -> sc.y == row, segments)
        end
        L += step
        1 <= L <= count || return SegmentCoordinate[]
        segments = _get_line_segments(places, L)
    end
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
    places = iomap.places
    places === nothing ? _find_flat_caret(iomap.input, seg.span_path, char_pos) :
                         _find_flat_caret(iomap.input, seg.span_path, char_pos, places)
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
    _highlight_char_range(sel) -> (start, stop, space) or nothing

Extract the flat character range to highlight from the TextBlock's selection,
and the space its offsets are in (see `_TextPlaces`). Recognized shapes:
- `EmptyReference` (∅) → the full extent, in the box space.
- `ConcreteReference(TextRangeReferenceStep(s, e), ∅)` with `s != e` → `(s, e)`,
  in the caret space.
- `ConcreteReference(TextSpanReferenceStep(s, e), ∅)` → `(s, e)`, in the box space.
Returns `nothing` for any other selection shape (normal cursor, etc.).
"""
function _highlight_char_range(sel)
    # Cover all segments: use a large sentinel that exceeds any absolute offset.
    sel isa EmptyReference && return (0, typemax(Int) >> 1, :box)
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
For an `Image`, or an `ImageFile` that holds one, it returns the pixel cell itself,
which only the paint of a backend reads. Else it returns whatever the content's
`.raw` cell holds, untouched:

- a `(pixels::Vector{UInt8}, native_w, native_h)` tuple from the decoder —
  the native size travels with the bytes so the backend can build the
  surface correctly and scale it to the span's display box,
- a bare `Vector{UInt8}` or cached texture `Ptr`,
- or `nothing` until the image is decoded.
"""
function _extract_image_data(span::TextGraphics)
    content = get_shown_picture(span.content)
    content === nothing && return nothing
    content isa Image && return getfield(content, :pixels)
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
- otherwise (an `Image`, an `ImageFile` or an `ImageMemory`) it is rasterized to
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

