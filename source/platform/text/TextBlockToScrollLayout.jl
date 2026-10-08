# Fragment of `TextModule`.
#
# A text with a gutter as a `ScrollLayout`: the lines as its center, laid out by
# `TextToGraphics`, and the gutter of each `TextLine` as its left edge, each gutter
# at the height of its line. One projection lays out both parts, so their rows
# agree by construction, and a scroll pane keeps the gutter at its left edge while
# the lines scroll.

"""
    TextBlockToScrollLayout(; measure, theme = nothing, start_x = 0, start_y = 0,
                            line_spacing = SingleSpacing())

Draw a `TextBlock` as a [`ScrollLayout`](@ref). The center is the canvas of the
lines, with the caret and the band of the selection, as `TextToGraphics` draws
it with the same keywords. The left edge holds the gutter of each `TextLine`,
printed by the recursion, with its first baseline on the first baseline of its
line, or in the middle of the line when it draws no text. The left edge is as
high as the lines and as wide as the gutter of the first line that has one: the
projection of a gutter gives every line the same width.

A point, a click and a pointer event go to the part at the point, in the frame in
which the parts are put together: on the lines to `TextToGraphics`, on a gutter
to the projection of that gutter, re-rooted into `.elements[i].gutter`. A click
on a gutter that gives no operation selects the mark at the point, so the stage
that made the mark can answer it. A key goes to the gutter that the selection is
in, and else to the lines. A chain that holds gutters needs a recursion.
"""
@projection UntrackedCell struct TextBlockToScrollLayout
    text::Any        # the `TextToGraphics` that lays out the lines
end

TextBlockToScrollLayout(; measure::TextMeasure, kwargs...) =
    TextBlockToScrollLayout(TextToGraphics(; measure, kwargs...))

"""
    TextBlockToScrollLayoutIoMap

The IO map of `TextBlockToScrollLayout`: the IO map of the lines, `lines_iomap`,
and the rows of the gutter, a cell of one entry for each line that has a gutter,
`(group, line, iomap, row)`: the line group, the index of the `TextLine` among the
elements, the IO map of its gutter, and the canvas that places it.
"""
@iomap struct TextBlockToScrollLayoutIoMap
    projection::Any
    input::TextBlock
    output::Any
    lines_iomap::Any
    gutter_rows::Cell
end

# A row of the gutter: the output of the gutter of `line`, placed at the height of
# that line, wherever it stands.
function _make_gutter_row(lines_iomap, line::TextLine, gutter_iomap)
    cells = lines_iomap.line_cells(line)
    y = Cell(Computation(function ()
        top = Int(cells.y[])
        baseline = cells.layout[].first_baseline
        gutter_baseline = find_first_baseline(gutter_iomap)
        (baseline === nothing || gutter_baseline === nothing) &&
            return Int32(top + div(Int(cells.h[]) - _get_printed_size(gutter_iomap)[2], 2))
        Int32(top + baseline - gutter_baseline)
    end))
    GraphicsCanvas(Cell(Int32(0)), y, Cell(Int32(0)), Cell(Int32(0)),
                   CellVector(Cell[Cell(gutter_iomap.output)]), layout_none, true, Cell(nothing))
end

function print_document(p::TextBlockToScrollLayout, recursion, block::TextBlock, ctx)
    lines_iomap = print_document(p.text, recursion, block, ctx)
    lines_canvas = lines_iomap.output
    # A lazy text has no line cells, and no gutter yet.
    lines_iomap.line_cells === nothing &&
        return TextBlockToScrollLayoutIoMap(p, block, ScrollLayout(; center = lines_canvas),
                                            lines_iomap, Cell(Any[]))
    gutter_ctx = with_exact_size(ctx === nothing ? PrinterContext() : ctx; width = nothing, height = nothing)
    # Each gutter is printed once and each row made once, and they are kept while
    # their line keeps its gutter, so a new layout reuses them.
    printed = IdDict{Any, Any}()
    rows = Dict{Any, Any}()
    gutter_rows = Cell(Computation(function ()
        out = NamedTuple[]
        live_gutters = Set{Any}()
        live_rows = Set{Any}()
        for (group, line_group) in enumerate(unwrap_cell(lines_iomap.lines))
            line_group.line == 0 && continue
            line = block.elements[line_group.line]
            line isa TextLine || continue
            gutter = line.gutter
            gutter === nothing && continue
            recursion === nothing &&
                throw(ArgumentError("TextBlockToScrollLayout: a gutter needs a recursion to print it"))
            gutter_iomap = get!(printed, gutter) do
                path = (FieldReferenceStep("elements"), RangeReferenceStep(line_group.line - 1, line_group.line),
                        FieldReferenceStep("gutter"))
                print_child(recursion, gutter, make_child_context(gutter_ctx, block, path...))
            end
            # A row stays with its line, so a line inserted above it makes no row again.
            key = (objectid(line), objectid(gutter))
            row = get!(() -> _make_gutter_row(lines_iomap, line, gutter_iomap), rows, key)
            push!(live_gutters, gutter)
            push!(live_rows, key)
            push!(out, (group = group, line = line_group.line, iomap = gutter_iomap, row = row))
        end
        for gutter in collect(keys(printed))
            gutter in live_gutters || delete!(printed, gutter)
        end
        for key in collect(keys(rows))
            key in live_rows || delete!(rows, key)
        end
        out
    end))
    gutter_w = Cell(Computation(function ()
        entries = gutter_rows[]
        isempty(entries) ? Int32(0) : Int32(_get_printed_size(first(entries).iomap)[1])
    end))
    gutter_h = getfield(lines_canvas, :h)
    # A press on the gutter puts no caret, so the pointer is an arrow over it.
    arrow = GraphicsPointerShape(0, 0, () -> gutter_w[], () -> gutter_h[], :arrow)
    gutter_canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), gutter_w, gutter_h,
                                   CellVector(Computation(() -> vcat(Any[e.row for e in gutter_rows[]],
                                                                    Any[arrow]))),
                                   layout_none, true, Cell(nothing))
    output = ScrollLayout(; center = lines_canvas, left = gutter_canvas)
    TextBlockToScrollLayoutIoMap(p, block, output, lines_iomap, gutter_rows)
end

find_first_baseline(iomap::TextBlockToScrollLayoutIoMap) = find_first_baseline(iomap.lines_iomap)

# The steps from the block to the gutter of the `TextLine` at element `line`.
_get_gutter_steps(line::Integer) =
    (FieldReferenceStep("elements"), RangeReferenceStep(line - 1, line), FieldReferenceStep("gutter"))

# The entry of the gutter row of the `TextLine` at element `line`, and its index
# among the rows, or `nothing`.
function _find_gutter_row(iomap::TextBlockToScrollLayoutIoMap, line::Integer)
    for (index, entry) in enumerate(unwrap_cell(iomap.gutter_rows))
        entry.line == line && return (index, entry)
    end
    nothing
end

# A reference that names the gutter of a line, `.elements[i].gutter…`: the index
# `i` and the rest of the reference, or `nothing`.
function _split_gutter_reference(reference)
    reference isa ConcreteReference || return nothing
    (reference.head isa FieldReferenceStep && reference.head.name == "elements") || return nothing
    indexed = reference.tail
    (indexed isa ConcreteReference && indexed.head isa RangeReferenceStep) || return nothing
    field = indexed.tail
    (field isa ConcreteReference && field.head isa FieldReferenceStep && field.head.name == "gutter") ||
        return nothing
    (indexed.head.start + 1, field.tail)
end

_prefix_reference(step::ReferenceStep, rest) = rest === nothing ? nothing : ConcreteReference(step, rest)

# A reference into the gutter of a line maps to its row in the left edge, and any
# other reference into the text maps through the lines to the center.
function map_reference_forward(p::TextBlockToScrollLayout, iomap::TextBlockToScrollLayoutIoMap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    split = _split_gutter_reference(reference)
    if split !== nothing
        line, rest = split
        found = _find_gutter_row(iomap, line)
        found === nothing && return nothing
        index, entry = found
        gutter = entry.iomap
        inner = rest isa EmptyReference ? EmptyReference() :
                map_reference_forward(gutter.projection, gutter, rest)
        inner === nothing && return nothing
        return ConcreteReference(FieldReferenceStep("left"),
            ConcreteReference(FieldReferenceStep("elements"),
                ConcreteReference(RangeReferenceStep(index - 1, index),
                    ConcreteReference(FieldReferenceStep("elements"),
                        ConcreteReference(RangeReferenceStep(0, 1), inner)))))
    end
    lines = iomap.lines_iomap
    _prefix_reference(FieldReferenceStep("center"), map_reference_forward(lines.projection, lines, reference))
end

# The widths and the heights of the columns and the rows of the output.
function _get_text_layout_extents(iomap::TextBlockToScrollLayoutIoMap)
    output = iomap.output
    sizes = Any[nothing for _ in SCROLL_LAYOUT_PARTS]
    for (index, part) in enumerate(SCROLL_LAYOUT_PARTS)
        canvas = getproperty(output, part)
        canvas isa GraphicsCanvas && (sizes[index] = (Int(canvas.w[]), Int(canvas.h[])))
    end
    compute_scroll_layout_extents(sizes)
end

# The part at the point `(x, y)` of the frame in which the parts are put
# together: `(part, x, y)` with the point in the frame of the part, or `nothing`.
function _find_text_part_at(iomap::TextBlockToScrollLayoutIoMap, x::Int, y::Int)
    widths, heights = _get_text_layout_extents(iomap)
    index = find_scroll_layout_part_at(x, y, widths, heights)
    index === nothing && return nothing
    place_x, place_y = get_scroll_layout_place(index, widths, heights)
    (SCROLL_LAYOUT_PARTS[index], x - place_x, y - place_y)
end

# The row of the gutter at the height `y` of the left edge, with `y` in the frame
# of its gutter: `(entry, y)`, or `nothing`.
function _find_gutter_row_at(iomap::TextBlockToScrollLayoutIoMap, x::Int, y::Int)
    for entry in unwrap_cell(iomap.gutter_rows)
        local_y = y - Int(entry.row.y[])
        w, h = _get_printed_size(entry.iomap)
        (0 <= x < w && 0 <= local_y < h) && return (entry, local_y)
    end
    nothing
end

# A point maps to the part at it, and a path in a part maps through that part:
# on the lines through `TextToGraphics`, on a gutter through its projection, into
# `.elements[i].gutter`.
function map_reference_backward(p::TextBlockToScrollLayout, iomap::TextBlockToScrollLayoutIoMap, reference)
    lines = iomap.lines_iomap
    point = find_reference_point(reference)
    if point !== nothing
        found = _find_text_part_at(iomap, Int(point.x), Int(point.y))
        found === nothing && return nothing
        part, x, y = found
        part === :center &&
            return map_reference_backward(lines.projection, lines, PointReferenceStep(x, y))
        part === :left || return nothing
        row = _find_gutter_row_at(iomap, x, y)
        row === nothing && return nothing
        entry, local_y = row
        gutter = entry.iomap
        inside = map_reference_backward(gutter.projection, gutter, PointReferenceStep(x, local_y))
        inside isa Reference || (inside = EmptyReference())
        return _make_gutter_path(iomap.input, entry.line, inside)
    end
    reference isa ConcreteReference || return nothing
    head = reference.head
    head isa FieldReferenceStep || return nothing
    head.name == "center" && return map_reference_backward(lines.projection, lines, reference.tail)
    head.name == "left" || return nothing
    rest = reference.tail
    (rest isa ConcreteReference && rest.head isa FieldReferenceStep && rest.head.name == "elements") ||
        return nothing
    indexed = rest.tail
    (indexed isa ConcreteReference && indexed.head isa RangeReferenceStep) || return nothing
    entries = unwrap_cell(iomap.gutter_rows)
    index = indexed.head.start + 1
    1 <= index <= length(entries) || return nothing
    entry = entries[index]
    below = indexed.tail
    inside = EmptyReference()
    if below isa ConcreteReference
        element = below.tail
        (below.head isa FieldReferenceStep && below.head.name == "elements" &&
         element isa ConcreteReference && element.head isa RangeReferenceStep) || return nothing
        gutter = entry.iomap
        element.tail isa EmptyReference ||
            (inside = map_reference_backward(gutter.projection, gutter, element.tail))
        inside === nothing && return nothing
    end
    _make_gutter_path(iomap.input, entry.line, inside)
end

function _make_gutter_path(block::TextBlock, line::Integer, inside)
    path = inside
    for step in Base.reverse(_get_gutter_steps(line))
        path = ConcreteReference(step, path)
    end
    annotate_reference_types(block, path)
end

# A pointer event goes to the part at its point.
const _TextPointerEvent = Union{MouseClick, MouseDown, MouseUp, MouseMove, MouseScroll, MouseDwell}

function read_intent(p::TextBlockToScrollLayout, iomap::TextBlockToScrollLayoutIoMap, evt::_TextPointerEvent)
    lines = iomap.lines_iomap
    found = _find_text_part_at(iomap, Int(evt.x), Int(evt.y))
    found === nothing && return nothing
    part, x, y = found
    dx, dy = Int(evt.x) - x, Int(evt.y) - y
    if part === :center
        answer = read_intent(lines.projection, lines, shift_event_position(evt, -dx, -dy))
        return answer isa Operation ? shift_operation_position(answer, dx, dy) : answer
    end
    part === :left || return nothing
    row = _find_gutter_row_at(iomap, x, y)
    row === nothing && return nothing
    entry, local_y = row
    gutter = entry.iomap
    dy += y - local_y
    answer = read_child_event(gutter, shift_event_position(evt, -dx, -dy))
    if answer isa Operation
        rerooted = reroot_operation(shift_operation_position(answer, dx, dy), _get_gutter_steps(entry.line))
        rerooted isa ReplacePathOperation || return rerooted
        return make_path_operation(rerooted, annotate_reference_types(iomap.input, get_operation_path(rerooted)))
    end
    # A click that the gutter does not take selects the mark at the point, so the
    # stage that made the mark can answer it.
    evt isa MouseClick || return nothing
    inside = map_reference_backward(gutter.projection, gutter, PointReferenceStep(x, local_y))
    inside isa Reference || return nothing
    ReplaceSelectionOperation(_make_gutter_path(iomap.input, entry.line, inside))
end

# An operation in the output maps back as a path does; a key goes to the gutter
# that the selection is in, and else to the lines.
function read_intent(p::TextBlockToScrollLayout, iomap::TextBlockToScrollLayoutIoMap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, get_operation_path(op))
    path === nothing ? nothing : make_path_operation(op, path)
end

function read_intent(p::TextBlockToScrollLayout, iomap::TextBlockToScrollLayoutIoMap, payload)
    selection = get_selection(iomap.input)
    split = selection isa Reference ? _split_gutter_reference(strip_reference_types(selection)) : nothing
    if split !== nothing && !(payload isa Operation)
        found = _find_gutter_row(iomap, split[1])
        found === nothing && return nothing
        entry = found[2]
        gutter = entry.iomap
        answer = read_intent(gutter.projection, gutter, payload)
        answer isa Operation || return nothing
        rerooted = reroot_operation(answer, _get_gutter_steps(entry.line))
        rerooted isa ReplacePathOperation || return rerooted
        return make_path_operation(rerooted, annotate_reference_types(iomap.input, get_operation_path(rerooted)))
    end
    lines = iomap.lines_iomap
    read_intent(lines.projection, lines, payload)
end
