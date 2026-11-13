# Fragment of `WidgetModule` — a line of text that a widget drew, with the part of
# the input of the widget that the line shows. A widget that keeps these records
# puts the caret at the character under the pointer on a plain click, draws a caret
# that lies in the part on its line and a band behind a part selected as a whole and
# behind the characters of a range, names the part under the pointer on a move, and
# moves the caret and the range on a key.

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
    read_drawn_text_key(drawn, widget, event, measure) -> ReplaceSelectionOperation | Nothing

The answer to the key `event` while the selection of `widget` is a caret or a range
in a part that a line of `drawn` shows, or that part as a whole, which is the range
of all its characters: the new caret or range of that part, as `part{a:b}`. The key
table of the text domain answers the key on a short-lived text block of the string
of the part, which nothing draws or keeps; Home, End, Up and Down read the lines of
`drawn`. An answer that edits is dropped, so the text stays read-only. `nothing` for
any other key or selection, and for Up on the first line and Down on the last, so
the key goes on to the container.
"""
function read_drawn_text_key(drawn, widget, event, measure)
    event isa Union{KeyDown, KeyPress} || return nothing
    selection = widget.selection
    selection isa ConcreteReference || return nothing
    found = _split_part_range(selection)
    part, range = found === nothing ? (strip_reference_types(selection), nothing) : found
    # On a part as a whole, Up and Down go on to the container, as on a whole element.
    range === nothing && event isa KeyDown && event.key in (:up, :down) && return nothing
    lines = [line for line in drawn if strip_reference_types(line.part) == part]
    isempty(lines) && return nothing
    value = try_evaluate_reference(widget, part, nothing)
    value === nothing && return nothing
    text = string(value)
    anchor, moving = range === nothing ? (0, length(text)) :
                     range.direction === :backward ? (range.stop, range.start) : (range.start, range.stop)
    answer = event isa KeyDown ? _read_drawn_line_key(lines, event, anchor, moving, measure) : nothing
    answer === nothing && (answer = _read_text_table_key(text, event, anchor, moving))
    answer === nothing && return nothing
    (a, b) = answer
    ReplaceSelectionOperation(concat_references(part, ConcreteReference(
        RangeReferenceStep(min(a, b), max(a, b), b < a ? :backward : :forward), EmptyReference())))
end

# The new anchor and moving end that the key table of the text domain answers on a
# block of `text` with that selection, or `nothing` for an answer that is no move of
# the selection.
function _read_text_table_key(text, event, anchor, moving)
    block = TextBlock((TextLine(TextString(String(line))) for line in split(text, '\n'))...)
    set_selection!(block, make_flat_range_reference(min(anchor, moving), max(anchor, moving);
                                                    direction = moving < anchor ? :backward : :forward))
    answer = read_gesture(block, event)
    answer isa ReplaceSelectionOperation || return nothing
    path = strip_reference_types(answer.path)
    (path isa ConcreteReference && path.head isa TextRangeReferenceStep && path.tail isa EmptyReference) ||
        return nothing
    step = path.head
    step.direction === :backward ? (step.stop, step.start) : (step.start, step.stop)
end

# Home and End on the drawn line of the moving end, and Up and Down to the nearest
# character of the line above or below; Shift keeps the anchor. `nothing` for any
# other key, and where no line is above or below.
function _read_drawn_line_key(lines, event::KeyDown, anchor, moving, measure)
    event.key in (:home, :end, :up, :down) || return nothing
    modifiers = event.modifiers
    (modifiers.ctrl || modifiers.alt || modifiers.meta) && return nothing
    index = findfirst(line -> line.start <= moving <= line.start + length(_get_drawn_string(line)), lines)
    index === nothing && return nothing
    line = lines[index]
    target = if event.key === :home
        line.start
    elseif event.key === :end
        line.start + length(_get_drawn_string(line))
    else
        other = event.key === :up ? index - 1 : index + 1
        1 <= other <= length(lines) || return nothing
        x = _get_drawn_line_x(line, moving - line.start, measure)
        _find_nearest_drawn_character(lines[other], x, measure)
    end
    (modifiers.shift ? anchor : target, target)
end

# The x of the place before the character `k` of `line`, in the frame of its canvas.
function _get_drawn_line_x(line::DrawnTextLine, k::Int, measure)
    offsets = compute_caret_offsets(measure, _get_drawn_string(line), unwrap_cell(getfield(line.text, :font)))
    unwrap_cell(getfield(line.text, :x)) + offsets[k + 1]
end

# The character of the part where the place of `line` nearest to `x` is.
function _find_nearest_drawn_character(line::DrawnTextLine, x, measure)
    text = _get_drawn_string(line)
    offsets = compute_caret_offsets(measure, text, unwrap_cell(getfield(line.text, :font)))
    left = unwrap_cell(getfield(line.text, :x))
    line.start + argmin(k -> abs(left + offsets[k + 1] - x), 0:length(text))
end

"""
    make_drawn_selection_elements(elements, drawn, selection, measure, band_color) -> Vector{Any}

The `elements` of the canvas of a widget that keeps the records `drawn`, with the
mark of `selection`, the stored selection of the widget, in its text: a band in
`band_color` behind each line of a part that `selection` names as a whole, and
behind the characters of each line that a range of a part holds, and a thin
rectangle on top, in the colour of the line, while `selection` is a caret in a
part that a line shows. With no such mark, the answer is `elements` itself, so
a widget that holds no selection in its text has no element for it.
"""
function make_drawn_selection_elements(elements, drawn, selection, measure, band_color)
    bands = _make_drawn_bands(drawn, selection, measure, band_color)
    caret = _make_drawn_caret_elements(drawn, selection, measure)
    isempty(bands) && isempty(caret) && return elements
    # The bands go before the first element that holds a line, over the box of the widget.
    at = something(findfirst(element -> any(line -> _find_element_path(element, line.text) !== nothing, drawn),
                             elements),
                   length(elements) + 1)
    vcat(elements[1:(at - 1)], bands, elements[at:end], caret)
end

# A band in `color` over the box of each line of the part that `selection` names as
# a whole, and over the characters of each line that a range of a part holds, in
# the frame of the canvas of the lines.
function _make_drawn_bands(drawn, selection, measure, color)
    selection isa ConcreteReference || return Any[]
    whole = strip_reference_types(selection)
    found = _split_part_range(selection)
    bands = Any[]
    for line in drawn
        part = strip_reference_types(line.part)
        text = _get_drawn_string(line)
        font = unwrap_cell(getfield(line.text, :font))
        box = compute_line_box(measure, text, font)
        x = round(Int, unwrap_cell(getfield(line.text, :x)))
        y = round(Int, unwrap_cell(getfield(line.text, :y))) - box.text_y
        if part == whole
            push!(bands, GraphicsRect(x, y, box.width, box.height; color, radius = 0))
        elseif found !== nothing && found[1] == part && found[2].start < found[2].stop
            from = max(found[2].start - line.start, 0)
            to = min(found[2].stop - line.start, length(text))
            from < to || continue
            offsets = compute_caret_offsets(measure, text, font)
            push!(bands, GraphicsRect(x + round(Int, offsets[from + 1]), y,
                                      round(Int, offsets[to + 1] - offsets[from + 1]), box.height;
                                      color, radius = 0))
        end
    end
    bands
end

# The caret of `selection` on its line, as one element, or no element.
function _make_drawn_caret_elements(drawn, selection, measure)
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
