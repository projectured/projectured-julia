# Fragment of `GraphicsModule` — the ring that marks an object selected as a
# whole.

"""
    make_selection_ring(bounds, style = get_theme_defaults(GraphicsTheme)) -> GraphicsRect

The outline that marks an object selected as a whole. `bounds()` answers the
box `(x, y, w, h)` of the selected object in the frame the ring is drawn in, or
`nothing` when no object there is selected; the ring then has no size and draws
nothing. `style` holds the values of a [`GraphicsTheme`](@ref), and the ring
takes its color, its width and the radius of its corners from them. A projection
passes the values of the scaled theme of its appearance.

A container keeps the ring in its element list at all times, and only the
ring's geometry follows the selection. So the list keeps its shape, and a
selection move repaints the ring and nothing else.
"""
function make_selection_ring(bounds::Function, style::NamedTuple = get_theme_defaults(GraphicsTheme))
    width = Int(style.selection_ring_width)
    ring = GraphicsRect(0, 0, 0, 0; color = color_transparent, radius = Int(style.selection_ring_radius),
                        border_width = width, border_color = style.selection_ring)
    box = Cell(@computation something(bounds(), (0, 0, 0, 0)))
    set_cell_computation!(getfield(ring, :border_width), () -> Int32(box[][3] > 0 ? width : 0))
    set_cell_computation!(getfield(ring, :x), () -> Int32(box[][1]))
    set_cell_computation!(getfield(ring, :y), () -> Int32(box[][2]))
    set_cell_computation!(getfield(ring, :w), () -> Int32(box[][3]))
    set_cell_computation!(getfield(ring, :h), () -> Int32(box[][4]))
    ring
end
