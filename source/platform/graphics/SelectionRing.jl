# Fragment of `GraphicsModule` — the ring that marks an object selected as a
# whole.

"""
    make_selection_ring(bounds; color, width) -> GraphicsRect

The outline that marks an object selected as a whole. `bounds()` answers the
box `(x, y, w, h)` of the selected object in the frame the ring is drawn in, or
`nothing` when no object there is selected; the ring then has no size and draws
nothing. A projection passes the color and the width of the ring of its
[`GraphicsTheme`](@ref); the default is the ring of the default theme.

A container keeps the ring in its element list at all times, and only the
ring's geometry follows the selection. So the list keeps its shape, and a
selection move repaints the ring and nothing else.
"""
function make_selection_ring(bounds::Function;
                             color::StyleColor = get_theme_defaults(GraphicsTheme).selection_ring,
                             width::Integer = get_theme_defaults(GraphicsTheme).selection_ring_width)
    ring = GraphicsRect(0, 0, 0, 0; color = color_transparent, radius = 3,
                        border_width = width, border_color = color)
    box = Cell(@computation something(bounds(), (0, 0, 0, 0)))
    set_cell_computation!(getfield(ring, :border_width), () -> Int32(box[][3] > 0 ? width : 0))
    set_cell_computation!(getfield(ring, :x), () -> Int32(box[][1]))
    set_cell_computation!(getfield(ring, :y), () -> Int32(box[][2]))
    set_cell_computation!(getfield(ring, :w), () -> Int32(box[][3]))
    set_cell_computation!(getfield(ring, :h), () -> Int32(box[][4]))
    ring
end

"""
    make_selection_ring_stroke(theme) -> StyleStroke or UntrackedCell{StyleStroke}

The stroke of the ring around an object selected as a whole: the color and the
width of the ring of the scaled graphics theme `theme`. With a scaled theme, it is
a cell that reads the theme at each read, with no edge
([`make_theme_cell`](@ref)). With `nothing`, it is the plain stroke of the
default theme. A layout and a widget container hold it as their style field.
"""
function make_selection_ring_stroke(::Nothing)
    defaults = get_theme_defaults(GraphicsTheme)
    StyleStroke(defaults.selection_ring, defaults.selection_ring_width)
end
make_selection_ring_stroke(theme::ScaledGraphicsTheme) =
    make_theme_cell(StyleStroke, theme, scaled -> StyleStroke(scaled.selection_ring, scaled.selection_ring_width))
