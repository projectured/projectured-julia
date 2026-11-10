# Fragment of `SettingsManagingModule` — the settings of an editor as widgets: the
# view of the settings tab.

"""
    SettingsToWidget(; theme = nothing)

The settings tab: the `Settings` of an editor as widgets, in a pane that scrolls.
One card for each group, in the order of their names, with the title of the group.
The card holds the group, which [`SettingsGroupToWidget`](@ref) draws: its
summary, and a row for each setting. Under the cards, a button resets all of
them, and two buttons save the settings to their file and load them from it;
these two are off for settings with no file.

The projection holds its gaps and no theme. Its keyword constructor fills them
from `theme`, a `WidgetTheme` scaled or not, or the default theme for `nothing`.

- The selection of the settings holds a path in the widgets of the tab, as a path
  that this projection introduces. A path into a card goes on into its group, so
  a key reaches the control that the path names and a text draws its caret.
- The pane keeps its own place. A change of a setting does not print the tab
  again, because each control follows its setting, so the place stays. A change
  of "Catch faults" prints the whole view again, and the new pane starts at the
  top.

The view holds no effect of a setting. "Reset all" becomes the normal edit of
each setting, a `ReplaceReferencedValueOperation`, and the `settings` wrapper
turns it into an applied setting.
"""
struct SettingsToWidget <: Projection
    button_gap::Any     # between the buttons under the cards: a number or a cell of one
    section_gap::Any    # between the cards
end

SettingsToWidget(; theme = nothing, button_gap = get_widget_style(theme, :button_gap),
                 section_gap = get_widget_style(theme, :section_gap)) =
    SettingsToWidget(button_gap, section_gap)

@iomap struct SettingsToWidgetIoMap
    projection::Any
    input::Any
    output::Any
end

# ── Printer ───────────────────────────────────────────────────────────────

function print_document(p::SettingsToWidget, recursion, settings::Settings, ctx)
    groups = get_settings_groups(settings)
    cards = Any[WidgetCard(; title = get_document_title(group), content = group) for group in groups]
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
    # its image, and each document below it, a group too, the part of its parent's
    # path.
    set_output_path_computations!(output, settings, path -> find_introduced_path(p, path))
    set_output_tree_path_computations!(output)
    SettingsToWidgetIoMap(p, settings, output)
end

# ── Reference mapping ─────────────────────────────────────────────────────
# A path of the settings through this projection names a path in the widgets of
# the tab, and a widget of the tab maps back to such a path.

map_reference_forward(p::SettingsToWidget, ::SettingsToWidgetIoMap, reference) =
    find_introduced_path(p, reference)
