# Fragment of `GraphicsModule` — the ring that marks an object selected as a
# whole.

"""
    SELECTION_RING_COLOR

The color of the ring around an object that is selected as a whole.
"""
const SELECTION_RING_COLOR = StyleColor(0x25 / 255, 0x63 / 255, 0xeb / 255, 1.0)

"""
    make_selection_ring(bounds; color = SELECTION_RING_COLOR, width = 2) -> GraphicsRect

The outline that marks an object selected as a whole. `bounds()` answers the
box `(x, y, w, h)` of the selected object in the frame the ring is drawn in, or
`nothing` when no object there is selected; the ring then has no size and draws
nothing. A projection with a theme passes the color and the width of its ring.

A container keeps the ring in its element list at all times, and only the
ring's geometry follows the selection. So the list keeps its shape, and a
selection move repaints the ring and nothing else.
"""
function make_selection_ring(bounds::Function; color::StyleColor = SELECTION_RING_COLOR,
                             width::Integer = 2)
    ring = GraphicsRect(0, 0, 0, 0; color = color_transparent, radius = 3,
                        border_width = width, border_color = color)
    box = Cell(@computation something(bounds(), (0, 0, 0, 0)))
    set_cell_function!(getfield(ring, :border_width), () -> Int32(box[][3] > 0 ? width : 0))
    set_cell_function!(getfield(ring, :x), () -> Int32(box[][1]))
    set_cell_function!(getfield(ring, :y), () -> Int32(box[][2]))
    set_cell_function!(getfield(ring, :w), () -> Int32(box[][3]))
    set_cell_function!(getfield(ring, :h), () -> Int32(box[][4]))
    ring
end
