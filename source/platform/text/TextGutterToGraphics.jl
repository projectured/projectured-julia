# Fragment of `TextModule`.
#
# The gutter of a line of code as graphics: three lanes in one row, the marker,
# the number and the fold, from the left. Each mark is printed by the recursion,
# so a mark can be any document, and each lane is at least as wide as the width
# that the builder gives, so the lanes of all the lines stand in columns.

"""
    TextGutterToGraphics(; marker_width = 16, number_width = 0, fold_width = 16, gap = 4)

Draw a [`TextGutter`](@ref) as one row of three lanes, from the left: the marker,
the number and the fold. A lane is as wide as its mark, and at least as wide as
its width here, so a lane keeps its width on a line that has no mark in it. A
stage that wants a lane to grow, as the numbers do at a new digit, gives every
mark of the lane the same width. A marker and a fold stand in the middle of their
lane and a number at its right, and `gap` pixels follow each lane.

The marks that draw text stand on one baseline, and a mark that draws none stands
in the middle of the height of the row. A chain that holds marks needs a
recursion, because the recursion prints each mark.
"""
@projection UntrackedCell struct TextGutterToGraphics
    marker_width::Int = 16
    number_width::Int = 0
    fold_width::Int = 16
    gap::Int = 4
end

# The lanes of a `TextGutter`, from the left: the field and the alignment.
const _GUTTER_LANES = ((:marker, :center), (:number, :right), (:fold, :center))

_get_gutter_lane_minimum(p::TextGutterToGraphics, lane::Symbol) =
    lane === :marker ? p.marker_width : lane === :number ? p.number_width : p.fold_width

# The width and the height of what an IO map printed.
function _get_printed_size(iomap)
    output = iomap.output
    output isa GraphicsCanvas && return (Int(output.w[]), Int(output.h[]))
    output isa GraphicsDocument && return Tuple(Int.(get_graphics_size(output)))
    (0, 0)
end

# Where each mark of a gutter stands, from the IO maps of its marks (`nothing`
# for a lane with no mark): the `(x, y)` of each mark, and the width and the
# height of the row.
function _place_gutter_marks(p::TextGutterToGraphics, iomaps::Vector)
    sizes = Any[iomap === nothing ? nothing : _get_printed_size(iomap) for iomap in iomaps]
    baselines = Any[iomap === nothing ? nothing : find_first_baseline(iomap) for iomap in iomaps]
    row_baseline = 0
    for b in baselines
        b === nothing || (row_baseline = max(row_baseline, b))
    end
    height = 0
    for (k, size) in enumerate(sizes)
        size === nothing && continue
        b = baselines[k]
        height = max(height, b === nothing ? size[2] : row_baseline - b + size[2])
    end
    places = Any[]
    x = 0
    for (k, (lane, align)) in enumerate(_GUTTER_LANES)
        size = sizes[k]
        width = max(_get_gutter_lane_minimum(p, lane), size === nothing ? 0 : size[1])
        if size === nothing
            push!(places, nothing)
        else
            mark_x = align === :right ? width - size[1] :
                     align === :center ? div(width - size[1], 2) : 0
            b = baselines[k]
            mark_y = b === nothing ? div(height - size[2], 2) : row_baseline - b
            push!(places, (x + mark_x, mark_y))
        end
        x += width + p.gap
    end
    (places = places, width = x, height = height)
end

function _print_gutter_marks(recursion, gutter::TextGutter, ctx)
    recursion === nothing &&
        throw(ArgumentError("TextGutterToGraphics: a gutter needs a recursion to print its marks"))
    iomaps = Any[]
    for (lane, _) in _GUTTER_LANES
        mark = getproperty(gutter, lane)
        if mark === nothing
            push!(iomaps, nothing)
            continue
        end
        mark_ctx = with_exact_size(make_child_context(ctx, gutter, FieldReferenceStep(String(lane)));
                                   width = nothing, height = nothing)
        push!(iomaps, print_child(recursion, mark, mark_ctx))
    end
    iomaps
end

function print_document(p::TextGutterToGraphics, recursion, gutter::TextGutter, ctx)
    # The marks are printed again when a field of the gutter holds another mark.
    iomaps = Cell(@computation _print_gutter_marks(recursion, gutter, ctx))
    placed = Cell(@computation _place_gutter_marks(p, iomaps[]))
    entries = Cell(Computation(function ()
        out = Any[]
        for (k, iomap) in enumerate(iomaps[])
            if iomap === nothing
                push!(out, nothing)
                continue
            end
            x = Cell(@computation Int32(placed[].places[k][1]))
            y = Cell(@computation Int32(placed[].places[k][2]))
            push!(out, (x, y, iomap))
        end
        out
    end))
    elements = CellVector(Computation(function ()
        out = Any[]
        for entry in entries[]
            entry === nothing && continue
            x, y, iomap = entry
            output = iomap.output
            output isa GraphicsDocument || continue
            push!(out, GraphicsCanvas(x, y, Cell(Int32(0)), Cell(Int32(0)),
                                      CellVector(Cell[Cell(output)]), layout_none, true, Cell(nothing)))
        end
        out
    end))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)),
                            Cell(@computation Int32(placed[].width)),
                            Cell(@computation Int32(placed[].height)),
                            elements, layout_none, true, Cell(nothing))
    ChildrenIoMap(p, gutter, canvas, entries)
end

# The index of the lane named `name`, or `nothing`.
_find_gutter_lane(name::AbstractString) = findfirst(((lane, _),) -> String(lane) == name, _GUTTER_LANES)

# The steps from a gutter to the mark of lane `k`.
_get_gutter_lane_steps(k::Integer) = (FieldReferenceStep(String(_GUTTER_LANES[k][1])),)

# `lane/...` maps to the node that draws the mark, followed by what the mark's
# own mapper answers.
function map_reference_forward(::TextGutterToGraphics, iomap, reference)
    reference isa Reference || return nothing
    reference = strip_reference_types(reference)
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    head = reference.head
    head isa FieldReferenceStep || return nothing
    k = _find_gutter_lane(head.name)
    k === nothing && return nothing
    entries = getfield(iomap, :child_iomaps)[]::Vector
    entries[k] === nothing && return nothing
    mark = entries[k][3]
    mark.output isa GraphicsDocument || return nothing
    # The mark as a whole is the node that draws it.
    inner = reference.tail isa EmptyReference ? EmptyReference() :
            map_reference_forward(mark.projection, mark, reference.tail)
    inner === nothing && return nothing
    make_slot_reference(iomap.output, entries, k, inner)
end

# The lane whose mark draws the point `(x, y)` of the gutter, and the point in
# the frame of that mark, or `nothing`.
function _find_gutter_mark_at(entries::Vector, x::Int, y::Int)
    for (k, entry) in enumerate(entries)
        entry === nothing && continue
        mark_x, mark_y, mark = entry
        lx, ly = x - Int(mark_x[]), y - Int(mark_y[])
        w, h = _get_printed_size(mark)
        (0 <= lx < w && 0 <= ly < h) && return (k, lx, ly)
    end
    nothing
end

# A point maps to the mark drawn at it, and a path into the canvas to the mark of
# its slot, each on into the mark.
function map_reference_backward(::TextGutterToGraphics, iomap, reference)
    entries = getfield(iomap, :child_iomaps)[]::Vector
    point = find_reference_point(reference)
    if point !== nothing
        found = _find_gutter_mark_at(entries, Int(point.x), Int(point.y))
        found === nothing && return nothing
        k, lx, ly = found
        mark = entries[k][3]
        # A mark that names no part at the point, such as a shape that answers the
        # point itself, is itself the part there.
        inside = map_reference_backward(mark.projection, mark, PointReferenceStep(lx, ly))
        inside isa Reference || (inside = EmptyReference())
        return annotate_reference_types(iomap.input, ConcreteReference(_get_gutter_lane_steps(k)[1], inside))
    end
    reference isa ConcreteReference || return nothing
    head = reference.head
    (head isa FieldReferenceStep && head.name == "elements") || return nothing
    outer = reference.tail
    (outer isa ConcreteReference && outer.head isa RangeReferenceStep) || return nothing
    slot = outer.head.start + 1
    seen = 0
    for (k, entry) in enumerate(entries)
        (entry === nothing || !(entry[3].output isa GraphicsDocument)) && continue
        seen += 1
        seen == slot || continue
        mark = entry[3]
        below = outer.tail
        inside = EmptyReference()
        if below isa ConcreteReference
            element = below.tail
            (below.head isa FieldReferenceStep && below.head.name == "elements" &&
             element isa ConcreteReference && element.head isa RangeReferenceStep) || return nothing
            # A path that ends at the node of the mark names the mark itself.
            element.tail isa EmptyReference ||
                (inside = map_reference_backward(mark.projection, mark, element.tail))
            inside === nothing && return nothing
        end
        return annotate_reference_types(iomap.input, ConcreteReference(_get_gutter_lane_steps(k)[1], inside))
    end
    nothing
end

# A pointer event goes to the mark at its point, and an event with no point to the
# mark that the selection of the gutter names. The answer comes back re-rooted into
# the field of the lane.
function read_intent(::TextGutterToGraphics, iomap::ChildrenIoMap, evt)
    entries = getfield(iomap, :child_iomaps)[]::Vector
    gutter = iomap.input
    if evt isa Union{MouseClick, MouseDown, MouseUp, MouseMove, MouseScroll, MouseDwell}
        found = _find_gutter_mark_at(entries, Int(evt.x), Int(evt.y))
        found === nothing && return nothing
        k, lx, ly = found
        answer = read_child_event(entries[k][3], shift_event_position(evt, lx - Int(evt.x), ly - Int(evt.y)))
        answer = shift_operation_position(answer, Int(evt.x) - lx, Int(evt.y) - ly)
        return _reroot_gutter_answer(gutter, answer, k)
    end
    evt isa Operation && return nothing
    path = getfield(gutter, :selection)[]
    path isa ConcreteReference && path.head isa FieldReferenceStep || return nothing
    k = _find_gutter_lane(path.head.name)
    (k === nothing || entries[k] === nothing) && return nothing
    mark = entries[k][3]
    _reroot_gutter_answer(gutter, read_intent(mark.projection, mark, evt), k)
end

function _reroot_gutter_answer(gutter, answer, k::Integer)
    answer isa Operation || return nothing
    rerooted = reroot_operation(answer, _get_gutter_lane_steps(k))
    rerooted isa ReplacePathOperation || return rerooted
    make_path_operation(rerooted, annotate_reference_types(gutter, get_operation_path(rerooted)))
end
