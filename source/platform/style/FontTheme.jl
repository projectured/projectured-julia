# Fragment of `StyleModule` — the font theme: the roles of the fonts, one step of
# the type scale for each. A font role of any other theme names a role, and the
# scaled theme computes the font from the font theme of the appearance, as it
# computes a colour from the colour theme.

"""
    FontTheme

The roles of the fonts: what each text does, and the step of the type scale that
gives it. Every other theme names a role, with a [`FontRole`](@ref), so a change
of a family, of a size or of a weight here sets the type of every view. A role
never changes its size: a text that needs another size holds an exact
[`StyleFont`](@ref).

The two family fields give the family of each kind, `sans_family` and
`mono_family`, as `color_accent` gives the hue of the accent. A role field gives
the size, the weight, the slant and the kind of family of one role.

An appearance holds one font theme, for every colour mode.
"""
@theme struct FontTheme
    "The family of the sans steps: every text that is not code."
    sans_family::String = "Ubuntu"
    "The family of the mono steps: code, and no other text."
    mono_family::String = "Ubuntu Mono"
    "The title of a page: the help page, the about page, the title of an outline."
    page_title::FontStep = FontStep(:sans, 20; weight = 500)
    "The title of a part of the window: a pane, a card, a dialog."
    title::FontStep = FontStep(:sans, 16; weight = 500)
    "The text of the window: the frame, the controls, a row, a cell of a table, a tool panel."
    text::FontStep = FontStep(:sans, 13)
    "A label: the label of a form, the name of a field, the name of a setting."
    label::FontStep = FontStep(:sans, 13; weight = 500)
    "A head inside a row: an item of an accordion, the title of an alert or of a tooltip, the label of a turn."
    strong_text::FontStep = FontStep(:sans, 13; weight = 700)
    "The heading of a group inside a pane."
    section::FontStep = FontStep(:sans, 12; weight = 700)
    "The header of a column of a table, the title of an axis."
    column::FontStep = FontStep(:sans, 12; weight = 500)
    "A quiet text: a caption, a description, a hint, a footer, the status bar, a time, a count."
    quiet::FontStep = FontStep(:sans, 12)
    "A badge, a chip, a log level, the cap of a key."
    badge::FontStep = FontStep(:sans, 12; weight = 500)
    "The prose of a document, a message and a help text."
    document_text::FontStep = FontStep(:sans, 14)
    "The heading of the first level of a document."
    heading_1::FontStep = FontStep(:sans, 24; weight = 700)
    "The heading of the second level of a document."
    heading_2::FontStep = FontStep(:sans, 20; weight = 700)
    "The heading of the third level of a document."
    heading_3::FontStep = FontStep(:sans, 16; weight = 700)
    "The heading of the fourth level of a document."
    heading_4::FontStep = FontStep(:sans, 14; weight = 700)
    "The heading of the fifth level of a document."
    heading_5::FontStep = FontStep(:sans, 14; weight = 700)
    "The heading of the sixth level of a document."
    heading_6::FontStep = FontStep(:sans, 14; weight = 700)
    "Code in a tool panel."
    code::FontStep = FontStep(:mono, 13)
    "Code in a document and in every code view."
    document_code::FontStep = FontStep(:mono, 14)
end

"""
    get_font_theme(appearance) -> FontTheme

The font theme of `appearance`.
"""
get_font_theme(appearance::Appearance) = appearance.font_theme::FontTheme

"""
    resolve_font_role(role, appearance) -> StyleFont

The font that the [`FontRole`](@ref) `role`, which names a role of the font theme,
gives in `appearance`: the family that the font theme names for the kind of the
step, the size of the step, and the weight and the slant of `role` over those of
the step. The size is not scaled: [`scale_theme_value`](@ref) scales it once. A
computed cell that calls it follows a change of the font theme. A name that is no
field of [`FontTheme`](@ref) throws an `ArgumentError`.
"""
function resolve_font_role(role::FontRole, appearance::Appearance)
    name = role.role
    theme = get_font_theme(appearance)
    step = name in get_theme_field_names(FontTheme) ? getproperty(theme, name) : nothing
    step isa FontStep || throw(ArgumentError("the font theme has no role $(repr(name))"))
    family = step.family === :mono ? theme.mono_family : theme.sans_family
    StyleFont(family, step.size; weight = something(role.weight, step.weight),
              italic = something(role.italic, step.italic))
end
