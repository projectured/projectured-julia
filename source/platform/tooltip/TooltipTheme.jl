# Fragment of `TooltipModule` — the theme of the tooltip window: where it stands,
# how large it can be, and how its frame looks.

"""
    TooltipTheme

The place, the size and the frame of the tooltip window: its offset from the
point where the pointer rested, its gap below a part, its least and largest
size, the surface, the line and the texts of the frame around what it says, and
the texts and the key caps of a note. The padding and the gaps of the frame and of
a note are roles of the widget theme.

The theme of `TooltipWindowProjection`, for the place and the size, and of the
natural drawing of a `TooltipContent` and a `TooltipNote`, for the frame and the
note. `@theme` declares it, so `ScaledTooltipTheme` holds each value times its
scale, and `TooltipTheme()` is the default theme. A projection holds the values that it reads, as cells that
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
    "The surface of the window."
    surface::ThemeColor = ColorRole(:surface)
    "The line around the window."
    line::ThemeColor = ColorRole(:border_strong)
    "The width of the line around the window."
    line_width::LineWidth = LineWidth(1)
    "The title of a layer of a part around, and the line that names the keys of the layers."
    layer_text::ThemeText = TextRole(:text_faint; font_role = :quiet)
    "The title of a note: the name of the part."
    title_text::ThemeText = TextRole(:text; font_role = :strong_text)
    "The text of a note: what the part does, or what it shows."
    body_text::ThemeText = TextRole(:text; font_role = :text)
    "The name of a fact, the hint of a note, and the word between two keys."
    muted_text::ThemeText = TextRole(:text_muted; font_role = :text)
    "The value of a fact."
    value_text::ThemeText = TextRole(:text; font_role = :code)
    "The name of a key on a key cap."
    key_text::ThemeText = TextRole(:text; font_role = :badge)
    "The surface of a key cap."
    key_fill::ThemeColor = ColorRole(:surface_sunken)
    "The line around a key cap."
    key_line::ThemeColor = ColorRole(:border)
    "The mark before the title of a note with the tone of a warning: a glyph of the icon font."
    warning_mark::ThemeText = TextRole(:warning_text; font = StyleFont("Lucide", 13))
    "The mark before the title of a note with the tone of an error: a glyph of the icon font."
    error_mark::ThemeText = TextRole(:error_text; font = StyleFont("Lucide", 13))
    "The mark of a condition with the role of a success: a glyph of the icon font."
    success_mark::ThemeText = TextRole(:success_text; font = StyleFont("Lucide", 13))
    "The mark of a condition with the role of an information: a glyph of the icon font."
    info_mark::ThemeText = TextRole(:info_text; font = StyleFont("Lucide", 13))
    "The mark of a condition with the role of the accent, such as work that goes on: a glyph of the icon font."
    accent_mark::ThemeText = TextRole(:accent_text; font = StyleFont("Lucide", 13))
    "The mark of a condition with no role: a glyph of the icon font."
    quiet_mark::ThemeText = TextRole(:text_muted; font = StyleFont("Lucide", 13))
end
