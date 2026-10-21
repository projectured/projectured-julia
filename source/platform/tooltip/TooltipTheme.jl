# Fragment of `TooltipModule` — the theme of the tooltip window: where it stands,
# how large it can be, and how its frame looks.

"""
    TooltipTheme

The place, the size and the frame of the tooltip window: its offset from the
point where the pointer rested, its gap below a part, its least and largest
size, and the surface, the line, the padding and the texts of the frame around
what it says.

The theme of `TooltipWindowProjection`, for the place and the size, and of the
natural drawing of a `TooltipContent`, for the frame. `@theme` declares it, so
`ScaledTooltipTheme` holds each value times its scale, and `TooltipTheme()` is
the default theme. A projection holds the values that it reads, as cells that
read the theme, scaled or not; it reads them each time it opens a window, so a
change of the appearance shows at the next tooltip.
"""
@theme struct TooltipTheme
    "The offset of the window from the point where the pointer rested."
    offset::Spacing = Spacing(Point2D(16, 20))
    "The gap between a part and the window that stands below it."
    part_gap::Spacing = Spacing(4)
    "The least width and height of the window."
    minimum_size::ControlSize = ControlSize(Point2D(120, 32))
    "The largest width and height of the window."
    maximum_size::ControlSize = ControlSize(Point2D(560, 400))
    "The font that the texts of a tooltip follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 13)
    "The surface of the window."
    surface::ThemeColor = ColorRole(:surface)
    "The line around the window."
    line::ThemeColor = ColorRole(:border_strong)
    "The width of the line around the window."
    line_width::LineWidth = LineWidth(1)
    "The space between the line and what the window says."
    padding::Spacing = Spacing(Inset(8, 8, 12, 12))
    "The gap between two parts of what the window says."
    gap::Spacing = Spacing(6)
    "The title of a layer of a part around, and the line that names the keys of the layers."
    layer_text::ThemeText = TextRole(:text_faint; relative_size = 0.9)
end
