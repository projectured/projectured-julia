# Fragment of `ScreenModule` — the place of a window that a function computes.
#
# A window with a `placement` takes its place from that function, and not from its
# `x` and `y`. The screen projection calls the function in a computation over the
# screen that it prints, so the place follows each change of what the function
# reads: the place and the size of another window, or the box of a part in it. A
# new kind of place is a new function, and the window code does not change.

"""
    WindowPlace(x, y; minimum_size = nothing, maximum_size = nothing)

Where a placement puts a window: `x` and `y`, the top left corner on the screen
in logical pixels, and the bounds of a window that fits its content, as the
fields of `WindowDocument` say. A bound that is `nothing` keeps the bound of the
window. A window whose width must not change while its content changes has the
same minimum and maximum width.
"""
struct WindowPlace
    x::Int
    y::Int
    minimum_size::Union{Nothing,NTuple{2,Int}}
    maximum_size::Union{Nothing,NTuple{2,Int}}
end

WindowPlace(x::Integer, y::Integer; minimum_size = nothing, maximum_size = nothing) =
    WindowPlace(Int(x), Int(y),
                minimum_size === nothing ? nothing : (Int(minimum_size[1]), Int(minimum_size[2])),
                maximum_size === nothing ? nothing : (Int(maximum_size[1]), Int(maximum_size[2])))

"""
    WindowPlacementContext

What a placement reads to place a window. `screen` is the screen that the
projection prints, its input, with every window, its place and its size, or
`nothing` for a window that is printed on no screen. `window` is the window that is placed.
[`find_window_part_box`](@ref) gives the box of a part of any window.

The context gives no printed size of the content of `window`: the content prints
at the bounds of the place, so bounds made from the content would read
themselves.
"""
struct WindowPlacementContext
    screen::Any
    window::Any
    iomap::Any
end

"""
    find_window_part_box(context, reference) -> NamedTuple | Nothing

The box of the part at `reference`, a reference from the screen that the
projection prints, such as `windows[1].content` and the steps into the content of
that window: `(x = …, y = …, width = …, height = …)` in screen coordinates, or
`nothing` when the part has no image. A placement that reads it follows the part
when the part moves.
"""
function find_window_part_box(context::WindowPlacementContext, reference)
    iomap = context.iomap
    iomap === nothing && return nothing
    _find_part_box(iomap.projection, iomap, reference)
end

"""
    make_part_top_placement(reference; width_share = 0.5, minimum_width = 480,
                            maximum_height = 480, gap = 8) -> Function

The placement at the top center of the part at `reference`, a reference from the
screen: `gap` below the top edge of the box of the part, `width_share` of the
width of the part wide and at least `minimum_width`, and as high as the content of
the window up to `maximum_height`. The width does not change while the content
changes. While the part has no box, the window stands at its own `x` and `y`.

Use it for a list that a person types into and that belongs to the whole of a
part, such as the command palette over the content of a window.
"""
function make_part_top_placement(reference; width_share::Real = 0.5, minimum_width::Integer = 480,
                                 maximum_height::Integer = 480, gap::Integer = 8)
    context -> begin
        box = find_window_part_box(context, reference)
        box === nothing ? nothing : make_top_center_place(box; width_share, minimum_width, maximum_height, gap)
    end
end

"""
    make_top_center_place(box; width_share = 0.5, minimum_width = 480, maximum_height = 480,
                          gap = 8) -> WindowPlace

The place at the top center of `box`, a box in screen coordinates: `gap` below its
top edge, `width_share` of its width wide and at least `minimum_width`, and as high
as the content of the window up to `maximum_height`, with the same minimum and
maximum width. A placement that finds its box in its own way answers it.
"""
function make_top_center_place(box; width_share::Real = 0.5, minimum_width::Integer = 480,
                               maximum_height::Integer = 480, gap::Integer = 8)
    width = max(Int(minimum_width), round(Int, box.width * width_share))
    WindowPlace(box.x + (box.width - width) ÷ 2, box.y + gap;
                minimum_size = (width, 0), maximum_size = (width, Int(maximum_height)))
end

"""
    compute_anchored_place(context, anchor; side = :below, gap = 0,
                           minimum_size = nothing, maximum_size = nothing) -> WindowPlace

The place of the window of `context` on `side` of `anchor`, a box in screen
coordinates `(x = …, y = …, width = …, height = …)`; a point is a box of no size.
`side` is `:below`, `gap` under the box with the left edges aligned, or
`:center`, in the middle of the box. The bounds go into the place as they are.

The place stays on the area of the display that holds the middle of the anchor,
or on the first area, from `display_areas` of the screen. A window below the
anchor that crosses the bottom edge of the area goes `gap` above the anchor, and
slides up inside the area when the top has no room either. On every other edge the
window slides inside the area. A screen with no areas keeps the place on its side.

The size of the window is the size that the backend fitted to its content, so the
place follows it.
"""
function compute_anchored_place(context::WindowPlacementContext, anchor; side::Symbol = :below,
                                gap::Integer = 0, minimum_size = nothing, maximum_size = nothing)
    width, height = Int(context.window.width), Int(context.window.height)
    x, y = if side === :below
        (Int(anchor.x), Int(anchor.y + anchor.height + gap))
    elseif side === :center
        (Int(anchor.x + (anchor.width - width) ÷ 2), Int(anchor.y + (anchor.height - height) ÷ 2))
    else
        throw(ArgumentError("the side of an anchored place is :below or :center, not :$side"))
    end
    areas = context.screen isa ScreenDocument ? context.screen.display_areas : NTuple{4,Int}[]
    isempty(areas) && return WindowPlace(x, y; minimum_size, maximum_size)
    left, top, area_width, area_height =
        find_display_area(areas, (anchor.x + anchor.width ÷ 2, anchor.y + anchor.height ÷ 2))
    if side === :below && y + height > top + area_height
        above = Int(anchor.y) - Int(gap) - height
        above >= top && (y = above)
    end
    WindowPlace(_slide_inside(x, width, left, area_width), _slide_inside(y, height, top, area_height);
                minimum_size, maximum_size)
end

# The start of a span of `length` that starts at `start`, moved inside the span of
# `area_length` that starts at `area_start`; a span that is longer than the area
# starts with it.
_slide_inside(start, length, area_start, area_length) =
    max(min(start, area_start + area_length - length), area_start)

"""
    find_display_area(areas, point) -> NTuple{4,Int}

The area of `areas` that holds `point`, or the first area when none holds it.
Each area is `(x, y, width, height)`, as `display_areas` of a
[`ScreenDocument`](@ref) holds it, and `areas` is not empty.
"""
function find_display_area(areas, point)
    for area in areas
        (area[1] <= point[1] < area[1] + area[3] && area[2] <= point[2] < area[2] + area[4]) &&
            return area
    end
    first(areas)
end

"""
    find_window_box(context, id) -> NamedTuple | Nothing

The box of the window `id` where the screen prints it, `(x = …, y = …, width = …,
height = …)` in screen coordinates, or `nothing` when the screen holds no such
window. A placed window stands at the place that its placement computes, so a
popup of a placed window follows that place.
"""
function find_window_box(context::WindowPlacementContext, id::Symbol)
    context.iomap === nothing && return nothing
    screen = unwrap_cell(get_iomap_output(context.iomap))
    screen isa ScreenDocument || return nothing
    for window in screen.windows
        window isa WindowDocument && window.id === id || continue
        return (x = Int(window.x), y = Int(window.y), width = Int(window.width), height = Int(window.height))
    end
    nothing
end

"""
    make_window_center_placement(id) -> Function

The placement at the center of the window `id` where the screen prints it, inside
the area of its display, which answers no place while the screen holds no such
window. A dialog that names no place of its own takes it, from the window that
opens it.
"""
make_window_center_placement(id::Symbol) =
    context -> (box = find_window_box(context, id);
                box === nothing ? nothing : compute_anchored_place(context, box; side = :center))

# Whether `op` opens a dialog that names no place of its own: a window of the style
# of a dialog at the automatic place. A normal window at the automatic place is the
# backend's to place, as the main window is.
_is_unplaced_dialog(op::OpenWindowOperation) =
    op.placement === nothing && (op.x, op.y) == AUTOMATIC_WINDOW_PLACE && op.style in (:floating, :dialog)

# `op` with the placement at the center of the window `id`.
_place_at_window_center(op::OpenWindowOperation, id::Symbol) =
    OpenWindowOperation(op.id, op.title, op.x, op.y, op.width, op.height, op.minimum_size, op.maximum_size,
                        op.bg, op.style, op.auto_dismiss, op.modal, make_window_center_placement(id), op.content)

"""
    find_screen_reference(document, reference) -> Reference | Nothing

The reference of the part at `reference`, a reference from `document`, from the
first [`ScreenDocument`](@ref) on its way, which [`find_window_part_box`](@ref)
reads; `nothing` when the way passes no screen. A wrapper around the screen gives
its placement the part that an operation names from the state of the wrapper.
"""
function find_screen_reference(document, reference)
    reference isa Reference || return nothing
    steps = get_reference_steps(strip_reference_types(reference))
    for index in 1:(length(steps) + 1)
        document isa ScreenDocument && return extend_reference(EmptyReference(), steps[index:end]...)
        index > length(steps) && break
        document = try_evaluate_reference(document, extend_reference(EmptyReference(), steps[index]), nothing)
        document === nothing && break
    end
    nothing
end

"""
    make_fixed_placement(x, y; minimum_size = nothing, maximum_size = nothing) -> Function

The placement that puts its window at `x` and `y` with these bounds, whatever the
screen holds. A window with a frame takes it when a person moves or resizes the
window, so the window stays where the person put it and its first placement ends.
"""
function make_fixed_placement(x::Integer, y::Integer; minimum_size = nothing, maximum_size = nothing)
    place = WindowPlace(x, y; minimum_size, maximum_size)
    context -> place
end

# The place that the placement of `window` answers, or `nothing` when the window
# has no placement or the placement answers none. `screen_iomap` is the cell of the
# IO map of the screen that prints the window, which holds `nothing` while the
# screen prints.
function _compute_window_place(window::WindowDocument, screen_iomap)
    placement = getfield(window, :placement)[]
    placement === nothing && return nothing
    iomap = screen_iomap === nothing ? nothing : screen_iomap[]
    screen = iomap === nothing ? nothing : get_iomap_input(iomap)
    place = placement(WindowPlacementContext(screen, window, iomap))
    place isa WindowPlace || place === nothing ||
        throw(ArgumentError("a placement answers a WindowPlace or nothing, not $(typeof(place))"))
    place
end
