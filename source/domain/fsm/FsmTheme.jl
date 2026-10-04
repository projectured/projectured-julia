# Fragment of `FsmModule` — the theme of the fsm syntax: the keyword, the name
# of a part, a reference to another part, the chrome around them, and the
# label of a state and a transition in a diagram.

"""
    FsmTheme

The fonts and the colors of a state machine: its keywords, its names, its
references and the labels of a state diagram.

The theme of the Fsm projections. `@theme` declares it, so `ScaledFsmTheme`
holds each value times its scale, and `FsmTheme()` is the default theme.

The fields are the text styles of a keyword, a name, a reference, chrome, and
the label and the trigger of a diagram. Each field has a docstring that says
what it draws, which the appearance tab shows under its name.

The builder gives each Fsm projection its styles with `get_fsm_style`, from a
theme scaled or not; a projection built with no styles holds the plain values
of the default theme.
"""
@theme struct FsmTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu Mono", 14)
    "The keywords: `component`, `variable`, `timer`, `event`, `machine`, `state`, `initial`, `on`, `when`, `stay`, `ignore`, `entry` and `ignoring unhandled`."
    keyword_text::TextRole     = TextRole(color_solarized_blue; weight = 700)
    "The name of a component, a variable, a timer, an event, a machine or a state."
    name_text::TextRole        = TextRole(color_solarized_green)
    "A trigger, a target and an `initial`, read from the referenced part, and the reference of a transition label in a diagram."
    reference_text::TextRole   = TextRole(color_solarized_violet)
    "The punctuation around a part, and the chrome of a transition label in a diagram."
    chrome_text::TextRole      = TextRole(color_solarized_gray)
    "The name of a state in a diagram."
    state_label_text::TextRole = TextRole(color_solarized_green; weight = 700)
    "The keyword of a transition label in a diagram."
    trigger_text::TextRole     = TextRole(color_solarized_blue)
end
