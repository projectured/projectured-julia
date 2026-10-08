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
no width and no height at its place, and a canvas with no size of its own on an
axis has the bounds of what it draws there. It reads the printed output, so a
node that a lazy printer did not print has no box.

With `visible = true` the box is the part of it that the viewports on the way
show: each viewport cuts it to its own box, and a box that they do not show at
all is `nothing`, as for a part scrolled out of view.

Use it to put a window at a part that a command names, such as a tooltip that
opens with no pointer.
"""
function find_reference_box(document, reference::Reference; measure::TextMeasure = FontFileMeasure(),
                            visible::Bool = false)
    box, clip = _find_box_and_clip(document, reference, measure)
    (box === nothing || !visible || clip === nothing) && return box
    clip === false ? nothing : _cut_box(box, clip)
end

# The box of the node that `reference` reaches, and the box that the viewports on
# the way leave visible: `nothing` when no viewport is on the way, and `false` when
# the viewports show none of it.
function _find_box_and_clip(document, reference::Reference, measure::TextMeasure)
    node = _box_value(document)
    frame = (0.0, 0.0, 1.0, 1.0)       # origin x, origin y, scale x, scale y
    clip = nothing
    while reference isa ConcreteReference
        node isa GraphicsText && return (_make_text_box(frame, node, reference, measure), clip)
        step = get_reference_head(reference)
        step isa RegionReferenceStep && return (_make_region_box(frame, node, step), clip)
        child = try
            _box_value(evaluate_reference_step(step, node))
        catch
            return (nothing, clip)
        end
        if node isa GraphicsViewport && step isa FieldReferenceStep && step.name == "content"
            view = _make_node_box(frame, node, measure)
            clip === false ||
                (clip = clip === nothing ? view : something(_cut_box(view, clip), false))
        end
        frame = _enter_box_frame(frame, node, step)
        node = child
        reference = get_reference_tail(reference)
    end
    node isa GraphicsText && return (_make_text_box(frame, node, EmptyReference(), measure), clip)
    (_make_node_box(frame, node, measure), clip)
end

# The part of `box` inside `clip`, or `nothing` when it lies outside; a box of no
# width or no height, such as a caret, is kept when it lies inside.
function _cut_box(box, clip)
    left, top = max(box.x, clip.x), max(box.y, clip.y)
    right = min(box.x + box.width, clip.x + clip.width)
    bottom = min(box.y + box.height, clip.y + clip.height)
    (right < left || bottom < top) && return nothing
    (x = left, y = top, width = right - left, height = bottom - top)
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
    hasfield(typeof(node), name) ? Float64(_box_value(getproperty(node, name))) : 0.0

_has_box_place(node) = hasfield(typeof(node), :x) && hasfield(typeof(node), :y)

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

function _make_node_box(frame, node, measure::TextMeasure)
    _is_self_sized_canvas(node) && return _make_content_box(frame, node, measure)
    ox, oy, sx, sy = frame
    x = round(Int, ox + sx * _box_number(node, :x))
    y = round(Int, oy + sy * _box_number(node, :y))
    (x = x, y = y,
     width = round(Int, sx * _box_number(node, :w)),
     height = round(Int, sy * _box_number(node, :h)))
end

# A canvas with no size of its own on an axis, whose elements are a vector: the
# renderer draws what its elements reach there. A canvas over a lazy list keeps
# the size it declares, because such a list can have no end.
_is_self_sized_canvas(node) =
    node isa GraphicsCanvas && (_box_number(node, :w) <= 0 || _box_number(node, :h) <= 0) &&
    _box_value(getfield(node, :elements)) isa Union{AbstractVector, CellVector}

# The box of a canvas that sizes itself from its elements: on an axis where it has
# no size of its own, the bounds of what it draws, in the frame of its children.
function _make_content_box(frame, node::GraphicsCanvas, measure::TextMeasure)
    ox, oy, sx, sy = _enter_box_frame(frame, node, nothing)
    min_x, min_y, max_x, max_y = get_canvas_content_bounds(node, measure)
    width, height = _box_number(node, :w), _box_number(node, :h)
    left, right = width > 0 ? (0.0, width) : (Float64(min_x), Float64(max_x))
    top, bottom = height > 0 ? (0.0, height) : (Float64(min_y), Float64(max_y))
    (x = round(Int, ox + sx * left), y = round(Int, oy + sy * top),
     width = round(Int, sx * (right - left)), height = round(Int, sy * (bottom - top)))
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
