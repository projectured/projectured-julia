# Fragment of `WidgetModule` — a line of text that a widget drew, with the part of
# the input of the widget that the line shows. A widget that keeps these records
# puts the caret at the character under the pointer on a plain click, draws a caret
# that lies in the part on its line, and names the part under the pointer on a move.

"""
    DrawnTextLine(text, part, start)

A line of text that a widget drew: the `GraphicsText` element `text`, the path
`part` from the widget to the part of its input that the line shows, such as
`.title`, and the character of that part where the line starts, `start`. The
record holds the element itself, because a printer can put other elements before
it after it drew it.
"""
struct DrawnTextLine
    text::Any
    part::Reference
    start::Int
end

# The character of `text` where each of `lines`, the lines that the text breaks into
# in order, starts. A line that is cut with "…" starts where its text does.
function _find_line_starts(text::AbstractString, lines)
    starts = Int[]
    position = firstindex(text)
    for line in lines
        shown = endswith(line, "…") ? line[1:prevind(line, lastindex(line))] : line
        found = isempty(shown) ? nothing : findnext(shown, text, position)
        index = found === nothing ? position : first(found)
        push!(starts, index > lastindex(text) ? length(text) : length(text, firstindex(text), prevind(text, index)))
        found === nothing || (position = nextind(text, last(found)))
    end
    starts
end

_get_drawn_string(line::DrawnTextLine) = String(unwrap_cell(getfield(line.text, :text)))

# The path from `node` to `element`, an element of a canvas or of a viewport below
# `node`, found by identity; `nothing` when `node` does not hold it.
function _find_element_path(node, element)
    node = unwrap_cell(node)
    node === element && return EmptyReference()
    if node isa GraphicsCanvas
        elements = unwrap_cell(getfield(node, :elements))
        elements isa Union{AbstractVector, CellVector} || return nothing
        for k in 1:length(elements)
            inner = _find_element_path(elements[k], element)
            inner === nothing ||
                return ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(ElementReferenceStep(k), inner))
        end
    elseif node isa GraphicsViewport
        inner = _find_element_path(getfield(node, :content), element)
        inner === nothing || return ConcreteReference(FieldReferenceStep("content"), inner)
    end
    nothing
end

# The place of the characters `start:stop` of the line in `canvas`.
_make_line_place(path, start::Int, stop::Int) =
    concat_references(path, ConcreteReference(FieldReferenceStep("text"),
                                              ConcreteReference(RangeReferenceStep(start, stop), EmptyReference())))

# The caret before the character `k` of `part`.
_make_part_caret(part::Reference, k::Int) =
    concat_references(part, ConcreteReference(RangeReferenceStep(k, k), EmptyReference()))

"""
    find_drawn_caret(drawn, canvas, x, y, measure) -> Reference | Nothing

The caret that a plain click at `(x, y)`, in the frame of `canvas`, the output of
the widget, puts into the part that a line of `drawn` shows: `part{start + c}`,
where `c` is the place between two characters of the line nearest the point.
`nothing` when no line of `drawn` holds the point.
"""
function find_drawn_caret(drawn, canvas, x, y, measure)
    (isempty(drawn) || !(canvas isa GraphicsCanvas)) && return nothing
    ox, oy = Int(unwrap_cell(getfield(canvas, :x))), Int(unwrap_cell(getfield(canvas, :y)))
    for line in drawn
        path = _find_element_path(canvas, line.text)
        path === nothing && continue
        box = find_reference_box(canvas, path; measure)
        box === nothing && continue
        left, top = box.x - ox, box.y - oy
        (left <= x < left + box.width && top <= y < top + box.height) || continue
        text = _get_drawn_string(line)
        offsets = compute_caret_offsets(measure, text, unwrap_cell(getfield(line.text, :font)))
        c = argmin(k -> abs(offsets[k + 1] - (x - left)), 0:length(text))
        return _make_part_caret(line.part, line.start + c)
    end
    nothing
end

# The line of `drawn` that shows the characters `start:stop` of `part`, or `nothing`.
function _find_drawn_line(drawn, part::Reference, start::Int, stop::Int)
    for line in drawn
        strip_reference_types(line.part) == part || continue
        line.start <= start && stop <= line.start + length(_get_drawn_string(line)) && return line
    end
    nothing
end

# The part and the range at the end of `reference`, a caret or a range of
# characters of a part, or `nothing`.
function _split_part_range(reference)
    reference isa ConcreteReference || return nothing
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    range = last(steps)
    range isa RangeReferenceStep || return nothing
    (foldr(ConcreteReference, steps[1:(end - 1)]; init = EmptyReference()), range)
end

"""
    map_drawn_caret_forward(drawn, canvas, reference) -> Reference | Nothing

The place in `canvas` of `reference`, a caret or a range in a part that a line of
`drawn` shows: the characters of that line, `….text{a:b}`, whose box the graphics
give. `nothing` for any other reference.
"""
function map_drawn_caret_forward(drawn, canvas, reference)
    split = _split_part_range(reference)
    split === nothing && return nothing
    part, range = split
    line = _find_drawn_line(drawn, part, range.start, range.stop)
    line === nothing && return nothing
    path = _find_element_path(canvas, line.text)
    path === nothing && return nothing
    _make_line_place(path, range.start - line.start, range.stop - line.start)
end

"""
    map_drawn_place_backward(drawn, canvas, reference) -> Reference | Nothing

The part that `reference`, a place of characters of a line of `drawn` in
`canvas`, shows: `part{start + a : start + b}`. `nothing` for any other reference.
"""
function map_drawn_place_backward(drawn, canvas, reference)
    split = _split_part_range(reference)
    split === nothing && return nothing
    place, range = split
    for line in drawn
        path = _find_element_path(canvas, line.text)
        path === nothing && continue
        text = concat_references(path, ConcreteReference(FieldReferenceStep("text"), EmptyReference()))
        strip_reference_types(text) == place || continue
        return concat_references(line.part, ConcreteReference(
            RangeReferenceStep(line.start + range.start, line.start + range.stop), EmptyReference()))
    end
    nothing
end

"""
    make_drawn_caret_elements(drawn, selection, measure) -> Vector{Any}

The caret of a widget that keeps the records `drawn`: one thin rectangle in the
colour of the line, at the place of `selection`, the stored selection of the
widget, while it is a caret in a part that a line shows, and no element else. The
widget appends it to the elements of the canvas that holds the lines, so a widget
that holds no caret has no element and no cell for it.
"""
function make_drawn_caret_elements(drawn, selection, measure)
    place = _find_drawn_caret_place(drawn, selection, measure)
    place === nothing && return Any[]
    Any[GraphicsRect(place.x, place.y, 2, place.height; color = place.color)]
end

# The place of the caret `selection` on its line, in the frame of the canvas of
# the line, or `nothing`.
function _find_drawn_caret_place(drawn, selection, measure)
    split = _split_part_range(selection)
    split === nothing && return nothing
    part, range = split
    range.start == range.stop || return nothing
    line = _find_drawn_line(drawn, part, range.start, range.stop)
    line === nothing && return nothing
    text = _get_drawn_string(line)
    font = unwrap_cell(getfield(line.text, :font))
    offsets = compute_caret_offsets(measure, text, font)
    _, ascent, descent = compute_text_extent(measure, text, font)
    (x = round(Int, unwrap_cell(getfield(line.text, :x)) + offsets[range.start - line.start + 1]),
     y = round(Int, unwrap_cell(getfield(line.text, :y))),
     height = round(Int, ascent + descent), color = unwrap_cell(getfield(line.text, :color)))
end
