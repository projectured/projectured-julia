# Fragment of `FaultViewModule` — the theme of the fault log: the text of its
# count, its site, its origin, its message, and its empty line.

"""
    FaultTheme

The theme of the fault log. `@theme` declares it, so `ScaledFaultTheme` holds
each value times its scale, and `FaultTheme()` is the default theme.

- `count_text` — how many places the fault was found in.
- `site_text` — where it was caught.
- `origin_text` — what failed.
- `message_text` — what it said.
- `empty_text` — the line the log shows while it holds no fault.

A fault log reads the scaled theme through its `UntrackedCell` style fields;
with no theme it holds the plain values of the default theme.
"""
@theme struct FaultTheme
    count_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    site_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
    origin_text::StyleText = StyleText(font_dejavu_monospace_bold_16, color_solarized_red)
    message_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_700)
    empty_text::StyleText = StyleText(font_dejavu_monospace_regular_16, color_slate_500)
end

# The style field of a fault log projection that holds the text `name` of the
# theme `theme`: a `FaultTheme`, a scaled one, or `nothing` for the default
# values.
_get_fault_style(theme, name::Symbol) = make_style_field(FaultTheme, scale_theme(theme), StyleText, name)
