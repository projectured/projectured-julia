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
projection prints, with every window, its place and its size, or `nothing` for a
window that is printed on no screen. `window` is the window that is placed.
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
        box === nothing && return nothing
        width = max(Int(minimum_width), round(Int, box.width * width_share))
        WindowPlace(box.x + (box.width - width) ÷ 2, box.y + gap;
                    minimum_size = (width, 0), maximum_size = (width, Int(maximum_height)))
    end
end

# The place that the placement of `window` answers, or `nothing` when the window
# has no placement or the placement answers none. `screen_iomap` is the cell of the
# IO map of the screen that prints the window, which holds `nothing` while the
# screen prints.
function _compute_window_place(window::WindowDocument, screen_iomap)
    placement = getfield(window, :placement)[]
    placement === nothing && return nothing
    iomap = screen_iomap === nothing ? nothing : screen_iomap[]
    screen = iomap === nothing ? nothing : get_iomap_output(iomap)
    place = placement(WindowPlacementContext(screen, window, iomap))
    place isa WindowPlace || place === nothing ||
        throw(ArgumentError("a placement answers a WindowPlace or nothing, not $(typeof(place))"))
    place
end
