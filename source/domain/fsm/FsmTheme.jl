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

A Fsm projection reads the scaled theme through its `UntrackedCell` style
fields; with no theme it holds the plain values of the default theme.
"""
@theme struct FsmTheme
    "The keywords: `component`, `variable`, `timer`, `event`, `machine`, `state`, `initial`, `on`, `when`, `stay`, `ignore`, `entry` and `ignoring unhandled`."
    keyword_text::StyleText     = StyleText(StyleFont("Ubuntu Mono", 20; weight = 700), color_solarized_blue)
    "The name of a component, a variable, a timer, an event, a machine or a state."
    name_text::StyleText        = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_green)
    "A trigger, a target and an `initial`, read from the referenced part, and the reference of a transition label in a diagram."
    reference_text::StyleText   = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_violet)
    "The punctuation around a part, and the chrome of a transition label in a diagram."
    chrome_text::StyleText      = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_gray)
    "The name of a state in a diagram."
    state_label_text::StyleText = StyleText(StyleFont("Ubuntu Mono", 20; weight = 700), color_solarized_green)
    "The keyword of a transition label in a diagram."
    trigger_text::StyleText     = StyleText(StyleFont("Ubuntu Mono", 20), color_solarized_blue)
end

# The style field of a Fsm projection that holds the text `name` of the theme
# `theme`: a `FsmTheme`, a scaled one, or `nothing` for the default values.
_get_fsm_style(theme, name::Symbol) = make_style_field(FsmTheme, scale_theme(theme), StyleText; name)
