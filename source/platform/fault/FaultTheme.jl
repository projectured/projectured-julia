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

A fault log reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct FaultTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("DejaVu Sans Mono", 16)
    "The count of the occurrences of a fault."
    count_text::TextRole = TextRole(color_slate_500)
    "The barrier that catches a fault, such as `print`, `device` or `tool`."
    site_text::TextRole = TextRole(color_slate_500)
    "The name of the type or the function whose code fails."
    origin_text::TextRole = TextRole(color_solarized_red; weight = 700)
    "The message of the first occurrence of a fault."
    message_text::TextRole = TextRole(color_slate_700)
    "The line the log shows while it holds no fault."
    empty_text::TextRole = TextRole(color_slate_500)
end

# The style field of a fault log projection that holds the text `name` of the
# theme `theme`: a `FaultTheme`, a scaled one, or `nothing` for the default
# values.
_get_fault_style(theme, name::Symbol) = make_style_field(FaultTheme, scale_theme(theme), StyleText; name)
