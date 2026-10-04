# Fragment of `TooltipModule` — the theme of the tooltip window: where it stands
# and how large it can be.

"""
    TooltipTheme

The place and the size of the tooltip window: its offset from the point where
the pointer rested, its gap below a part, and its least and largest size.

The theme of `TooltipWindowProjection`. `@theme` declares it, so
`ScaledTooltipTheme` holds each value times its scale, and `TooltipTheme()` is
the default theme. The projection holds the values that it reads, as cells that
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
end
