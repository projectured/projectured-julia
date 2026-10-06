# Fragment of `GraphicsModule` — the theme of the graphics: the ring around an
# object selected as a whole, and the mark of a fault.

"""
    GraphicsTheme

The ring around an object that is selected as a whole, the band under a
selected row, the mark that a fault barrier of the graphics domain draws, and the
gap between the blocks of a collection.

The graphics and the layouts lie below every other slice that draws, so they
take these styles from this theme and from no other. `@theme` declares it, so
`ScaledGraphicsTheme` holds each value times its scale, and `GraphicsTheme()` is
the default theme. The widgets draw their ring and the band of a selected row
with the same theme, from the same appearance.
"""
@theme struct GraphicsTheme
    "The base font of the fault mark."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 13)
    "The mark of a fault that a projection of the graphics domain raised."
    fault_text::TextRole = TextRole(:error_text; weight = 700)
    "The ring around an object that is selected as a whole."
    selection_ring::ThemeColor = ColorRole(:selection_ring)
    "The band under a selected row of a list, a tree or a table."
    selection_band::ThemeColor = ColorRole(:selection_band)
    "The width of the ring around an object that is selected as a whole."
    selection_ring_width::LineWidth = LineWidth(2)
    "The radius of the corners of the ring around an object that is selected as a whole."
    selection_ring_radius::Radius = Radius(3)
    "The gap between the elements of a collection drawn as a stack of blocks."
    collection_gap::Spacing = Spacing(8)
end
