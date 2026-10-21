# Fragment of `TooltipModule` — the theme of the tooltip window: where it stands,
# how large it can be, and how its frame looks.

"""
    TooltipTheme

The place, the size and the frame of the tooltip window: its offset from the
point where the pointer rested, its gap below a part, its least and largest
size, the surface, the line, the padding and the texts of the frame around what
it says, and the texts, the key caps and the gaps of a note.

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
    "The gap between two layers that the window shows, and between the title and the text of a note."
    gap::Spacing = Spacing(6)
    "The gap between the parts of a note: its title and text, its facts, and its hint."
    section_gap::Spacing = Spacing(10)
    "The title of a layer of a part around, and the line that names the keys of the layers."
    layer_text::ThemeText = TextRole(:text_faint; relative_size = 0.9)
    "The title of a note: the name of the part."
    title_text::ThemeText = TextRole(:text; weight = 700)
    "The text of a note: what the part does, or what it shows."
    body_text::ThemeText = TextRole(:text)
    "The name of a fact, the hint of a note, and the word between two keys."
    muted_text::ThemeText = TextRole(:text_muted)
    "The value of a fact."
    value_text::ThemeText = TextRole(:text; family = "Ubuntu Mono")
    "The name of a key on a key cap."
    key_text::ThemeText = TextRole(:text; family = "Ubuntu Mono", relative_size = 0.9)
    "The surface of a key cap."
    key_fill::ThemeColor = ColorRole(:surface_sunken)
    "The line around a key cap."
    key_line::ThemeColor = ColorRole(:border)
    "The space between the line of a key cap and the name of its key."
    key_padding::Spacing = Spacing(Inset(1, 1, 5, 5))
    "The gap between two key caps."
    key_gap::Spacing = Spacing(3)
    "The gap between the title of a note and its key caps."
    head_gap::Spacing = Spacing(16)
    "The gap between the name and the value of a fact."
    fact_gap::Spacing = Spacing(14)
    "The gap between two facts."
    fact_row_gap::Spacing = Spacing(2)
    "The mark before the title of a note with the tone of a warning: a glyph of the icon font."
    warning_mark::ThemeText = TextRole(:warning_text; family = "Lucide")
    "The mark before the title of a note with the tone of an error: a glyph of the icon font."
    error_mark::ThemeText = TextRole(:error_text; family = "Lucide")
    "The mark of a condition with the role of a success: a glyph of the icon font."
    success_mark::ThemeText = TextRole(:success_text; family = "Lucide")
    "The mark of a condition with the role of an information: a glyph of the icon font."
    info_mark::ThemeText = TextRole(:info_text; family = "Lucide")
    "The mark of a condition with the role of the accent, such as work that goes on: a glyph of the icon font."
    accent_mark::ThemeText = TextRole(:accent_text; family = "Lucide")
    "The mark of a condition with no role: a glyph of the icon font."
    quiet_mark::ThemeText = TextRole(:text_muted; family = "Lucide")
end
