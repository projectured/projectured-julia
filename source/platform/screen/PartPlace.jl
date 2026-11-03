# Fragment of `ScreenModule` — the place on the screen below a part, for a window
# that a command opens at the part.

"""
    find_part_place(projection, iomap, source) -> Tuple{Int,Int} | Nothing

The place on the screen below the part at `source`, a reference from the input of
`iomap`: the left edge and the bottom of the box of the node that draws the part,
or `nothing` when the part has no image or its node is not printed. `projection`
and `iomap` show a screen, so the box is in screen coordinates.

A wrapper at the screen that keeps a window, such as the tooltip window, opens a
window there when an answer has no point, as when a command runs a binding with
no pointer, so the window stands below the part and does not cover it. The part
is mapped forward (`map_reference_forward`) with the type of each node on its
reference, because a view checks them, and the box of the node is read from the
printed output (`find_reference_box`).
"""
function find_part_place(projection, iomap, source)
    box = _find_part_box(projection, iomap, source)
    box === nothing ? nothing : (box.x, box.y + box.height)
end

# The box of the node that draws the part at `source`, a reference from the input
# of `iomap`, in the frame of its output, or `nothing`.
function _find_part_box(projection, iomap, source)
    source isa Reference || return nothing
    input = get_iomap_input(iomap)
    try_evaluate_reference(input, source, _NO_PART) === _NO_PART && return nothing
    image = map_reference_forward(projection, iomap, annotate_reference_types(input, source))
    image === nothing && return nothing
    find_reference_box(get_iomap_output(iomap), image)
end

# What a step of a reference that reaches no node evaluates to.
const _NO_PART = gensym(:no_part)
