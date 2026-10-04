# Fragment of `FaultViewModule` — the theme of the fault log: the text of its
# count, its site, its origin, its message, and its empty line.

"""
    FaultTheme

The fonts and the colors of the Faults panel: a count, a site, a cause, a
message and the line it shows when empty.

The theme of the fault log. `@theme` declares it, so `ScaledFaultTheme` holds
each value times its scale, and `FaultTheme()` is the default theme.

The fields are the text styles of a fault's count, site, origin, message and
the line the log shows when empty. Each field has a docstring that says what
it draws, which the appearance tab shows under its name.

`make_fault_log_projection` gives the projection of a fault log its styles with
`get_fault_style`, from a theme scaled or not; a projection built with no styles
holds the plain values of the default theme.
"""
@theme struct FaultTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 13)
    "The count of the occurrences of a fault."
    count_text::TextRole = TextRole(:text_muted)
    "The barrier that catches a fault, such as `print`, `device` or `tool`."
    site_text::TextRole = TextRole(:text_muted)
    "The name of the type or the function whose code fails."
    origin_text::TextRole = TextRole(:error_text; weight = 700)
    "The message of the first occurrence of a fault."
    message_text::TextRole = TextRole(:text)
    "The line the log shows while it holds no fault."
    empty_text::TextRole = TextRole(:text_faint)
    "The surface of the panel that shows the log over the content of a window: dark and translucent, with a red cast, so the content stays readable and the panel says that it is not chrome."
    panel_background::StyleColor = ColorRole(:error_fill; alpha = 0.92)
    "The space between the panel and the edges of the window."
    panel_margin::Spacing = Spacing(12)
    "The space inside the panel, around the lines of the log."
    panel_padding::Spacing = Spacing(8)
    "The radius of the corners of the panel."
    panel_radius::Radius = Radius(4)
end

"""
    make_fault_log_panel_theme() -> FaultTheme

The fault theme of the panel over a window: the text that reads on a solid fill,
on the red of an error of the panel.
"""
make_fault_log_panel_theme() =
    FaultTheme(count_text = TextRole(:text_on_accent), site_text = TextRole(:text_on_accent),
               origin_text = TextRole(:text_on_accent; weight = 700),
               message_text = TextRole(:text_on_accent), empty_text = TextRole(:text_on_accent))

# The two presets, for the appearance tab: the log on a surface, and on its panel.
get_theme_presets(::Type{FaultTheme}) =
    Pair{String,Any}["Plain" => FaultTheme, "Panel" => make_fault_log_panel_theme]
