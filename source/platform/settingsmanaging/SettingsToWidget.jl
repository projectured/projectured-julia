# Fragment of `SettingsManagingModule` — the settings of an editor as widgets: the
# view of the settings tab.

"""
    SettingsToWidget()

The settings tab: the `Settings` of an editor as widgets, in a pane that scrolls.
One card for each group, in the order of their names, with one row for each
setting: its label, whose tooltip says what it does, its control, and a button
that resets it. Under the cards, a button resets all of them, and two buttons save
the settings to their file and load them from it; these two are off for settings
with no file.

- A `Bool` is a switch, a number is a spin box with the step of its values, a
  `Symbol` is a choice of its values, and a `String` is a text.
- A group that no target of the editor applies, such as the render settings of a
  backend that draws no windows, says so on its card, and its controls are off.
- Each control shows the value of its setting and follows a change of it.
- A group that the application reads when it starts says so on its card.
- The selection of the settings holds a path in the widgets of the tab, as a path
  that this projection introduces, so a key reaches the control that the path
  names and a text draws its caret.
- The pane keeps its own place. A change of a setting does not print the tab
  again, because each control follows its setting, so the place stays. A change
  of "Catch faults" prints the whole view again, and the new pane starts at the
  top.

The view holds no effect of a setting. A control edit and a reset become the
normal edit of a group, a `ReplaceReferencedValueOperation` of one setting, and
the `settings` wrapper turns it into an applied setting.
"""
struct SettingsToWidget <: Projection end

# `controls` holds `(control, group, name, convert)` for each control of a setting,
# so the reader turns the write of a control into the write of its setting:
# `convert` makes the value of the setting from the value that the control writes.
@iomap struct SettingsToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    controls::Vector{Tuple{Any,Any,Symbol,Any}}
end

const _GROUP_GAP = 12
const _ROW_GAP = 6
const _COLUMN_GAP = 12

# ── Printer ───────────────────────────────────────────────────────────────

function print_document(p::SettingsToWidget, recursion, settings::Settings, ctx)
    controls = Tuple{Any,Any,Symbol,Any}[]
    groups = get_settings_groups(settings)
    cards = Any[_make_group_card(settings, group, controls) for group in groups]
    reset = _make_command_button("Reset all", "Give every setting its default.",
                               () -> _make_reset_operation(groups))
    save = _make_command_button("Save", "Write the settings to their file.",
                              () -> SaveSettingsOperation(settings, settings.file))
    load = _make_command_button("Load", "Read the settings from their file.",
                              () -> LoadSettingsOperation(settings, settings.file))
    for button in (save, load)
        set_cell_computation!(getfield(button, :enabled), () -> !isempty(settings.file))
    end
    buttons = HorizontalLayout(Any[reset, save, load]; gap = _COLUMN_GAP)
    output = WidgetScrollPane(VerticalLayout(Any[cards..., buttons]; gap = _GROUP_GAP))
    # Each kind of path of the settings names a part of the tab: the output holds
    # its image, and each document below it the part of its parent's path.
    set_output_path_computations!(output, settings, path -> find_introduced_path(p, path))
    set_output_tree_path_computations!(output)
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
        control, convert = _make_setting_control(group, description, is_used)
        push!(controls, (control, group, description.name, convert))
        push!(cells, WidgetLabel(description.label; tooltip = description.text))
        push!(cells, control)
        reset = _make_command_button("Reset", "Give \"$(description.label)\" its default.",
                                   () -> _make_reset_operation(group, description))
        set_cell_computation!(getfield(reset, :enabled), is_used)
        push!(cells, reset)
    end
    grid = GridLayout(cells, 3; horizontal_gap = _COLUMN_GAP, vertical_gap = _ROW_GAP,
                      vertical_align = :center)
    card = WidgetCard(; title = WidgetLabel(_make_group_title(T)),
                      content = WidgetComposite(Any[grid]))
    note = is_settings_group_read_at_start(T) ?
        "These settings take effect at the next start." :
        "This editor does not use these settings."
    set_cell_computation!(getfield(card, :description),
                          () -> (is_used() && !is_settings_group_read_at_start(T)) ? nothing : note)
    card
end

_make_group_title(T::Type) = uppercasefirst(replace(get_settings_name(T), "_" => " "))

# The control of one setting, and the function from the value that it writes to
# the value of the setting. Its value is a computed cell over the setting, so it
# follows a change from any path: the tab, a command, an undo, a load. It is on
# while `is_used()` answers true.
function _make_setting_control(group, description::SettingDescription, is_used)
    name = description.name
    values = description.values
    current = () -> getproperty(group, name)
    if description.type === Bool
        control = WidgetSwitch(; checked = current())
        set_cell_computation!(getfield(control, :checked), current)
        convert = identity
    elseif description.type in (Int, Float64) && values isa AbstractRange
        control = WidgetSpinBox(current(); min = first(values), max = last(values),
                                step = step(values))
        set_cell_computation!(getfield(control, :value), current)
        convert = identity
    elseif description.type === Symbol && values isa Tuple
        choices = collect(values)
        control = WidgetRadioGroup(String.(choices);
                                   selected = something(findfirst(==(current()), choices), 0))
        set_cell_computation!(getfield(control, :selected),
                              () -> something(findfirst(==(current()), choices), 0))
        convert = index -> choices[index]
    else
        control = WidgetText(string(current()))
        set_cell_computation!(getfield(control, :content), () -> string(current()))
        convert = identity
    end
    set_cell_computation!(getfield(control, :enabled), is_used)
    control, convert
end

# A button whose click makes the operation of `make`, and says `tooltip`.
_make_command_button(text::AbstractString, tooltip::AbstractString, make) =
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

_make_setting_write(group, name::Symbol, value) =
    ReplaceReferencedValueOperation(group,
        ConcreteReference(FieldReferenceStep(String(name)), EmptyReference()), value)

# The write of a control becomes the write of its setting. Every other operation
# takes the default way back of the kernel: a path in the widgets becomes a path
# that this projection introduces into the settings.
function read_intent(::SettingsToWidget, iomap::SettingsToWidgetIoMap,
                     operation::ReplaceReferencedValueOperation)
    for (control, group, name, convert) in iomap.controls
        operation.document === control || continue
        return _make_setting_write(group, name, convert(operation.value))
    end
    operation
end

# An edit of the text of a setting becomes the write of the whole text, and the
# caret after the characters that it put in.
function read_intent(p::SettingsToWidget, iomap::SettingsToWidgetIoMap,
                     operation::ReplaceStringRangeOperation)
    found = _find_text_edit(iomap, strip_reference_types(operation.reference))
    found === nothing && return invoke(read_intent, Tuple{Projection, Any, Any},
                                       p, iomap, operation)
    (group, name, range) = found
    text = string(getproperty(group, name))
    write = _make_setting_write(group, name,
                                splice_string(text, range.start, range.stop,
                                              operation.replacement))
    caret = _place_caret(strip_reference_types(operation.reference),
                         range.start + length(operation.replacement))
    selection = map_reference_backward(p, iomap, caret)
    selection === nothing && return write
    CompoundOperation(Any[write, ReplaceSelectionOperation(selection)])
end

# The setting whose text `reference`, a path from the output, goes through, and the
# last range of the path, which holds the characters that the edit replaces; or
# `nothing` for a path through no text of a setting.
function _find_text_edit(iomap::SettingsToWidgetIoMap, reference)
    texts = IdDict{Any,Any}(control => (group, name)
                            for (control, group, name, _) in iomap.controls
                            if control isa WidgetText)
    node = iomap.output
    rest = reference
    while rest isa ConcreteReference
        found = get(texts, node, nothing)
        if found !== nothing
            range = _find_last_range_step(rest)
            return range === nothing ? nothing : (found..., range)
        end
        node = unwrap_cell(evaluate_reference_step(rest.head, node))
        rest = rest.tail
    end
    nothing
end

function _find_last_range_step(reference)
    found = nothing
    while reference isa ConcreteReference
        reference.head isa ARangeReferenceStep && (found = reference.head)
        reference = reference.tail
    end
    found
end

# `reference` with its last step, the range of the text, made a caret at `offset`.
function _place_caret(reference, offset::Integer)
    reference isa ConcreteReference || return reference
    reference.tail isa ConcreteReference ||
        return ConcreteReference(PositionReferenceStep(offset), EmptyReference())
    ConcreteReference(reference.head, _place_caret(reference.tail, offset))
end

# ── Reference mapping ─────────────────────────────────────────────────────
# A path of the settings through this projection names a path in the widgets of
# the tab, and a widget of the tab maps back to such a path.

map_reference_forward(p::SettingsToWidget, ::SettingsToWidgetIoMap, reference) =
    find_introduced_path(p, reference)
