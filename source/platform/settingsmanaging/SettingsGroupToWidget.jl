# Fragment of `SettingsManagingModule` — one settings group as widgets: the page
# of a group, and the body of its card in the settings tab.

"""
    SettingsGroupToWidget(; theme = nothing)

One `SettingsGroup` as widgets: the summary of its group type, the first
paragraph of its docstring, then one row for each setting: its label, its
control, and a button that resets it; under that row, across the three columns,
the description of the setting, the text of its docstring after the label. The
settings tab puts each group in a card with the title of the group, and the page
of a group shows the same widgets alone.

The projection holds its styles and no theme. Its keyword constructor fills them
from `theme`, a `WidgetTheme` scaled or not, or the default theme for `nothing`:
the summary and a description take its small font and its muted color, as the
description of a card does, and the rows and the columns take its gaps.

- A `Bool` is a switch, a number is a spin box with the step of its values, a
  `Symbol` is a choice of its values, and a `String` is a text.
- A group that no target of the editor applies, such as the render settings of a
  backend that draws no windows, says so on a line under the summary, and its
  controls are off. The line and the controls follow `is_used` of the group.
- A group that the application reads when it starts says so on that line.
- Each control shows the value of its setting and follows a change of it.
- The selection of the group holds a path in its widgets, as a path that this
  projection introduces, so a key reaches the control that the path names and a
  text draws its caret.

The view holds no effect of a setting. A control edit and a reset become the
normal edit of the group, a `ReplaceReferencedValueOperation` of one setting, and
the `settings` wrapper turns it into an applied setting.
"""
struct SettingsGroupToWidget <: Projection
    name_text::Any      # the style of the name of a setting: a `StyleText` or a cell of one
    caption::Any        # the style of the summary and a description: a `StyleText` or a cell of one
    gap::Any            # between the summary and the rows: a number or a cell of one
    column_gap::Any     # between the columns
    row_gap::Any        # between the rows
end

SettingsGroupToWidget(; theme = nothing, name_text = _make_text_style(theme, _compute_name_style),
                      caption = _make_text_style(theme, _compute_caption_style),
                      gap = get_widget_style(theme, :form_row_gap),
                      column_gap = get_widget_style(theme, :form_column_gap),
                      row_gap = get_widget_style(theme, :form_row_gap)) =
    SettingsGroupToWidget(name_text, caption, gap, column_gap, row_gap)

# A text style that `compute` makes from the values of the widget theme `theme`,
# scaled or not, or of the default theme for `nothing`. The name of a setting takes
# the label font and the text color, as the name of a field of a form. The summary
# and a description take the quiet font and the muted color, as the description
# of a card.
_make_text_style(::Nothing, compute) = compute(get_theme_defaults(WidgetTheme))
_make_text_style(theme, compute) = make_theme_cell(StyleText, theme, compute)
_compute_name_style(values) = StyleText(values.label_font, values.foreground)
_compute_caption_style(values) = StyleText(values.quiet_font, values.muted_foreground)

# `controls` holds `(control, name, convert)` for each control of a setting, so
# the reader turns the write of a control into the write of its setting: `convert`
# makes the value of the setting from the value that the control writes.
@iomap struct SettingsGroupToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    controls::Vector{Tuple{Any,Symbol,Any}}
end

# A setting and its text, which belongs to it, stand with no gap between them.
const _DESCRIPTION_GAP = 0

# ── Printer ───────────────────────────────────────────────────────────────

function print_document(p::SettingsGroupToWidget, recursion, group::SettingsGroup, ctx)
    T = get_settings_group_type(group)
    controls = Tuple{Any,Symbol,Any}[]
    styles = (name = unwrap_cell(p.name_text), caption = unwrap_cell(p.caption))
    is_used = () -> group.is_used
    cells = Any[]
    row_gaps = Any[]     # the gap above each row of the grid
    for description in get_setting_descriptions(T)
        control, convert = _make_setting_control(group, description, is_used)
        push!(controls, (control, description.name, convert))
        push!(cells, WidgetLabel(description.label; text_style = styles.name))
        push!(cells, control)
        reset = _make_command_button("Reset", "Give \"$(description.label)\" its default.",
                                     () -> _make_reset_operation(group, description))
        set_cell_computation!(getfield(reset, :enabled), is_used)
        push!(cells, reset)
        push!(row_gaps, nothing)
        text = uppercasefirst(strip_code_marks(description.text))
        if !isempty(text)
            push!(cells, LayoutConstraint(WidgetLabel(text; text_style = styles.caption); column_span = 3))
            push!(row_gaps, _DESCRIPTION_GAP)
        end
    end
    grid = GridLayout(cells, 3; horizontal_gap = unwrap_cell(p.column_gap),
                      vertical_gap = unwrap_cell(p.row_gap), vertical_align = :center, row_gaps)
    summary = WidgetLabel(""; text_style = styles.caption)
    set_cell_computation!(getfield(summary, :content), () -> _format_group_summary(T, is_used()))
    output = VerticalLayout(Any[summary, grid]; gap = unwrap_cell(p.gap))
    # Each kind of path of the group names a part of its widgets: the output holds
    # its image, and each document below it the part of its parent's path.
    set_output_path_computations!(output, group, path -> find_introduced_path(p, path))
    set_output_tree_path_computations!(output)
    SettingsGroupToWidgetIoMap(p, group, output, controls)
end

# The summary of the group type `T`, and under it the note that the group takes
# effect at the next start, or that the editor does not use it.
function _format_group_summary(T::Type, is_used::Bool)
    note = is_settings_group_read_at_start(T) ? "These settings take effect at the next start." :
           is_used ? "" : "This editor does not use these settings."
    join(filter(!isempty, String[strip_code_marks(compute_docstring_summary(T)), note]), "\n")
end

# The control of one setting, and the function from the value that it writes to
# the value of the setting. Its value is a computed cell over the setting, so it
# follows a change from any path: the tab, a command, an undo, a load. It is on
# while `is_used()` answers true.
function _make_setting_control(group, description::SettingDescription, is_used)
    name = description.name
    values = description.values
    current = () -> getproperty(group, name)
    tooltip = _make_setting_control_note(group, description)
    if description.type === Bool
        control = WidgetSwitch(; checked = current(), tooltip)
        set_cell_computation!(getfield(control, :checked), current)
        convert = identity
    elseif description.type in (Int, Float64) && values isa AbstractRange
        control = WidgetSpinBox(current(); min = first(values), max = last(values),
                                step = step(values), tooltip)
        set_cell_computation!(getfield(control, :value), current)
        convert = identity
    elseif description.type === Symbol && values isa Tuple
        choices = collect(values)
        control = WidgetRadioGroup(String.(choices);
                                   selected = something(findfirst(==(current()), choices), 0), tooltip)
        set_cell_computation!(getfield(control, :selected),
                              () -> something(findfirst(==(current()), choices), 0))
        convert = index -> choices[index]
    else
        control = WidgetText(string(current()); tooltip)
        set_cell_computation!(getfield(control, :content), () -> string(current()))
        convert = identity
    end
    set_cell_computation!(getfield(control, :enabled), is_used)
    control, convert
end

# What a control of a setting says when the pointer rests: its default, the values
# it takes, and that it is read at the start of the editor. The description of
# the setting shows under its row already, so the note does not say it again.
function _make_setting_control_note(group, description::SettingDescription)
    facts = Any["Default" => string(description.default)]
    values = description.values
    values isa AbstractRange && push!(facts, "Range" => string(first(values), " to ", last(values)))
    values isa Tuple && push!(facts, "Choices" => join(values, ", "))
    TooltipNote(; title = description.label, facts,
                hint = is_settings_group_read_at_start(get_settings_group_type(group)) ?
                       "Takes effect at the next start." : nothing)
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
# that this projection introduces into the group.
function read_intent(::SettingsGroupToWidget, iomap::SettingsGroupToWidgetIoMap,
                     operation::ReplaceReferencedValueOperation)
    for (control, name, convert) in iomap.controls
        operation.document === control || continue
        return _make_setting_write(iomap.input, name, convert(operation.value))
    end
    operation
end

# An edit of the text of a setting becomes the write of the whole text, and the
# caret after the characters that it put in.
function read_intent(p::SettingsGroupToWidget, iomap::SettingsGroupToWidgetIoMap,
                     operation::ReplaceStringRangeOperation)
    found = _find_text_edit(iomap, strip_reference_types(operation.reference))
    found === nothing && return invoke(read_intent, Tuple{Projection, Any, Any},
                                       p, iomap, operation)
    (name, range) = found
    group = iomap.input
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
function _find_text_edit(iomap::SettingsGroupToWidgetIoMap, reference)
    texts = IdDict{Any,Any}(control => name
                            for (control, name, _) in iomap.controls
                            if control isa WidgetText)
    node = iomap.output
    rest = reference
    while rest isa ConcreteReference
        found = get(texts, node, nothing)
        if found !== nothing
            range = _find_last_range_step(rest)
            return range === nothing ? nothing : (found, range)
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
# A path of the group through this projection names a path in its widgets, and
# a widget maps back to such a path.

map_reference_forward(p::SettingsGroupToWidget, ::SettingsGroupToWidgetIoMap, reference) =
    find_introduced_path(p, reference)
