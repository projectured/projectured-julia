# Fragment of `AppearanceModule` — the appearance tab: an `Appearance` shown as
# widgets that step its zoom and its scales.

"""
    AppearanceToWidget(; scroll_pane)

Show an `Appearance` as widgets, in a pane that scrolls:

- a row for the zoom and one for each of the six scales, each with its name, a
  − button, its value in percent, a + button and a reset button, and under the
  rows the buttons "Reset all", "Save" and "Load", which save the appearance in
  the file of `get_appearance_file` and read it back;
- a section for each theme of the appearance: its presets, as a choice that
  writes every field of the preset into the theme, and a row for each field. A
  size has a spin box for each of its parts, a font has buttons that step through
  the font files and a spin box for its size, and a color shows its swatch and
  its value.

A press of a button answers the operation of the button, and a step of a spin box
or a choice of a preset answers a write of the theme, so the `appearance` wrapper
of the editor prints the view again, with this tab. Every write is view state: a
change of the appearance is no edit of a document, and the history does not take
it back. The gaps of the tab are those of the widget theme of the appearance, so
they follow its spacing scale. `scroll_pane` is the printer of a `WidgetScrollPane`
with the widget theme of the editor, which draws the pane and, through the
recursion, the widgets in it.
"""
struct AppearanceToWidget <: Projection
    scroll_pane::Any        # the printer of the pane, with the widget theme of the editor
end

AppearanceToWidget(; scroll_pane) = AppearanceToWidget(scroll_pane)

# `commands` holds the operation of each button of the print, by the `Action` of
# the button: a press answers `InvokeActionOperation` with that `Action`. `writes`
# holds, for each spin box and each choice, the function from the value that it
# writes to the operation that the tab answers.
@iomap struct AppearanceToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
    commands::Any
    writes::Any
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

# A color as `#rrggbbaa`.
_get_color_text(color::StyleColor) =
    "#" * join(string(round(Int, clamp(c, 0, 1) * 255); base = 16, pad = 2)
               for c in (color.red, color.green, color.blue, color.alpha))

# A write of the field `field` of `theme`. It is view state, so the history does
# not record it.
_write_theme_field(theme, field::Symbol, value) =
    ReplaceViewStateOperation(ReplaceReferencedValueOperation(theme, String(field), value))

# The font files that a font of a theme can take, in the order of their names:
# the files of the font folder, without the icon font and the emoji font.
_get_theme_font_files() =
    sort!([f for f in readdir(_FONT_DIR) if endswith(f, ".ttf") &&
           !(f in ("lucide.ttf", "NotoEmoji-Regular.ttf"))])

# The font `delta` files away from `font` in the list of the font files, at the
# size of `font`.
function _step_font_file(font::StyleFont, delta::Integer)
    files = _get_theme_font_files()
    i = something(findfirst(==(basename(font.filename)), files), 1)
    StyleFont(joinpath(_FONT_DIR, files[mod1(i + delta, length(files))]), font.size)
end

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
    theme = _get_widget_theme(appearance)
    cells = Any[]
    for (field, name) in _APPEARANCE_ROWS
        push!(cells, WidgetLabel(name),
              button("−", _make_step_operation(appearance, field, -1)),
              WidgetLabel(_get_percent_text(getproperty(appearance, field))),
              button("+", _make_step_operation(appearance, field, 1)),
              button("Reset", _make_step_operation(appearance, field, 0)))
    end
    reset_all = CompoundOperation(Any[_make_step_operation(appearance, field, 0)
                                      for (field, _) in _APPEARANCE_ROWS])
    parts = Any[GridLayout(cells, 5; horizontal_gap = theme.label_gap, vertical_gap = theme.item_gap,
                           vertical_align = :center),
                HorizontalLayout(Any[button("Reset all", reset_all),
                                     button("Save", SaveAppearanceOperation(appearance)),
                                     button("Load", LoadAppearanceOperation(appearance))];
                                 gap = theme.label_gap)]
    for entry in sort!(collect(values(appearance.themes)); by = e -> string(get_theme_type(e.theme)))
        push!(parts, _make_theme_section(entry.theme, theme, button, spin_box, writes))
    end
    content = VerticalLayout(parts; gap = theme.section_gap)
    pane = WidgetScrollPane(content)
    child = print_document(p.scroll_pane, recursion, pane, ctx)
    AppearanceToWidgetIoMap(p, appearance, child.output, child, commands, writes)
end

# The section of `theme`: its name, its presets, and a row for each field.
function _make_theme_section(theme, widget_theme, button, spin_box, writes)
    T = get_theme_type(theme)
    parts = Any[WidgetLabel(string(nameof(T)))]
    presets = get_theme_presets(T)
    if !isempty(presets)
        choice = WidgetRadioGroup(first.(presets); selected = 0)
        writes[choice] = index -> begin
            preset = last(presets[index])()
            CompoundOperation(Any[_write_theme_field(theme, field, getproperty(preset, field))
                                  for field in get_theme_field_names(T)])
        end
        push!(parts, choice)
    end
    cells = Any[]
    for field in get_theme_field_names(T)
        value = getproperty(theme, field)
        push!(cells, WidgetLabel(replace(String(field), "_" => " ")),
              _make_field_control(theme, field, value, button, spin_box, widget_theme))
    end
    push!(parts, GridLayout(cells, 2; horizontal_gap = widget_theme.label_gap,
                            vertical_gap = widget_theme.item_gap, vertical_align = :center))
    VerticalLayout(parts; gap = widget_theme.item_gap)
end

# The control of one field of a theme.
function _make_field_control(theme, field::Symbol, value::ThemeLength, button, spin_box, widget_theme)
    kind = Base.typename(typeof(value)).wrapper
    controls = Any[]
    for (part, name) in _get_length_parts(value.value)
        isempty(name) || push!(controls, WidgetLabel(name))
        push!(controls, spin_box(_get_length_part(value.value, part),
                                 v -> _write_theme_field(theme, field,
                                          kind(_replace_length_part(getproperty(theme, field).value, part, v)))))
    end
    HorizontalLayout(controls; gap = widget_theme.label_gap)
end

function _make_field_control(theme, field::Symbol, value::StyleFont, button, spin_box, widget_theme)
    HorizontalLayout(Any[
        button("‹", _write_theme_field(theme, field, _step_font_file(value, -1))),
        WidgetLabel(splitext(basename(value.filename))[1]),
        button("›", _write_theme_field(theme, field, _step_font_file(value, 1))),
        spin_box(value.size, v -> _write_theme_field(theme, field,
                                                     StyleFont(getproperty(theme, field).filename, v));
                 min = 6, max = 96),
    ]; gap = widget_theme.label_gap)
end

function _make_field_control(theme, field::Symbol, value::StyleColor, button, spin_box, widget_theme)
    HorizontalLayout(Any[WidgetLabel("■"; style = WidgetStyle(label_text_color = value)),
                         WidgetLabel(_get_color_text(value))]; gap = widget_theme.label_gap)
end

_make_field_control(theme, field::Symbol, value, button, spin_box, widget_theme) =
    WidgetLabel(string(value))

# The scaled widget theme of `appearance` for the gaps of the tab: the one that it
# holds, or the default theme at its scales. A print writes nothing into the
# appearance.
function _get_widget_theme(appearance::Appearance)
    entry = get(appearance.themes, WidgetTheme, nothing)
    entry === nothing ? make_scaled_theme(WidgetTheme(), appearance) : entry.scaled
end

# The pane reads each input. A press of a button of the tab answers the operation
# of the button, and a step of a spin box or a choice of a preset answers the
# write of the theme; every other answer passes on.
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
_translate_tab_operation(iomap, operation::CompoundOperation) =
    CompoundOperation(Any[_translate_tab_operation(iomap, member) for member in operation.operations])
_translate_tab_operation(iomap, operation::WrappingOperation) =
    rewrap_operation(operation, _translate_tab_operation(iomap, get_wrapped_operation(operation)))
_translate_tab_operation(iomap, operation) = operation

# A reference of the appearance names no widget of the tab, and a widget of the
# tab names no place of the appearance.
map_reference_forward(::AppearanceToWidget, ::AppearanceToWidgetIoMap, reference) = nothing
map_reference_backward(::AppearanceToWidget, ::AppearanceToWidgetIoMap, reference) = nothing
