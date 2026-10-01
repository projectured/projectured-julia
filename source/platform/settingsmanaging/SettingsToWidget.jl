# Fragment of `SettingsManagingModule` — the settings of an editor as widgets: the
# view of the settings tab.

"""
    SettingsToWidget()

The settings tab: the `Settings` of an editor as widgets. One card for each group,
in the order of their names, with one row for each setting: its label, whose
tooltip says what it does, its control, and a button that resets it. Under the
cards, a button resets all of them.

- A `Bool` is a switch, and a number is a spin box with the step of its values.
  Another type shows its value as text.
- A group that no target of the editor applies, such as the render settings of a
  backend that draws no windows, says so on its card, and its controls are off.
- Each control shows the value of its setting and follows a change of it.

The view holds no effect of a setting. A control edit and a reset become the
normal edit of a group, a `ReplaceReferencedValueOperation` of one setting, and
the `settings` wrapper turns it into an applied setting.
"""
struct SettingsToWidget <: Projection end

# `controls` holds `(control, group, name)` for each control of a setting, so the
# reader turns the write of a control into the write of its setting.
@iomap struct SettingsToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    controls::Vector{Tuple{Any,Any,Symbol}}
end

const _GROUP_GAP = 12
const _ROW_GAP = 6
const _COLUMN_GAP = 12

# ── Printer ───────────────────────────────────────────────────────────────

function print_document(p::SettingsToWidget, recursion, settings::Settings, ctx)
    controls = Tuple{Any,Any,Symbol}[]
    groups = get_settings_groups(settings)
    cards = Any[_make_group_card(settings, group, controls) for group in groups]
    reset = _make_reset_button("Reset all", "Give every setting its default.",
                               () -> _make_reset_operation(groups))
    output = VerticalLayout(Any[cards..., reset]; gap = _GROUP_GAP)
    SettingsToWidgetIoMap(p, settings, output, controls)
end

# A card of one group: its name, a note when the editor does not use it, and a row
# for each setting. The note and the state of the controls follow the unused types
# of the settings, which the start step of the editor finds after the first print.
function _make_group_card(settings::Settings, group, controls)
    T = get_settings_group_type(group)
    is_used = () -> !(T in settings.unused_types)
    cells = Any[]
    for description in get_setting_descriptions(T)
        control = _make_setting_control(group, description, is_used)
        control isa WidgetLabel || push!(controls, (control, group, description.name))
        push!(cells, WidgetLabel(description.label; tooltip = description.text))
        push!(cells, control)
        reset = _make_reset_button("Reset", "Give \"$(description.label)\" its default.",
                                   () -> _make_reset_operation(group, description))
        set_cell_computation!(getfield(reset, :enabled), is_used)
        push!(cells, reset)
    end
    grid = GridLayout(cells, 3; horizontal_gap = _COLUMN_GAP, vertical_gap = _ROW_GAP,
                      vertical_align = :center)
    card = WidgetCard(; title = WidgetLabel(_make_group_title(T)),
                      content = WidgetComposite(Any[grid]))
    note = WidgetLabel("This editor does not use these settings.")
    set_cell_computation!(getfield(card, :description), () -> is_used() ? nothing : note)
    card
end

_make_group_title(T::Type) = uppercasefirst(replace(get_settings_name(T), "_" => " "))

# The control of one setting. Its value is a computed cell over the setting, so it
# follows a change from any path: the tab, a command, an undo, a load. It is on
# while `is_used()` answers true.
function _make_setting_control(group, description::SettingDescription, is_used)
    name = description.name
    if description.type === Bool
        control = WidgetSwitch(; checked = getproperty(group, name))
        set_cell_computation!(getfield(control, :checked), () -> getproperty(group, name))
        set_cell_computation!(getfield(control, :enabled), is_used)
        return control
    end
    values = description.values
    if description.type in (Int, Float64) && values isa AbstractRange
        control = WidgetSpinBox(getproperty(group, name); min = first(values),
                                max = last(values), step = step(values))
        set_cell_computation!(getfield(control, :value), () -> getproperty(group, name))
        set_cell_computation!(getfield(control, :enabled), is_used)
        return control
    end
    label = WidgetLabel(string(getproperty(group, name)))
    set_cell_computation!(getfield(label, :content), () -> string(getproperty(group, name)))
    label
end

# A button whose click makes the operation of `make`, and says `tooltip`.
_make_reset_button(text::AbstractString, tooltip::AbstractString, make) =
    WidgetButton(text; tooltip = tooltip,
                 gestures = GestureBinding[
                     GestureBinding(MouseClickPattern(:left), (_, _) -> make();
                                    description = tooltip, domain = "settings")])

# The write of the default of one setting, and of every setting of `groups`.
_make_reset_operation(group, description::SettingDescription) =
    ReplaceReferencedValueOperation(group,
        ConcreteReference(FieldReferenceStep(String(description.name)), EmptyReference()),
        description.default)

_make_reset_operation(groups::AbstractVector) =
    CompoundOperation(Any[_make_reset_operation(group, description)
                          for group in groups
                          for description in
                              get_setting_descriptions(get_settings_group_type(group))])

# ── Reader ────────────────────────────────────────────────────────────────

# The write of a control becomes the write of its setting. A selection inside the
# controls has no place in the settings, so it ends here, as in `ObjectToWidget`.
function read_intent(::SettingsToWidget, iomap::SettingsToWidgetIoMap,
                     operation::ReplaceReferencedValueOperation)
    for (control, group, name) in iomap.controls
        operation.document === control || continue
        return ReplaceReferencedValueOperation(group,
            ConcreteReference(FieldReferenceStep(String(name)), EmptyReference()),
            operation.value)
    end
    operation
end

read_intent(::SettingsToWidget, ::SettingsToWidgetIoMap, ::ReplacePathOperation) = nothing
read_intent(::SettingsToWidget, ::SettingsToWidgetIoMap, operation) = operation

# ── Reference mapping ─────────────────────────────────────────────────────
# No caret goes into the settings. A point names the control under it by an
# introduced reference, and only such a reference maps forward again.

map_reference_forward(p::SettingsToWidget, ::SettingsToWidgetIoMap, reference) =
    find_introduced_path(p, reference)
