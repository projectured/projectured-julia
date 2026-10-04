# Fragment of `AppearanceModule` — the appearance tab: an `Appearance` shown as
# widgets that step its zoom and its scales.

"""
    AppearanceToWidget(; scroll_pane)

Show an `Appearance` as widgets, in a pane that scrolls:

- a row for the zoom and one for each of the six scales, each with its name, a
  − button, its value in percent, a + button and a reset button, and under the
  rows the buttons "Reset all", "Save" and "Load", which save the appearance in
  the file of `get_appearance_file` and read it back;
- the group "Colors": a row for each of the five colour settings, the mode, the
  contrast, the palette, the accent and the neutral, each with its name, buttons
  ‹ and › that step through its values, and its value; and the card of the
  colour theme of the present mode and contrast, with a row for each role;
- the themes of the appearance in three groups: "Editor", the widget, the text,
  the syntax and the reference themes, which every view draws with; "Tools", the
  other themes of `ProjecturedPlatform`; and "Documents", the themes of the other
  packages, in the order of their names;
- a card for each theme, which folds to its title, and which the tab shows open
  when the `open_sections` of the appearance name it. The card starts with the
  summary of its theme type, the first paragraph of its docstring. It holds the
  presets of the theme, as a choice that writes every field of the preset into
  the theme, and a row for each field, its name and its control; under that row,
  across the card, the docstring of the field, in the small font and the muted
  color of the widget theme. A size has a spin box for each of its parts, a font has buttons that step through
  the font files and a spin box for its size, a colour has its swatch and its
  value as a text, `#rrggbbaa`, that a person edits, and a text style has the
  controls of its colour over those of its font. A role of the colour theme has
  its swatch and buttons that step through the roles; a step of a ramp has
  buttons that step through the hues and through the steps; both have a button
  "Fix", which writes the colour that they give as a fixed colour. A colour that
  differs from the default of its theme has a button "Reset".

A press of a button answers the operation of the button, and a step of a spin box,
a choice of a preset or an edit of a colour answers a write of the theme, so the
`appearance` wrapper of the editor prints the view again, with this tab.

- A write of a theme is an edit: the wrapper makes it a
  `ReplaceThemeValueOperation`, so a history around the tab, such as the history
  of a window, records it, and Ctrl+Z takes it back and prints the view again.
- A step of the zoom or of a scale takes nothing back, as from its keys.
- A press on the chevron of a card answers a write of `open_sections`, and a
  scroll of the tab a write of `scroll_position`. Both are view state: the
  history does not record them, and no view prints again; the card and the pane
  follow their cells.

The gaps of the tab are those of the widget theme of the appearance, so they
follow its spacing scale. `scroll_pane` is the printer
of a `WidgetScrollPane` with the widget theme of the editor, which draws the pane
and, through the recursion, the widgets in it.

The appearance holds the caret of a colour text, and the part under the pointer,
as a path that this projection introduces: a path in its widget tree, from the
pane. The tree has the same form at each print, so the path names the same text
after the print that a write starts.
"""
struct AppearanceToWidget <: Projection
    scroll_pane::Any        # the printer of the pane, with the widget theme of the editor
end

AppearanceToWidget(; scroll_pane) = AppearanceToWidget(scroll_pane)

# `commands` holds the operation of each button of the print, by the `Action` of
# the button: a press answers `InvokeActionOperation` with that `Action`. `writes`
# holds, for each spin box and each choice, the function from the value that it
# writes to the operation that the tab answers. `edits` holds, for each colour
# text, the function from an edit of the text (its start, its stop and the new
# characters) to the write of the colour and the place of the caret after it, or
# to `nothing` when the edit names no colour. `folds` holds, for each card of a
# theme, the name of the theme type.
@iomap struct AppearanceToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
    commands::Any
    writes::Any
    edits::Any
    folds::Any
end

get_child_iomaps(iomap::AppearanceToWidgetIoMap) = Any[iomap.child_iomap]

# The rows of the tab, in order: the field of the appearance and its name.
const _APPEARANCE_ROWS = ((:zoom, "Zoom"), (:font_scale, "Text"), (:icon_scale, "Icons"),
                          (:spacing_scale, "Spacing"), (:control_scale, "Controls"),
                          (:radius_scale, "Corners"), (:line_scale, "Lines"))

# The operation that steps the field `field` of `appearance` by `delta`.
_make_step_operation(appearance::Appearance, field::Symbol, delta::Integer) =
    field === :zoom ? AdjustZoomOperation(appearance, delta) :
                      AdjustScaleOperation(appearance, field, delta)

# A factor as a person reads it, in percent.
_get_percent_text(factor::Real) = string(round(Int, factor * 100), "%")

# A write of the field `field` of `theme`. It is an edit: the `appearance` wrapper
# makes it a `ReplaceThemeValueOperation`, and a history around the tab records it.
_write_theme_field(theme, field::Symbol, value) =
    ReplaceReferencedValueOperation(theme, String(field), value)

# The families that a font of a theme can take, in the order of their names: the
# bundled families, without the icon font and the emoji font.
_get_theme_font_families() =
    filter(family -> !(family in ("Lucide", "Noto Emoji")), get_font_families())

# The font `delta` families away from `font` in the list of the families, at the
# size, the weight and the slant of `font`.
function _step_font_family(font::StyleFont, delta::Integer)
    families = _get_theme_font_families()
    i = something(findfirst(==(font.family), families), 1)
    StyleFont(families[mod1(i + delta, length(families))], font.size;
              weight = font.weight, italic = font.italic)
end

# The names of the weights on the scale of CSS.
const _FONT_WEIGHT_NAMES = Dict(100 => "Thin", 200 => "Extra Light", 300 => "Light",
                                400 => "Regular", 500 => "Medium", 600 => "Semi Bold",
                                700 => "Bold", 800 => "Extra Bold", 900 => "Black")

_get_font_weight_name(weight::Integer) = get(_FONT_WEIGHT_NAMES, Int(weight), string(weight))

# The font `delta` weights of its family away from `font`: one heavier for 1, one
# lighter for -1, and no further than the heaviest or the lightest. A weight that
# the family does not have steps from the nearest one that it has.
function _step_font_weight(font::StyleFont, delta::Integer)
    weights = get_font_weights(font.family)
    isempty(weights) && return font
    i = something(findfirst(==(Int(font.weight)), weights), argmin(abs.(weights .- font.weight)))
    StyleFont(font.family, font.size; weight = weights[clamp(i + delta, 1, length(weights))],
              italic = font.italic)
end

# `font` upright, or italic when `italic` is true.
_with_font_italic(font::StyleFont, italic::Bool) =
    StyleFont(font.family, font.size; weight = font.weight, italic)

# A size of a theme with `part` replaced by `value`: a part of an inset, of a
# point, or the size itself.
_replace_length_part(inset::Inset, part::Symbol, value) =
    Inset(part === :top ? value : inset.top[], part === :bottom ? value : inset.bottom[],
          part === :left ? value : inset.left[], part === :right ? value : inset.right[])
_replace_length_part(point::Point2D, part::Symbol, value) =
    Point2D(part === :x ? value : point.x[], part === :y ? value : point.y[])
_replace_length_part(::Real, ::Symbol, value) = value

# The parts of a size that a spin box each edits, with their names.
_get_length_parts(::Inset) = ((:top, "top"), (:bottom, "bottom"), (:left, "left"), (:right, "right"))
_get_length_parts(::Point2D) = ((:x, "width"), (:y, "height"))
_get_length_parts(::Real) = ((:value, ""),)
_get_length_part(inset::Inset, part::Symbol) = getproperty(inset, part)[]
_get_length_part(point::Point2D, part::Symbol) = getproperty(point, part)[]
_get_length_part(value::Real, ::Symbol) = value

function print_document(p::AppearanceToWidget, recursion, appearance::Appearance, ctx)
    commands = IdDict{Any,Any}()
    writes = IdDict{Any,Any}()
    edits = IdDict{Any,Any}()
    folds = IdDict{Any,Any}()
    theme = _get_widget_theme(appearance)
    # A button whose press answers `operation`. Its callback evaluates the same
    # operation, for a view that shows the tab with no reader of this projection.
    function button(label, operation)
        action = Action(label; callback = editor -> evaluate_operation(editor, operation))
        commands[action] = operation
        WidgetButton(label; action)
    end
    function spin_box(value, write; min = 0, max = 400)
        box = WidgetSpinBox(Int(round(value)); min, max)
        writes[box] = write
        box
    end
    # A checkbox of `value` that says `label`; a click answers `write(!value)`.
    function checkbox(value, write; label = nothing)
        box = WidgetCheckbox(value; label)
        writes[box] = write
        box
    end
    # A choice of `labels`, with none chosen; the choice of an index answers
    # `write(index)`.
    function choice(labels, write)
        group = WidgetRadioGroup(labels; selected = 0)
        writes[group] = write
        group
    end
    # The text of the colour that `read()` answers; `write(color)` is the
    # operation that sets a new colour.
    function color_text(read, write)
        text = WidgetText(format_style_color(read()); validator = _is_color_input)
        edits[text] = (start, stop, replacement) ->
            _compute_color_edit(read, write, start, stop, replacement)
        text
    end
    controls = (; button, spin_box, checkbox, choice, color_text, theme, appearance, folds,
                defaults = IdDict{Any,Any}())
    cells = Any[]
    for (field, name) in _APPEARANCE_ROWS
        push!(cells, WidgetLabel(name),
              button("−", _make_step_operation(appearance, field, -1)),
              WidgetLabel(_get_percent_text(getproperty(appearance, field))),
              button("+", _make_step_operation(appearance, field, 1)),
              button("Reset", _make_step_operation(appearance, field, 0)))
    end
    reset_all = CompoundOperation(Any[Any[_make_step_operation(appearance, field, 0)
                                          for (field, _) in _APPEARANCE_ROWS];
                                      Any[_write_color_setting(appearance, field, value)
                                          for (field, value) in pairs(_COLOR_SETTING_DEFAULTS)]])
    parts = Any[GridLayout(cells, 5; horizontal_gap = theme.label_gap, vertical_gap = theme.item_gap,
                           vertical_align = :center),
                HorizontalLayout(Any[button("Reset all", reset_all),
                                     button("Save", SaveAppearanceOperation(appearance)),
                                     button("Load", LoadAppearanceOperation(appearance))];
                                 gap = theme.label_gap)]
    push!(parts, WidgetLabel("Colors"; text_style = StyleText(theme.font_bold, theme.muted_foreground)),
          _make_color_settings(controls),
          _make_theme_section(controls, get_color_theme(appearance)))
    for (title, themes) in _get_theme_groups(appearance)
        isempty(themes) && continue
        push!(parts, WidgetLabel(title; text_style = StyleText(theme.font_bold, theme.muted_foreground)))
        for section_theme in themes
            push!(parts, _make_theme_section(controls, section_theme))
        end
    end
    content = VerticalLayout(parts; gap = theme.section_gap)
    # The pane scrolls the cell of the appearance: the next print, which a write of
    # the appearance starts, makes a new pane at the same place.
    pane = WidgetScrollPane(content; scroll_position = getfield(appearance, :scroll_position))
    _follow_tab_paths!(p, appearance, pane)
    child = print_document(p.scroll_pane, recursion, pane, ctx)
    AppearanceToWidgetIoMap(p, appearance, child.output, child, commands, writes, edits, folds)
end

# The themes that every view of the editor draws with, in the order of the group
# "Editor" of the tab.
const _EDITOR_THEME_TYPES = (WidgetTheme, TextTheme, SyntaxTheme, ReferenceTheme, GraphicsTheme, TooltipTheme)

# The groups of the tab: each a title and the themes of `appearance` that it shows.
# A theme of `ProjecturedPlatform` that is no editor theme is the theme of a tool,
# and a theme of another package is the theme of a document.
function _get_theme_groups(appearance::Appearance)
    themes = sort!([entry.theme for entry in values(appearance.themes)];
                   by = theme -> string(nameof(get_theme_type(theme))))
    editor = Any[theme for T in _EDITOR_THEME_TYPES for theme in themes if get_theme_type(theme) === T]
    others = filter(theme -> !(get_theme_type(theme) in _EDITOR_THEME_TYPES), themes)
    is_tool = theme -> Base.moduleroot(parentmodule(get_theme_type(theme))) ===
                       Base.moduleroot(@__MODULE__)
    (("Editor", editor), ("Tools", filter(is_tool, others)), ("Documents", filter(!is_tool, others)))
end

# The title of the card of the theme type `T`: the words of its name without
# `Theme`, so `GestureHelpTheme` is "Gesture help".
function _get_section_title(T::Type)
    words = [m.match for m in eachmatch(r"[A-Z][a-z0-9]*|[a-z0-9]+", replace(string(nameof(T)), r"Theme$" => ""))]
    uppercasefirst(lowercase(join(words, " ")))
end

# The card of `theme`: its title and the summary of its type, and its presets and
# for each field a row and the docstring of the field under it, which show while
# the `open_sections` of the appearance name the type of the theme.
# `controls` makes the controls of the tab and holds its widget theme.
function _make_theme_section(controls, theme)
    T = get_theme_type(theme)
    name = string(nameof(T))
    parts = Any[]
    presets = get_theme_presets(T)
    isempty(presets) || push!(parts, controls.choice(first.(presets), index -> begin
        preset = last(presets[index])()
        CompoundOperation(Any[_write_theme_field(theme, field, getproperty(preset, field))
                              for field in get_theme_field_names(T)])
    end))
    caption = StyleText(controls.theme.font_small, controls.theme.muted_foreground)
    cells = Any[]
    # The gap above each row of the grid: a field is a section gap from the field
    # above, and its docstring follows its row with no gap, as a part of it.
    row_gaps = Any[]
    for field in get_theme_field_names(T)
        push!(cells, WidgetLabel(replace(String(field), "_" => " ")),
              _make_field_control(controls, theme, field, getproperty(theme, field)))
        push!(row_gaps, nothing)
        text = something(find_theme_field_text(T, field), "")
        if !isempty(text)
            push!(cells, LayoutConstraint(WidgetLabel(strip_code_marks(text); text_style = caption);
                                          column_span = 2))
            push!(row_gaps, 0)
        end
    end
    push!(parts, GridLayout(cells, 2; horizontal_gap = controls.theme.label_gap,
                            vertical_gap = controls.theme.section_gap, vertical_align = :center,
                            row_gaps))
    appearance = controls.appearance
    summary = strip_code_marks(compute_docstring_summary(T))
    card = WidgetCard(; title = WidgetLabel(_get_section_title(T)),
                      description = isempty(summary) ? nothing : summary,
                      content = VerticalLayout(parts; gap = controls.theme.item_gap),
                      collapsible = true, collapsed = !(name in appearance.open_sections))
    set_cell_computation!(getfield(card, :collapsed), () -> !(name in appearance.open_sections))
    controls.folds[card] = name
    card
end

# The write that opens the section of the theme type named `name` in the tab, or
# closes it when it is open. It is view state, so the history does not record it.
function _make_fold_operation(appearance::Appearance, name::String)
    open = appearance.open_sections
    toggled = name in open ? filter(!=(name), open) : vcat(open, name)
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(appearance, "open_sections", toggled))
end

# The control of the field `field` of `theme`, which holds `value`.
function _make_field_control(controls, theme, field::Symbol, value::ThemeLength)
    kind = Base.typename(typeof(value)).wrapper
    parts = Any[]
    for (part, name) in _get_length_parts(value.value)
        isempty(name) || push!(parts, WidgetLabel(name))
        push!(parts, controls.spin_box(_get_length_part(value.value, part),
                                       v -> _write_theme_field(theme, field,
                                                kind(_replace_length_part(getproperty(theme, field).value, part, v)))))
    end
    HorizontalLayout(parts; gap = controls.theme.label_gap, vertical_align = :center)
end

_make_field_control(controls, theme, field::Symbol, value::StyleFont) =
    _make_font_control(controls, () -> getproperty(theme, field),
                       font -> _write_theme_field(theme, field, font))

_make_field_control(controls, theme, field::Symbol, value::ThemeColor) =
    _make_theme_color_control(controls, () -> getproperty(theme, field),
                              color -> _write_theme_field(theme, field, color),
                              _get_default_field(controls, theme, field))

# A text style has the controls of its colour over those of its font. Each writes
# a new style with the other part as it is.
function _make_field_control(controls, theme, field::Symbol, value::StyleText)
    read = () -> getproperty(theme, field)
    VerticalLayout(Any[
        _make_color_control(controls, () -> read().color,
                            color -> _write_theme_field(theme, field, StyleText(read().font, color))),
        _make_font_control(controls, () -> read().font,
                           font -> _write_theme_field(theme, field, StyleText(font, read().color))),
    ]; gap = controls.theme.item_gap)
end

_make_field_control(controls, theme, field::Symbol, value::FontRole) =
    _make_role_control(controls, theme, () -> getproperty(theme, field),
                       role -> _write_theme_field(theme, field, role))

# A text role has the controls of its colour over those of its font role.
function _make_field_control(controls, theme, field::Symbol, value::TextRole)
    read = () -> getproperty(theme, field)
    default = _get_default_field(controls, theme, field)
    VerticalLayout(Any[
        _make_theme_color_control(controls, () -> read().color,
                                  color -> _write_theme_field(theme, field, TextRole(read().font, color)),
                                  default isa TextRole ? default.color : nothing),
        _make_role_control(controls, theme, () -> read().font,
                           role -> _write_theme_field(theme, field, TextRole(role, read().color))),
    ]; gap = controls.theme.item_gap)
end

# A multiple of the natural line height has a spin box in percent.
_make_field_control(controls, theme, field::Symbol, value::MultipleSpacing) =
    HorizontalLayout(Any[controls.spin_box(round(Int, value.factor * 100),
                                           v -> _write_theme_field(theme, field, MultipleSpacing(v / 100));
                                           min = 50, max = 400),
                         WidgetLabel("% of the natural line height")];
                     gap = controls.theme.label_gap, vertical_align = :center)

_make_field_control(controls, theme, field::Symbol, value) = WidgetLabel(string(value))

# `role` with its weight, its slant or its relative size replaced.
_with_font_role(role::FontRole; weight = role.weight, italic = role.italic,
                relative_size = role.relative_size) =
    FontRole(; base = role.base, family = role.family, weight, italic, relative_size)

# The controls of the font role that `read()` answers, in one row: its family when
# it sets one, the steps through the weights of the family of the font that it
# gives, a checkbox for italic, and its size in percent of its base font. A step or
# a check sets the weight or the slant of the role, which then no longer follows
# the base in it. `write(role)` is the operation that sets a new role.
function _make_role_control(controls, theme, read, write)
    role = read()
    font = apply_font_role(role, get_role_base(role, theme))
    parts = Any[]
    role.family === nothing || push!(parts, WidgetLabel(role.family))
    append!(parts, Any[
        controls.button("−", write(_with_font_role(role; weight = _step_font_weight(font, -1).weight))),
        WidgetLabel(_get_font_weight_name(font.weight)),
        controls.button("+", write(_with_font_role(role; weight = _step_font_weight(font, 1).weight))),
        controls.checkbox(font.italic, v -> write(_with_font_role(read(); italic = v)); label = "italic"),
        controls.spin_box(round(Int, role.relative_size * 100),
                          v -> write(_with_font_role(read(); relative_size = v / 100)); min = 25, max = 400),
        WidgetLabel("% of " * replace(String(role.base), "_" => " ")),
    ])
    HorizontalLayout(parts; gap = controls.theme.label_gap, vertical_align = :center)
end

# The controls of the font that `read()` answers. The first row steps through the
# families and names the family of the font. The second row steps through the
# weights of the family and names the weight, then a checkbox chooses italic and a
# spin box the size. `write(font)` is the operation that sets a new font.
function _make_font_control(controls, read, write)
    font = read()
    gap = controls.theme.label_gap
    VerticalLayout(Any[
        HorizontalLayout(Any[
            controls.button("‹", write(_step_font_family(font, -1))),
            WidgetLabel(font.family),
            controls.button("›", write(_step_font_family(font, 1))),
        ]; gap, vertical_align = :center),
        HorizontalLayout(Any[
            controls.button("−", write(_step_font_weight(font, -1))),
            WidgetLabel(_get_font_weight_name(font.weight)),
            controls.button("+", write(_step_font_weight(font, 1))),
            controls.checkbox(font.italic, v -> write(_with_font_italic(read(), v)); label = "italic"),
            controls.spin_box(font.size, v -> write(with_font_size(read(), v)); min = 6, max = 96),
        ]; gap, vertical_align = :center),
    ]; gap)
end

# The controls of the colour that `read()` answers: its swatch and its text.
# `write(color)` is the operation that sets a new colour.
function _make_color_control(controls, read, write)
    HorizontalLayout(Any[WidgetSwatch(read()), controls.color_text(read, write)];
                     gap = controls.theme.label_gap, vertical_align = :center)
end

# The value of the field `field` in the default theme of `theme`: the colour theme
# of the same mode and contrast for a colour theme of the appearance, and the
# default theme of its type for any other. Each default theme is made once in a
# print.
function _get_default_field(controls, theme, field::Symbol)
    default = get!(controls.defaults, theme) do
        variant = findfirst(held -> held === theme, controls.appearance.color_themes)
        variant === nothing ? get_theme_type(theme)() : make_color_theme(variant)
    end
    getproperty(default, field)
end

# The controls of the colour of a theme that `read()` answers, by its kind, and a
# button "Reset" that writes `default` when the colour differs from it.
# `write(color)` is the operation that sets a new colour.
function _make_theme_color_control(controls, read, write, default)
    color = read()
    swatch = WidgetSwatch(resolve_theme_color(color, controls.appearance))
    parts = Any[swatch]
    if color isa StyleColor
        push!(parts, controls.color_text(read, write))
    elseif color isa ColorRole
        append!(parts, Any[controls.button("‹", write(_step_color_role(color, -1))),
                           WidgetLabel(format_theme_color(color)),
                           controls.button("›", write(_step_color_role(color, 1)))])
    else
        append!(parts, Any[controls.button("‹", write(_step_palette_hue(color, -1))),
                           WidgetLabel(String(color.hue)),
                           controls.button("›", write(_step_palette_hue(color, 1))),
                           controls.button("−", write(_step_palette_step(color, -1))),
                           WidgetLabel(string(color.step)),
                           controls.button("+", write(_step_palette_step(color, 1)))])
    end
    color isa StyleColor ||
        push!(parts, controls.button("Fix", write(resolve_theme_color(color, controls.appearance))))
    default === nothing || color == default || push!(parts, controls.button("Reset", write(default)))
    HorizontalLayout(parts; gap = controls.theme.label_gap, vertical_align = :center)
end

# The role `delta` roles away from `role` in the order of the colour theme.
function _step_color_role(role::ColorRole, delta::Integer)
    names = get_theme_field_names(ColorTheme)
    i = something(findfirst(==(role.role), names), 1)
    ColorRole(names[mod1(i + delta, length(names))]; alpha = role.alpha)
end

# The hues that a step of a ramp steps through: the hues of every palette and the
# accent.
const _STEP_HUES = (PALETTE_HUES..., :accent)

# `color` at the hue `delta` hues away, or at the step `delta` steps away, from 1
# to 12.
function _step_palette_hue(color::PaletteColor, delta::Integer)
    i = something(findfirst(==(color.hue), _STEP_HUES), 1)
    PaletteColor(_STEP_HUES[mod1(i + delta, length(_STEP_HUES))], color.step; alpha = color.alpha,
                 minimum_contrast = color.minimum_contrast, against = color.against)
end
_step_palette_step(color::PaletteColor, delta::Integer) =
    PaletteColor(color.hue, clamp(color.step + delta, 1, 12); alpha = color.alpha,
                 minimum_contrast = color.minimum_contrast, against = color.against)

# ── The colour settings ─────────────────────────────────────────────────────

# The rows of the colour settings, in order: the field of the appearance and its
# name, and the value of each in a new appearance.
const _COLOR_SETTING_ROWS = ((:color_mode, "Mode"), (:color_contrast, "Contrast"),
                             (:color_palette, "Palette"), (:color_accent, "Accent"),
                             (:color_neutral, "Neutral"))
const _COLOR_SETTING_DEFAULTS = (color_mode = :light, color_contrast = :normal,
                                 color_palette = DEFAULT_PALETTE_NAME, color_accent = :blue,
                                 color_neutral = :slate)

# A write of the colour setting `field` of `appearance`. It changes the look, so
# the `appearance` wrapper prints the view again, and a history records it.
_write_color_setting(appearance::Appearance, field::Symbol, value) =
    ReplaceReferencedValueOperation(appearance, String(field), value)

# The values that the colour setting `field` of `appearance` steps through.
function _get_color_setting_values(appearance::Appearance, field::Symbol)
    field === :color_mode && return collect(COLOR_MODES)
    field === :color_contrast && return collect(COLOR_CONTRASTS)
    field === :color_palette && return get_palette_names()
    field === :color_accent && return [hue for hue in PALETTE_HUES if hue !== :neutral]
    palette = something(find_palette(appearance.color_palette), find_palette(DEFAULT_PALETTE_NAME))
    copy(get_palette_neutrals(palette))
end

# The value `delta` values away from the colour setting `field` of `appearance`.
function _step_color_setting(appearance::Appearance, field::Symbol, delta::Integer)
    values = _get_color_setting_values(appearance, field)
    i = something(findfirst(==(getproperty(appearance, field)), values), 1)
    values[mod1(i + delta, length(values))]
end

# The rows of the colour settings: for each, its name, the buttons that step it,
# its value, and for the accent and the neutral a swatch of the solid step.
function _make_color_settings(controls)
    appearance = controls.appearance
    cells = Any[]
    for (field, name) in _COLOR_SETTING_ROWS
        swatch = field === :color_accent ? PaletteColor(:accent, 9) :
                 field === :color_neutral ? PaletteColor(:neutral, 9) : nothing
        push!(cells, WidgetLabel(name),
              controls.button("‹", _write_color_setting(appearance, field,
                                                        _step_color_setting(appearance, field, -1))),
              WidgetLabel(string(getproperty(appearance, field))),
              controls.button("›", _write_color_setting(appearance, field,
                                                        _step_color_setting(appearance, field, 1))),
              swatch === nothing ? WidgetLabel("") :
                                   WidgetSwatch(resolve_theme_color(swatch, appearance)))
    end
    GridLayout(cells, 5; horizontal_gap = controls.theme.label_gap,
               vertical_gap = controls.theme.item_gap, vertical_align = :center)
end

# A text that a colour text takes as typed: hex digits and `#`.
_is_color_input(text::AbstractString) = all(c -> isxdigit(c) || c == '#', text)

# The write of the colour that the text of the colour that `read()` answers names
# after the edit that puts `replacement` between `start` and `stop`, and the place
# of the caret after the edit; or `nothing` when that text names no colour.
# `write(color)` is the write. One character typed with no range replaces the digit
# after the caret, so the text keeps its nine characters.
function _compute_color_edit(read, write, start::Integer, stop::Integer,
                             replacement::AbstractString)
    text = format_style_color(read())
    color = convert_text_to_style_color(splice_string(text, start, stop, replacement))
    color === nothing ||
        return (write(color), min(start + length(replacement), length(text)))
    (start == stop && 1 <= start < length(text) && length(replacement) == 1) || return nothing
    color = convert_text_to_style_color(splice_string(text, start, start + 1, replacement))
    color === nothing ? nothing : (write(color), start + 1)
end

# ── The paths of the tab ──────────────────────────────────────────────────────

# The selection and the part under the pointer of `pane` are the paths in the
# widget tree that `appearance` holds through `p`, and each document below the
# pane holds the part of its parent's path below it. So a layout sends a key to
# the colour text that holds the caret, and the text draws the caret.
function _follow_tab_paths!(p::AppearanceToWidget, appearance::Appearance, pane)
    set_cell_computation!(getfield(pane, :selection),
                          () -> map_selection_forward(appearance, path -> _get_tab_path(p, path)))
    hasfield(typeof(pane), :mouse_target) &&
        set_cell_computation!(getfield(pane, :mouse_target),
                              () -> map_mouse_target_forward(appearance, path -> _get_tab_path(p, path)))
    set_output_tree_path_computations!(pane)
end

# The path in the widget tree that `reference`, a path of the appearance, names:
# the path that a step of `p` holds. Any other path names no widget.
function _get_tab_path(p::AppearanceToWidget, reference)
    reference isa ConcreteReference || return nothing
    step = reference.head
    (step isa ProjectionReferenceStep && step.projection === p) ? step.output_path : nothing
end

# The path that the appearance holds for `path`, a path in the widget tree from the
# pane: a step of this projection around it, typed in the tree. The pane whole is
# the appearance whole.
function _introduce_tab_path(iomap::AppearanceToWidgetIoMap, path::Reference)
    path isa EmptyReference && return EmptyReference(get_reference_node_type(iomap.input))
    pane = iomap.child_iomap.input
    typed = is_fully_typed_reference(path) ? path : annotate_reference_types(pane, path)
    make_introduced_reference(iomap.projection, iomap.input, typed)
end

# The scaled widget theme of `appearance` for the gaps of the tab: the one that it
# holds, or the default theme at its scales. A print writes nothing into the
# appearance.
function _get_widget_theme(appearance::Appearance)
    entry = get(appearance.themes, WidgetTheme, nothing)
    entry === nothing ? make_scaled_theme(WidgetTheme(), appearance) : entry.scaled
end

# The pane reads each input. A press of a button of the tab answers the operation
# of the button, a step of a spin box or a choice of a preset answers the write of
# the theme, an edit of a colour text answers the write of the colour or nothing,
# and a path of the tree becomes the path that the appearance holds; every other
# answer passes on.
function read_intent(p::AppearanceToWidget, recursion, change::Intent, iomap::AppearanceToWidgetIoMap)
    answer = read_intent(p.scroll_pane, recursion, change, iomap.child_iomap)
    operation = answer isa Intent ? answer.operation : answer
    Intent(change.gesture, _translate_tab_operation(iomap, operation))
end

read_intent(p::AppearanceToWidget, iomap::AppearanceToWidgetIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

_translate_tab_operation(iomap, operation::InvokeActionOperation) =
    get(iomap.commands, operation.action, operation)
function _translate_tab_operation(iomap, operation::ReplaceReferencedValueOperation)
    write = get(iomap.writes, operation.document, nothing)
    write === nothing ? operation : write(operation.value)
end
function _translate_tab_operation(iomap, operation::ReplaceStringRangeOperation)
    found = _find_color_edit(iomap, operation.reference)
    found === nothing && return operation
    edit, range = found
    answer = edit(range.start, range.stop, operation.replacement)
    answer === nothing && return nothing
    write, caret = answer
    path = _place_caret(strip_reference_types(operation.reference), caret)
    CompoundOperation(Any[write, ReplaceSelectionOperation(_introduce_tab_path(iomap, path))])
end
function _translate_tab_operation(iomap, operation::ToggleCollapseOperation)
    name = get(iomap.folds, operation.target, nothing)
    name === nothing ? operation : _make_fold_operation(iomap.input, name)
end
_translate_tab_operation(iomap, operation::ReplacePathOperation) =
    make_path_operation(operation, _introduce_tab_path(iomap, get_operation_path(operation)))
# An edit that names no colour declines the whole answer that holds it.
function _translate_tab_operation(iomap, operation::CompoundOperation)
    members = Any[_translate_tab_operation(iomap, member) for member in operation.operations]
    any(isnothing, members) ? nothing : CompoundOperation(members)
end
function _translate_tab_operation(iomap, operation::WrappingOperation)
    inner = _translate_tab_operation(iomap, get_wrapped_operation(operation))
    inner === nothing ? nothing : rewrap_operation(operation, inner)
end
_translate_tab_operation(iomap, operation) = operation

# The edit function of the colour text that `reference`, a path from the pane, goes
# through, and the last range of the path, which holds the characters that the
# edit replaces; or `nothing` for a path through no colour text.
function _find_color_edit(iomap, reference)
    node = iomap.child_iomap.input
    rest = reference
    while rest isa ConcreteReference
        edit = get(iomap.edits, node, nothing)
        if edit !== nothing
            range = _find_last_range_step(rest)
            return range === nothing ? nothing : (edit, range)
        end
        node = unwrap_cell(evaluate_reference_step(rest.head, node))
        rest = rest.tail
    end
    nothing
end

# `reference` with its last step, the range of the text, made a caret at `offset`.
function _place_caret(reference, offset::Integer)
    reference isa ConcreteReference || return reference
    reference.tail isa ConcreteReference || return ConcreteReference(PositionReferenceStep(offset), EmptyReference())
    ConcreteReference(reference.head, _place_caret(reference.tail, offset))
end

function _find_last_range_step(reference)
    found = nothing
    while reference isa ConcreteReference
        reference.head isa ARangeReferenceStep && (found = reference.head)
        reference = reference.tail
    end
    found
end

# A path of the appearance through this projection names its path in the widget
# tree, and the drawing maps it on; a widget of the tab maps back to that path.
function map_reference_forward(p::AppearanceToWidget, iomap::AppearanceToWidgetIoMap, reference)
    reference isa EmptyReference && return EmptyReference(get_reference_node_type(iomap.output))
    inner = _get_tab_path(p, reference)
    inner === nothing ? nothing : map_reference_forward(p.scroll_pane, iomap.child_iomap, inner)
end

function map_reference_backward(p::AppearanceToWidget, iomap::AppearanceToWidgetIoMap, reference)
    inner = map_reference_backward(p.scroll_pane, iomap.child_iomap, reference)
    inner isa Reference ? _introduce_tab_path(iomap, inner) : nothing
end
