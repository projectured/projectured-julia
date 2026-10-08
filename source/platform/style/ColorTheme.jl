# Fragment of `StyleModule` — the colour theme: the roles of the colours, what a
# role and a step of a ramp resolve to in an appearance, and the four colour
# themes of an appearance, one for each mode and contrast.

"""
    ColorTheme

The roles of the colours: what each colour does, and the step of a ramp of the
palette that gives it. Every other theme names a role, with a
[`ColorRole`](@ref), and this theme names the step, with a
[`PaletteColor`](@ref), so a change of the palette, the mode, the contrast, the
accent or the neutral of the appearance recolours every view.

An appearance holds one colour theme for each pair of a mode and a contrast
([`make_color_theme`](@ref)). A person fine-tunes a role in the theme of the
present pair, with another step or with a fixed colour, and the fine-tune stays
with that pair.

The roles are in groups: the surfaces, the texts, the lines, the accent, the
layers of a state, the status, the tokens of a language, the series of a chart
and the overlays. A text role of a token reaches a contrast of 4.5 against the
backgrounds, and 7 in a high contrast theme.

Each kind of value and each kind of name has a role of its own, the same in
every view: a string, a number, a boolean, a symbol; a function, a type, a
module, a parameter, a variable, a field. A role can name another role: a
character takes the colour of a string, a null the colour of a boolean, and a
macro the colour of a function, until a person gives it a step of its own. A
name at its definition takes the role of its kind, and its theme makes it
bold.
"""
@theme struct ColorTheme
    # ── Surfaces ──
    "The background of a window and of an editor."
    background::StyleColor = PaletteColor(:neutral, 2)
    "A raised surface: a card, a menu, a popup, a panel. It is lighter than the background in both modes."
    surface::StyleColor = PaletteColor(:neutral, 1)
    "A quiet surface: a track, a gutter, a disabled control, a sunken field."
    surface_sunken::StyleColor = PaletteColor(:neutral, 3)
    "A panel over the content of a window, such as the fault log: dark in the light mode, light in the dark mode."
    surface_inverse::StyleColor = PaletteColor(:neutral, 12; alpha = 0.92)
    # ── Texts ──
    "The text: prose, a label, a value, a plain name."
    text::StyleColor = PaletteColor(:neutral, 12)
    "A quiet text: a caption, a detail, a number of a line."
    text_muted::StyleColor = PaletteColor(:neutral, 11; minimum_contrast = 4.5)
    "A faint text: a placeholder, a hint, a disabled label."
    text_faint::StyleColor = PaletteColor(:neutral, 10; minimum_contrast = 3.0)
    "A text on a solid fill of the accent or of a status."
    text_on_accent::StyleColor = color_white
    "A text on the inverse surface."
    text_inverse::StyleColor = PaletteColor(:neutral, 1)
    "A quiet text on the inverse surface."
    text_inverse_muted::StyleColor = PaletteColor(:neutral, 8)
    # ── Lines ──
    "A faint line: the border of a card and of a pane, a separator."
    border::StyleColor = PaletteColor(:neutral, 6)
    "A strong line: the border of a control that takes a value, an axis."
    border_strong::StyleColor = PaletteColor(:neutral, 8; minimum_contrast = 3.0)
    "A grid line and a hairline of a chart."
    grid::StyleColor = PaletteColor(:neutral, 4)
    # ── Accent ──
    "A solid fill of the accent: a default button, a checked box, a progress bar; white text reads on it."
    accent::StyleColor = PaletteColor(:accent, 9; minimum_contrast = 4.5, against = color_white)
    "The solid fill of the accent under the pointer."
    accent_hover::StyleColor = PaletteColor(:accent, 10; minimum_contrast = 4.5, against = color_white)
    "A text in the accent: a link, the current item."
    accent_text::StyleColor = PaletteColor(:accent, 11; minimum_contrast = 4.5)
    "A tint of the accent: the fill of a hovered or a chosen item of a list or a menu."
    accent_tint::StyleColor = PaletteColor(:accent, 3)
    "The ring around the control that holds the keyboard. It differs from the selection ring, so a control selected as a whole and a control with the caret look different."
    focus_ring::StyleColor = PaletteColor(:accent, 8; minimum_contrast = 3.0)
    # ── Layers of a state ──
    "The layer over a part under the pointer."
    hover::StyleColor = PaletteColor(:neutral, 12; alpha = 0.06)
    "The layer over a pressed part."
    pressed::StyleColor = PaletteColor(:neutral, 12; alpha = 0.12)
    "The band under a selected text and a selected row, while it holds the keyboard."
    selection_band::StyleColor = PaletteColor(:accent, 9; alpha = 0.25)
    "The band under a selected text, while another part holds the keyboard."
    selection_band_dormant::StyleColor = PaletteColor(:neutral, 9; alpha = 0.2)
    "The ring around a part that is selected as a whole."
    selection_ring::StyleColor = PaletteColor(:accent, 9; minimum_contrast = 3.0)
    "The band under a match of a search."
    search_match::StyleColor = PaletteColor(:amber, 9; alpha = 0.45)
    "The caret of the text that holds the keyboard."
    caret::StyleColor = PaletteColor(:neutral, 12)
    "The caret of a text that keeps its place while another holds the keyboard."
    caret_dormant::StyleColor = PaletteColor(:neutral, 9)
    # ── Status ──
    "A solid mark of an error, and the fill of an action that deletes; white text reads on it."
    error_fill::StyleColor = PaletteColor(:red, 9; minimum_contrast = 4.5, against = color_white)
    "The text of an error: a message, a value that does not parse, a fault."
    error_text::StyleColor = PaletteColor(:red, 11; minimum_contrast = 4.5)
    "A tint of an error: the fill behind a field that does not parse."
    error_tint::StyleColor = PaletteColor(:red, 3)
    "A solid mark of a warning."
    warning_fill::StyleColor = PaletteColor(:amber, 9)
    "The text of a warning, and of a step where a run stops."
    warning_text::StyleColor = PaletteColor(:amber, 11; minimum_contrast = 4.5)
    "A tint of a warning."
    warning_tint::StyleColor = PaletteColor(:amber, 3)
    "A solid mark of a success; white text reads on it."
    success_fill::StyleColor = PaletteColor(:green, 9; minimum_contrast = 4.5, against = color_white)
    "The text of a success: a value that names a known thing."
    success_text::StyleColor = PaletteColor(:green, 11; minimum_contrast = 4.5)
    "A tint of a success."
    success_tint::StyleColor = PaletteColor(:green, 3)
    "A solid mark of an information."
    info_fill::StyleColor = PaletteColor(:blue, 9)
    "The text of an information, such as the level of a message."
    info_text::StyleColor = PaletteColor(:blue, 11; minimum_contrast = 4.5)
    "A tint of an information."
    info_tint::StyleColor = PaletteColor(:blue, 3)
    # ── Tokens ──
    "A keyword of a language, a directive."
    keyword::StyleColor = PaletteColor(:violet, 11; minimum_contrast = 4.5)
    "The name of a declared thing: a function, a module, a table, a state, a formula."
    definition::StyleColor = PaletteColor(:blue, 11; minimum_contrast = 4.5)
    "A function, at its definition and at a call, a function of mathematics, a process."
    function_name::StyleColor = PaletteColor(:blue, 11; minimum_contrast = 4.5)
    "A macro. It takes the colour of a function."
    macro_name::StyleColor = ColorRole(:function_name)
    "An event and a timer of a machine. It takes the colour of a function."
    event::StyleColor = ColorRole(:function_name)
    "A field, a field after a dot, a key, an attribute, a column."
    field::StyleColor = PaletteColor(:blue, 11; minimum_contrast = 4.5)
    "A string, a code span, a literal block."
    string_literal::StyleColor = PaletteColor(:green, 11; minimum_contrast = 4.5)
    "A character. It takes the colour of a string."
    character_literal::StyleColor = ColorRole(:string_literal)
    "A number: an integer, a float, an index."
    number_literal::StyleColor = PaletteColor(:orange, 11; minimum_contrast = 4.5)
    "A boolean: `true` and `false`."
    boolean_literal::StyleColor = PaletteColor(:pink, 11; minimum_contrast = 4.5)
    "A null: `null`, `nothing`, `missing`. It takes the colour of a boolean."
    null_literal::StyleColor = ColorRole(:boolean_literal)
    "A symbol, such as `:name`."
    symbol_literal::StyleColor = PaletteColor(:teal, 11; minimum_contrast = 4.5)
    "A named constant that is no literal: a constant of mathematics, a substitution, the value of a field of a packet."
    constant::StyleColor = PaletteColor(:orange, 11; minimum_contrast = 4.5)
    "A type, a struct, a SQL table, a data type, a machine and a component of an FSM."
    type_name::StyleColor = PaletteColor(:amber, 11; minimum_contrast = 4.5)
    "A parameter of a type, such as a variable of `where`. It takes the colour of a type."
    type_parameter::StyleColor = ColorRole(:type_name)
    "A module, a schema, a database, a folder. It takes the colour of a type."
    module_name::StyleColor = ColorRole(:type_name)
    "A use of a name: a variable, a reference to another part."
    reference::StyleColor = PaletteColor(:neutral, 12)
    "A variable, and a name of a kind that the view does not know."
    variable::StyleColor = PaletteColor(:neutral, 12)
    "A parameter of a function, the name of a keyword argument, the name of an option. It takes the colour of a variable."
    parameter::StyleColor = ColorRole(:variable)
    "A member of a fixed set of named values, such as a state of a machine. It takes the colour of a symbol."
    enum_member::StyleColor = ColorRole(:symbol_literal)
    "A tag of a markup, such as an XML element. It takes the colour of a keyword."
    tag::StyleColor = ColorRole(:keyword)
    "A link, a URL, a cross-reference."
    link::StyleColor = PaletteColor(:accent, 11; minimum_contrast = 4.5)
    "An operator."
    operator::StyleColor = PaletteColor(:neutral, 11; minimum_contrast = 4.5)
    "A bracket, a comma, a colon, a quote."
    punctuation::StyleColor = PaletteColor(:neutral, 11; minimum_contrast = 4.5)
    "The brackets around the part under the pointer."
    punctuation_lit::StyleColor = PaletteColor(:neutral, 12)
    "A comment."
    comment::StyleColor = PaletteColor(:neutral, 11; minimum_contrast = 4.5)
    "A mark of a markup: a heading mark, a bullet, an emphasis mark, a fence."
    markup::StyleColor = PaletteColor(:neutral, 11; minimum_contrast = 4.5)
    "A heading and a title."
    heading::StyleColor = PaletteColor(:neutral, 12)
    # ── Series of a chart ──
    "The first series of a chart."
    series_1::StyleColor = PaletteColor(:blue, 9)
    "The second series of a chart."
    series_2::StyleColor = PaletteColor(:orange, 9)
    "The third series of a chart."
    series_3::StyleColor = PaletteColor(:green, 9)
    "The fourth series of a chart."
    series_4::StyleColor = PaletteColor(:pink, 9)
    "The fifth series of a chart."
    series_5::StyleColor = PaletteColor(:teal, 9)
    "The sixth series of a chart."
    series_6::StyleColor = PaletteColor(:violet, 9)
    "The seventh series of a chart."
    series_7::StyleColor = PaletteColor(:amber, 9)
    "The eighth series of a chart."
    series_8::StyleColor = PaletteColor(:red, 9)
    # ── Overlays ──
    "The shadow under a raised part."
    shadow::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.08)
    "The layer that covers the window behind a dialog."
    scrim::StyleColor = StyleColor(0.0, 0.0, 0.0, 0.4)
end

"""
    COLOR_VARIANTS

The names of the four colour themes of an appearance: `:light`, `:dark`,
`:light_high_contrast` and `:dark_high_contrast`.
"""
const COLOR_VARIANTS = (:light, :dark, :light_high_contrast, :dark_high_contrast)

"""
    get_color_variant(mode, contrast) -> Symbol
    get_color_variant(appearance) -> Symbol

The name of the colour theme of a mode and a contrast, one of
[`COLOR_VARIANTS`](@ref): the mode, with `_high_contrast` for the high contrast.
A mode that is not known is light.
"""
get_color_variant(mode::Symbol, contrast::Symbol) =
    Symbol(mode === :dark ? "dark" : "light", contrast === :high ? "_high_contrast" : "")
get_color_variant(appearance::Appearance) =
    get_color_variant(get_color_mode(appearance), get_color_contrast(appearance))

"""
    make_color_theme(variant) -> ColorTheme

The default colour theme of `variant`, one of [`COLOR_VARIANTS`](@ref). A raised
surface is lighter than the background: step 1 on step 2 in the light mode, and
step 2 on step 1 in the dark mode. The selection ring differs from the focus ring
in each variant: step 9 of the accent against step 8 in the light mode, step 11
against step 8 in the dark mode, and step 12 against step 11 in a high contrast
theme. A dark theme has darker shadows and scrims; a
high contrast theme has one surface, takes its texts, its tokens and its lines to
a contrast of 7, and its layers further from the surface.
"""
function make_color_theme(variant::Symbol)
    variant in COLOR_VARIANTS ||
        throw(ArgumentError("$(repr(variant)) is no colour variant; the variants are $(COLOR_VARIANTS)"))
    dark = variant in (:dark, :dark_high_contrast) ?
        (background = PaletteColor(:neutral, 1), surface = PaletteColor(:neutral, 2),
         selection_ring = PaletteColor(:accent, 11; minimum_contrast = 3.0),
         shadow = StyleColor(0.0, 0.0, 0.0, 0.4), scrim = StyleColor(0.0, 0.0, 0.0, 0.6)) : (;)
    high = variant in (:light_high_contrast, :dark_high_contrast) ? (
        background = PaletteColor(:neutral, 1),
        surface = PaletteColor(:neutral, 1),
        surface_sunken = PaletteColor(:neutral, 2),
        surface_inverse = PaletteColor(:neutral, 12),
        text_muted = PaletteColor(:neutral, 11; minimum_contrast = 7.0),
        text_faint = PaletteColor(:neutral, 11; minimum_contrast = 4.5),
        border = PaletteColor(:neutral, 11; minimum_contrast = 4.5),
        border_strong = PaletteColor(:neutral, 12),
        grid = PaletteColor(:neutral, 8; minimum_contrast = 3.0),
        accent = PaletteColor(:accent, 11; minimum_contrast = 7.0, against = color_white),
        accent_text = PaletteColor(:accent, 11; minimum_contrast = 7.0),
        focus_ring = PaletteColor(:accent, 11; minimum_contrast = 4.5),
        hover = PaletteColor(:neutral, 12; alpha = 0.12),
        pressed = PaletteColor(:neutral, 12; alpha = 0.2),
        selection_band = PaletteColor(:accent, 9; alpha = 0.4),
        selection_band_dormant = PaletteColor(:neutral, 9; alpha = 0.35),
        selection_ring = PaletteColor(:accent, 12),
        search_match = PaletteColor(:amber, 9; alpha = 0.7),
        error_fill = PaletteColor(:red, 11; minimum_contrast = 7.0, against = color_white),
        error_text = PaletteColor(:red, 11; minimum_contrast = 7.0),
        warning_text = PaletteColor(:amber, 11; minimum_contrast = 7.0),
        success_fill = PaletteColor(:green, 11; minimum_contrast = 7.0, against = color_white),
        success_text = PaletteColor(:green, 11; minimum_contrast = 7.0),
        info_text = PaletteColor(:blue, 11; minimum_contrast = 7.0),
        keyword = PaletteColor(:violet, 11; minimum_contrast = 7.0),
        definition = PaletteColor(:blue, 11; minimum_contrast = 7.0),
        function_name = PaletteColor(:blue, 11; minimum_contrast = 7.0),
        field = PaletteColor(:blue, 11; minimum_contrast = 7.0),
        string_literal = PaletteColor(:green, 11; minimum_contrast = 7.0),
        number_literal = PaletteColor(:orange, 11; minimum_contrast = 7.0),
        boolean_literal = PaletteColor(:pink, 11; minimum_contrast = 7.0),
        symbol_literal = PaletteColor(:teal, 11; minimum_contrast = 7.0),
        constant = PaletteColor(:orange, 11; minimum_contrast = 7.0),
        type_name = PaletteColor(:amber, 11; minimum_contrast = 7.0),
        link = PaletteColor(:accent, 11; minimum_contrast = 7.0),
        operator = PaletteColor(:neutral, 11; minimum_contrast = 7.0),
        punctuation = PaletteColor(:neutral, 11; minimum_contrast = 7.0),
        comment = PaletteColor(:neutral, 11; minimum_contrast = 7.0),
        markup = PaletteColor(:neutral, 11; minimum_contrast = 7.0),
        series_1 = PaletteColor(:blue, 10), series_2 = PaletteColor(:orange, 10),
        series_3 = PaletteColor(:green, 10), series_4 = PaletteColor(:pink, 10),
        series_5 = PaletteColor(:teal, 10), series_6 = PaletteColor(:violet, 10),
        series_7 = PaletteColor(:amber, 10), series_8 = PaletteColor(:red, 10)) : (;)
    ColorTheme(; merge(dark, high)...)
end

"""
    make_color_themes() -> Dict{Symbol,Any}

A new colour theme of each of [`COLOR_VARIANTS`](@ref), by its name: the
`color_themes` of a new appearance.
"""
make_color_themes() = Dict{Symbol,Any}(variant => make_color_theme(variant) for variant in COLOR_VARIANTS)

"""
    get_color_theme(appearance) -> ColorTheme

The colour theme of the present mode and contrast of `appearance`.
"""
get_color_theme(appearance::Appearance) =
    appearance.color_themes[get_color_variant(appearance)]

"""
    get_color_mode(appearance) -> Symbol
    get_color_contrast(appearance) -> Symbol

The mode, `:light` or `:dark`, and the contrast, `:normal` or `:high`, that the
colours of `appearance` use: the setting, or for `:system` the setting of the
operating system that `appearance.system_colors` holds. A mode that is not known
is light, and a contrast that is not known is normal.
"""
function get_color_mode(appearance::Appearance)
    mode = appearance.color_mode
    mode === :system && (mode = appearance.system_colors.mode)
    mode === :dark ? :dark : :light
end
function get_color_contrast(appearance::Appearance)
    contrast = appearance.color_contrast
    contrast === :system && (contrast = appearance.system_colors.contrast)
    contrast === :high ? :high : :normal
end

"""
    get_color_accent(appearance) -> Symbol

The hue of the accent that the colours of `appearance` use: the setting, or for
`:system` the hue that [`find_nearest_accent_hue`](@ref) finds for the accent of
the operating system, and `:blue` when the system names no accent or a grey one.
"""
function get_color_accent(appearance::Appearance)
    accent = appearance.color_accent
    accent === :system || return accent
    bytes = appearance.system_colors.accent
    bytes === nothing && return :blue
    color = StyleColor((Float64(byte) / 255 for byte in bytes)..., 1.0)
    something(find_nearest_accent_hue(color, _get_appearance_palette(appearance),
                                      get_color_mode(appearance)), :blue)
end

# The least chroma of a colour that has a hue; a colour with less is grey.
const _LEAST_ACCENT_CHROMA = 0.04

"""
    find_nearest_accent_hue(color, palette, mode) -> Symbol or nothing

The hue of `palette`, other than the neutral, whose solid step (step 9) in `mode`
has the OKLCH hue angle nearest to that of `color`; `nothing` for a grey `color`,
which has no hue.
"""
function find_nearest_accent_hue(color::StyleColor, palette::Palette, mode::Symbol)
    _, chroma, angle = convert_color_to_oklch(color)
    chroma < _LEAST_ACCENT_CHROMA && return nothing
    nearest, nearest_distance = nothing, Inf
    for hue in PALETTE_HUES
        hue === :neutral && continue
        ramp = find_palette_ramp(palette, hue, mode)
        ramp === nothing && continue
        _, _, hue_angle = convert_color_to_oklch(ramp[9])
        distance = abs(mod(angle - hue_angle + 180, 360) - 180)
        distance < nearest_distance && ((nearest, nearest_distance) = (hue, distance))
    end
    nearest
end

# The palette of `appearance`, or the default palette when the registry holds no
# palette of its name.
_get_appearance_palette(appearance::Appearance) =
    something(find_palette(appearance.color_palette), find_palette(DEFAULT_PALETTE_NAME))

"""
    resolve_theme_color(color, appearance) -> StyleColor

The colour that the [`ThemeColor`](@ref) `color` gives in `appearance`: a
`StyleColor` as it is; a [`PaletteColor`](@ref) the step of the palette, the mode,
the neutral and the accent of `appearance` (a palette that the registry does not
hold is the default palette); a [`ColorRole`](@ref) the colour that the colour
theme of the present mode and contrast gives the role. A computed cell that calls
it follows a change of each of these.
"""
resolve_theme_color(color::StyleColor, ::Appearance) = color
function resolve_theme_color(color::PaletteColor, appearance::Appearance)
    compute_palette_color(_get_appearance_palette(appearance), color, get_color_mode(appearance);
                          neutral = appearance.color_neutral, accent = get_color_accent(appearance))
end
function resolve_theme_color(color::ColorRole, appearance::Appearance)
    value = color
    for _ in 1:8
        value isa ColorRole || break
        value.role in get_theme_field_names(ColorTheme) ||
            throw(ArgumentError("the colour theme has no role $(repr(value.role))"))
        alpha = value.alpha
        value = getproperty(get_color_theme(appearance), value.role)
        alpha == 1 || (value = _multiply_alpha(value, alpha))
    end
    value isa ColorRole &&
        throw(ArgumentError("the role $(repr(color.role)) names roles in a cycle"))
    resolve_theme_color(value, appearance)
end

# `color` with its alpha times `alpha`.
_multiply_alpha(color::StyleColor, alpha::Real) =
    StyleColor(color.red, color.green, color.blue, color.alpha * alpha)
_multiply_alpha(color::PaletteColor, alpha::Real) =
    PaletteColor(color.hue, color.step; alpha = color.alpha * alpha,
                 minimum_contrast = color.minimum_contrast, against = color.against)
_multiply_alpha(color::ColorRole, alpha::Real) = ColorRole(color.role; alpha = color.alpha * alpha)

# A step of a ramp and a role take the colour that they give in the appearance,
# and a list of colours takes the colour of each.
scale_theme_value(color::Union{PaletteColor, ColorRole}, appearance::Appearance) =
    resolve_theme_color(color, appearance)
scale_theme_value(colors::AbstractVector{<:ThemeColor}, appearance::Appearance) =
    StyleColor[resolve_theme_color(color, appearance) for color in colors]
