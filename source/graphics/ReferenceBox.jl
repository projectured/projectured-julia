# Fragment of `GraphicsModule` — the place and the size of the node that a
# reference reaches in a printed graphics document.

"""
    find_reference_box(document, reference; measure = FontFileMeasure()) -> NamedTuple | Nothing

The box of the node that `reference` reaches from `document`, a printed
graphics document: `(x = …, y = …, width = …, height = …)` in the frame that the
place of `document` is given in, or `nothing` when the reference reaches no node.
A text (`GraphicsText`) has the box of what it draws, measured with `measure`, as
every backend draws with the font files; a reference that goes on into its text,
`text{a:b}`, has the box of those characters, and `text{a:a}` the box of a caret.
A `RegionReferenceStep` after a node is that box in the frame of the node.

A forward map answers the reference of the node that draws a part
(`map_reference_forward`); this reads where that node is. Each node on the way
that has a place moves the frame of its children by that place, and a viewport
moves its content by its `transform` as well, its translation and its scale. The
node at the end gives its size; a node with no size, such as a text, has a box of
no width and no height at its place. It reads the printed output, so a node that
a lazy printer did not print has no box.

Use it to put a window at a part that a command names, such as a tooltip that
opens with no pointer.
"""
function find_reference_box(document, reference::Reference; measure::TextMeasure = FontFileMeasure())
    node = _box_value(document)
    frame = (0.0, 0.0, 1.0, 1.0)       # origin x, origin y, scale x, scale y
    while reference isa ConcreteReference
        node isa GraphicsText && return _make_text_box(frame, node, reference, measure)
        step = get_reference_head(reference)
        step isa RegionReferenceStep && return _make_region_box(frame, node, step)
        child = try
            _box_value(evaluate_reference_step(step, node))
        catch
            return nothing
        end
        frame = _enter_box_frame(frame, node, step)
        node = child
        reference = get_reference_tail(reference)
    end
    node isa GraphicsText && return _make_text_box(frame, node, EmptyReference(), measure)
    _make_node_box(frame, node)
end

# The box of `region` in the frame of the children of `node`.
function _make_region_box(frame, node, region::RegionReferenceStep)
    ox, oy, sx, sy = _enter_box_frame(frame, node, nothing)
    (x = round(Int, ox + sx * region.x), y = round(Int, oy + sy * region.y),
     width = round(Int, sx * region.width), height = round(Int, sy * region.height))
end

# The box of a text, or of the characters `a:b` of it when `reference` is
# `text{a:b}`; `nothing` for any other reference into a text.
function _make_text_box(frame, node::GraphicsText, reference, measure::TextMeasure)
    text = String(_box_value(getfield(node, :text)))
    font = _box_value(getfield(node, :font))
    width, ascent, descent = compute_text_extent(measure, text, font)
    left, right = 0, width
    if reference isa ConcreteReference
        head = get_reference_head(reference)
        (head isa FieldReferenceStep && head.name == "text") || return nothing
        range = get_reference_tail(reference)
        (range isa ConcreteReference && get_reference_tail(range) isa EmptyReference) || return nothing
        step = get_reference_head(range)
        step isa RangeReferenceStep || return nothing
        offsets = compute_caret_offsets(measure, text, font)
        (0 <= step.start <= step.stop < length(offsets)) || return nothing
        left, right = round(Int, offsets[step.start + 1]), round(Int, offsets[step.stop + 1])
    end
    ox, oy, sx, sy = frame
    (x = round(Int, ox + sx * (_box_number(node, :x) + left)),
     y = round(Int, oy + sy * _box_number(node, :y)),
     width = round(Int, sx * (right - left)),
     height = round(Int, sy * (ascent + descent)))
end

_box_value(value) = value isa AbstractCell ? _box_value(value[]) : value

_box_number(node, name::Symbol) =
    hasproperty(node, name) ? Float64(_box_value(getproperty(node, name))) : 0.0

_has_box_place(node) = hasproperty(node, :x) && hasproperty(node, :y)

# The frame of the children of `node`, from the frame that the place of `node` is
# given in. A viewport moves its content by its transform too.
function _enter_box_frame(frame, node, step)
    _has_box_place(node) || return frame
    ox, oy, sx, sy = frame
    ox, oy = ox + sx * _box_number(node, :x), oy + sy * _box_number(node, :y)
    if node isa GraphicsViewport && step isa FieldReferenceStep && step.name == "content"
        transform = _box_value(getfield(node, :transform))
        ox, oy = ox + sx * transform.e, oy + sy * transform.f
        sx, sy = sx * transform.a, sy * transform.d
    end
    (ox, oy, sx, sy)
end

function _make_node_box(frame, node)
    ox, oy, sx, sy = frame
    x = round(Int, ox + sx * _box_number(node, :x))
    y = round(Int, oy + sy * _box_number(node, :y))
    (x = x, y = y,
     width = round(Int, sx * _box_number(node, :w)),
     height = round(Int, sy * _box_number(node, :h)))
end

"""
    find_node_reference(document, node; depth = 3) -> Reference | Nothing

The reference from `document`, a printed graphics node, to `node` inside it,
found by identity through the elements of a canvas and the content of a
viewport, at most `depth` nodes deep; `nothing` when `node` is not there.

A container that puts parts of its own before its children, whose number varies,
such as the parts of a box, uses it in its forward map: the canvas of a child sits
in a wrapper canvas, or in the content of a viewport that clips it, a few nodes
below the container's own canvas.
"""
function find_node_reference(document, node; depth::Int = 3)
    level = Any[(_box_value(document), EmptyReference())]
    for _ in 0:depth
        next = Any[]
        for (candidate, steps) in level
            candidate === node && return _reverse_steps(steps)
            for (child, step, index) in _find_node_children(candidate)
                reached = ConcreteReference(step, steps)
                index === nothing || (reached = ConcreteReference(index, reached))
                push!(next, (_box_value(child), reached))
            end
        end
        isempty(next) && return nothing
        level = next
    end
    nothing
end

# The children of a printed node that the search looks into, each with the step to
# it and the index step after that. The elements of a canvas are read only when
# they are a vector: a list that a lazy printer walks can be endless.
function _find_node_children(node)
    if node isa GraphicsCanvas
        elements = _box_value(getfield(node, :elements))
        elements isa Union{AbstractVector,CellVector} || return ()
        return ((elements[k], FieldReferenceStep("elements"), RangeReferenceStep(k - 1, k))
                for k in 1:length(elements))
    elseif node isa GraphicsViewport
        return ((getfield(node, :content), FieldReferenceStep("content"), nothing),)
    end
    ()
end

# The steps of a search, kept last step first, as a reference from the start.
function _reverse_steps(steps)
    reference = EmptyReference()
    while steps isa ConcreteReference
        reference = ConcreteReference(get_reference_head(steps), reference)
        steps = get_reference_tail(steps)
    end
    reference
end
