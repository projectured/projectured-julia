# Fragment of `GraphicsModule` — the shape of the pointer at a point of what a
# window draws.

"""
    find_pointer_shape(canvas, x, y) -> Symbol

The shape that the pointer takes at `(x, y)` over `canvas`, the root canvas of a
window: the `shape` of the last [`GraphicsPointerShape`](@ref) that holds the
point, in the order of the drawing, or `:default` where no region holds it. A
region of a drag that holds the point wins over every region that is not one.

The walk follows the drawing of a backend. The root canvas is at the origin of
the window, a nested canvas moves its elements by its place and clips nothing,
and a viewport clips the regions inside it to its box and moves them by its
content and its transform. A canvas that lays out its elements without overlap
walks only the elements at the point, from the first one that reaches it, as
`hit_element_at` does, so a list of rows that the viewport does not show is not
walked. A canvas that declares its extent and does not hold the point is not
walked either.

# Example

    canvas = GraphicsCanvas([GraphicsPointerShape(0, 0, 100, 20, :ibeam)]; w = 200, h = 100)
    find_pointer_shape(canvas, 10, 10)    # :ibeam
    find_pointer_shape(canvas, 10, 50)    # :default
"""
function find_pointer_shape(canvas::GraphicsCanvas, x::Real, y::Real)
    found = _FoundPointerShape(:default, nothing)
    _find_elements_shape!(found, canvas, Float64(x), Float64(y))
    something(found.drag, found.plain)
end

# The shape of the last plain region and of the last region of a drag that hold
# the point, so far.
mutable struct _FoundPointerShape
    plain::Symbol
    drag::Union{Symbol,Nothing}
end

# The elements of `canvas`, in the order of the drawing, with the point in the
# frame of its elements.
function _find_elements_shape!(found::_FoundPointerShape, canvas::GraphicsCanvas,
                               x::Float64, y::Float64)
    layout = canvas.layout
    elements = canvas.elements
    laid_out = !canvas.overlapping_elements && layout != layout_none
    point = layout == layout_horizontal ? x : y
    get_start = layout == layout_horizontal ? _elem_x : _elem_y
    if elements isa ListNode
        # The elements of a laid-out list do not overlap, so only the last one that
        # starts at or before the point can hold it. Before the head, nearest
        # first, that is the first such element; from the head on, it is the one
        # before the first element that starts after the point.
        node = elements.prev
        while node !== nothing
            element = node.value
            if !(element isa GraphicsFence)
                start = laid_out ? get_start(element) : nothing
                if start === nothing || start <= point
                    _find_element_shape!(found, element, x, y)
                    start === nothing || break
                end
            end
            node = node.prev
        end
        candidate = nothing
        node = elements
        while node !== nothing
            element = node.value
            if !(element isa GraphicsFence)
                start = laid_out ? get_start(element) : nothing
                if start === nothing
                    candidate === nothing || _find_element_shape!(found, candidate, x, y)
                    candidate = nothing
                    _find_element_shape!(found, element, x, y)
                elseif start > point
                    break
                else
                    candidate = element
                end
            end
            node = node.next
        end
        candidate === nothing || _find_element_shape!(found, candidate, x, y)
    else
        for index in compute_first_visible_index(canvas, floor(Int, point)):length(elements)
            element = elements[index]
            element isa GraphicsFence && continue
            if laid_out
                start = get_start(element)
                start !== nothing && start > point && break
            end
            _find_element_shape!(found, element, x, y)
        end
    end
    found
end

# One element, with the point in the frame that holds the element.
function _find_element_shape!(found::_FoundPointerShape, element, x::Float64, y::Float64)
    if element isa GraphicsPointerShape
        left, top = Int(element.x), Int(element.y)
        if left <= x < left + Int(element.w) && top <= y < top + Int(element.h)
            element.drag ? (found.drag = element.shape) : (found.plain = element.shape)
        end
    elseif element isa GraphicsCanvas
        x, y = x - Int(element.x), y - Int(element.y)
        has_declared_extent(element) &&
            !(0 <= x < Int(element.w) && 0 <= y < Int(element.h)) && return found
        _find_elements_shape!(found, element, x, y)
    elseif element isa GraphicsViewport
        left, top = Int(element.x), Int(element.y)
        (left <= x < left + Int(element.w) && top <= y < top + Int(element.h)) || return found
        content = element.content::GraphicsCanvas
        transform = element.transform::AffineTransform
        # A backend draws an element of the content at `(v + t) / s + c + l`, in
        # units scaled by `s`: the inverse of that place, for the point.
        scale_x = transform.a == 0.0 ? 1.0 : transform.a
        scale_y = transform.d == 0.0 ? 1.0 : transform.d
        _find_elements_shape!(found, content,
                              (x - left - transform.e) / scale_x - Int(content.x),
                              (y - top - transform.f) / scale_y - Int(content.y))
    end
    found
end
