# Fragment of `SettingsManagingModule` — the settings of an editor as widgets: the
# view of the settings tab.

"""
    SettingsToWidget(; theme = nothing)

The settings tab: the `Settings` of an editor as widgets, in a pane that scrolls.
One card for each group, in the order of their names, with the title of the group
and the summary of its group type, and the rows of its settings, which
[`SettingsGroupToWidget`](@ref) makes for the page of one group too. Under the
cards, a button resets all of them, and two buttons save the settings to their
file and load them from it; these two are off for settings with no file.

The projection holds its styles and no theme. Its keyword constructor fills them
from `theme`, a `WidgetTheme` scaled or not, or the default theme for `nothing`,
as `SettingsGroupToWidget` does.

- A group that no target of the editor applies, or that the application reads
  when it starts, says so on its card, on a line under the summary.
- The selection of the settings holds a path in the widgets of the tab, as a path
  that this projection introduces, so a key reaches the control that the path
  names and a text draws its caret. Every control is in the one widget tree of
  the tab, so Tab moves through the controls of every card.
- The pane keeps its own place. A change of a setting does not print the tab
  again, because each control follows its setting, so the place stays. A change
  of "Catch faults" prints the whole view again, and the new pane starts at the
  top.

The view holds no effect of a setting. A control edit and a reset become the
normal edit of a group, a `ReplaceReferencedValueOperation` of one setting, and
the `settings` wrapper turns it into an applied setting.
"""
struct SettingsToWidget <: Projection
    name_text::Any      # the style of the name of a setting: a `StyleText` or a cell of one
    caption::Any        # the style of a description: a `StyleText` or a cell of one
    button_gap::Any     # between the buttons under the cards: a number or a cell of one
    section_gap::Any    # between the cards
    column_gap::Any     # between the columns of a card
    row_gap::Any        # between the rows of a card
end

SettingsToWidget(; theme = nothing, name_text = _make_text_style(theme, _compute_name_style),
                 caption = _make_text_style(theme, _compute_caption_style),
                 button_gap = get_widget_style(theme, :button_gap),
                 section_gap = get_widget_style(theme, :section_gap),
                 column_gap = get_widget_style(theme, :form_column_gap),
                 row_gap = get_widget_style(theme, :form_row_gap)) =
    SettingsToWidget(name_text, caption, button_gap, section_gap, column_gap, row_gap)

# `controls` holds `(control, group, name, convert)` for each control of a setting,
# as the IO map of `SettingsGroupToWidget` does.
@iomap struct SettingsToWidgetIoMap
    projection::Any
    input::Any
    output::Any
    controls::Vector{Tuple{Any,Any,Symbol,Any}}
end

# ── Printer ───────────────────────────────────────────────────────────────

function print_document(p::SettingsToWidget, recursion, settings::Settings, ctx)
    controls = Tuple{Any,Any,Symbol,Any}[]
    groups = get_settings_groups(settings)
    styles = (name = unwrap_cell(p.name_text), caption = unwrap_cell(p.caption))
    gaps = (column = unwrap_cell(p.column_gap), row = unwrap_cell(p.row_gap))
    cards = Any[_make_group_card(group, controls, styles, gaps) for group in groups]
    reset = _make_command_button("Reset all", "Give every setting its default.",
                                 () -> _make_reset_operation(groups))
    save = _make_command_button("Save", "Write the settings to their file.",
                                () -> SaveSettingsOperation(settings, settings.file))
    load = _make_command_button("Load", "Read the settings from their file.",
                                () -> LoadSettingsOperation(settings, settings.file))
    for button in (save, load)
        set_cell_computation!(getfield(button, :enabled), () -> !isempty(settings.file))
    end
    buttons = HorizontalLayout(Any[reset, save, load]; gap = unwrap_cell(p.button_gap))
    output = WidgetScrollPane(VerticalLayout(Any[cards..., buttons]; gap = unwrap_cell(p.section_gap));
                              grows = (width = false, height = true))
    # Each kind of path of the settings names a part of the tab: the output holds
    # its image, and each document below it the part of its parent's path.
    set_output_path_computations!(output, settings, path -> find_introduced_path(p, path))
    set_output_tree_path_computations!(output)
    SettingsToWidgetIoMap(p, settings, output, controls)
end

# A card of one group: its title, the summary of its type and its note, and its
# rows. The note follows the `is_used` of the group.
function _make_group_card(group, controls, styles, gaps)
    card = WidgetCard(; title = get_document_title(group),
                      content = WidgetComposite(Any[_make_group_grid(group, controls, styles, gaps)]))
    set_cell_computation!(getfield(card, :description), () -> _format_group_summary(group))
    card
end

# ── Reader ────────────────────────────────────────────────────────────────

# The write of a control becomes the write of its setting, and an edit of the text
# of a setting the write of the whole text, as on the page of a group. Every other
# operation takes the default way back of the kernel.
read_intent(::SettingsToWidget, iomap::SettingsToWidgetIoMap, operation::ReplaceReferencedValueOperation) =
    _read_control_write(iomap, operation)
read_intent(p::SettingsToWidget, iomap::SettingsToWidgetIoMap, operation::ReplaceStringRangeOperation) =
    _read_text_edit(p, iomap, operation)

# ── Reference mapping ─────────────────────────────────────────────────────
# A path of the settings through this projection names a path in the widgets of
# the tab, and a widget of the tab maps back to such a path.

map_reference_forward(p::SettingsToWidget, ::SettingsToWidgetIoMap, reference) =
    find_introduced_path(p, reference)
