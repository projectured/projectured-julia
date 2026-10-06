# Fragment of `ShellModule` — the bands a window's shell draws, and the rule for
# what may go on them.
#
# **A menu item that does nothing teaches a person that the menu is a lie.**
# Every item here runs a gesture that the window already answers, so the menu is
# a second way to reach what a key reaches and never a promise of its own. An
# item for a command that does not exist waits until the command does.

"""
    make_window_command(label, callback; icon = nothing, shortcut = nothing,
                        tooltip = nothing) -> WidgetMenuItem

One command for a band: what it says, and what it does when it is pressed.

`callback` takes the editor and does the work, which is what makes an item
honest — a band holds commands and never promises. A host builds its own
commands with this and needs no widget package of its own.

`tooltip` is what the item says about itself when the pointer rests on it, which
is where a command with a short label says the whole of what it does.
"""
make_window_command(label, callback; icon = nothing, shortcut = nothing,
                    tooltip = nothing) =
    WidgetMenuItem(label; action = Action(label; icon = icon, shortcut = shortcut,
                                          callback = callback),
                          tooltip = tooltip)

"""
    make_window_file_menu() -> WidgetMenuItem

The File menu: the name on the bar, and the menu that opens below it. Its
commands open a tab in the focused group and close the focused tab.
"""
make_window_file_menu() =
    WidgetMenuItem("File"; submenu = WidgetMenu(Any[
        make_window_command("New tab", _open_tab!;
                            shortcut = Shortcut(:t; ctrl = true)),
        make_window_command("Close tab", _close_tab!;
                            shortcut = Shortcut(:w; ctrl = true)),
    ]))

"""
    make_window_view_menu(; recorded = RECORDED_TOOLS) -> WidgetMenuItem

The View menu: the name on the bar, and the menu that opens below it. Its
commands split the focused group, open the gesture log, and open the appearance
and the settings.

**Settings** opens the settings of the editor in a tab: the settings tab of
`SettingsToWidget`, the same that the toolbar opens.

**Gesture log** opens the session's log in a tab. The wrapper `gesture_log`
records it from the start of the window, so the tab holds what happened before
it opened, and a person opens it after a fault rather than before one. The item
is there only when `recorded` holds `:gesture_log`, so a window that does not
record has no item for a log that stays empty.

**Appearance** (Ctrl+,) opens the `Appearance` of the window in a tab: the zoom
and the scales, each with its buttons.
"""
make_window_view_menu(; recorded = RECORDED_TOOLS) =
    WidgetMenuItem("View"; submenu = WidgetMenu(Any[
        make_window_command("Split vertically",
                            editor -> _split!(editor, :vertical);
                            shortcut = Shortcut(:backslash; ctrl = true)),
        make_window_command("Split horizontally",
                            editor -> _split!(editor, :horizontal);
                            shortcut = Shortcut(:backslash; ctrl = true, shift = true)),
        (:gesture_log in recorded ? (make_window_command("Gesture log",
                                         editor -> _reach_tool!(editor, GestureLog,
                                                                _make_default_tool(GestureLog));
                                         tooltip = "Every gesture of this session, and what each one did"),) :
                    ())...,
        make_window_command("Appearance",
                            editor -> _reach_tool!(editor, Appearance, _make_appearance_tool);
                            shortcut = Shortcut(:comma; ctrl = true),
                            tooltip = "The zoom and the scales of this window"),
        make_window_command("Settings",
                            editor -> _reach_tool!(editor, Settings, _find_tool_settings);
                            tooltip = "How this editor works"),
    ]))

"""
    make_window_help_menu(; about = _ -> AboutPage(), gesture_help = false,
                          command_palette = false) -> WidgetMenuItem

The Help menu: the name on the bar, and the menu that opens below it. Its
commands open a tab with every document type that an empty tab can make, a tab
with every projection, and the page about the program. Each reaches the tab
that already shows one, and opens one only when there is none.

`about` makes the page of the program that the window runs, from the editor.
The default page describes ProjecturEd; a window of another program gives its
own.

**Gestures** and **Command palette** come first, each only when the wrapper of
its name is on: `gesture_help` and `command_palette` say which are. Each does
what its key does, F1 or Ctrl+Shift+P: it opens the tool, or closes it when it
is open. The wrapper keeps its tool, so the command sends
`ToggleGestureHelpOperation` or `ToggleCommandPaletteOperation` with a route into
the content of the shell. The wrapper is around the shell, so it finds the
operation on its way up and answers what its key answers. The item carries no
shortcut, because the key reaches the wrapper itself, and its tooltip names the
key.
"""
make_window_help_menu(; about = _ -> AboutPage(), gesture_help = false, command_palette = false) =
    WidgetMenuItem("Help"; submenu = WidgetMenu(Any[
        (gesture_help ? (make_window_command("Gestures",
                             editor -> _post_shell_content_operation!(
                                 editor, ToggleGestureHelpOperation(), "Open or close the gesture help");
                             tooltip = "The gestures that work where the selection is (F1)"),) :
                        ())...,
        (command_palette ? (make_window_command("Command palette",
                                editor -> _post_shell_content_operation!(
                                    editor, ToggleCommandPaletteOperation(),
                                    "Open or close the command palette");
                                tooltip = "Find a command that works here, and run it (Ctrl+Shift+P)"),) :
                           ())...,
        make_window_command("Documents",
                            editor -> _reach_tool!(editor, DocumentTypeList,
                                                   _make_scrolling_tool(DocumentTypeList));
                            tooltip = "Every document type that an empty tab can make"),
        make_window_command("Projections",
                            editor -> _reach_tool!(editor, ProjectionList,
                                                   _make_scrolling_tool(ProjectionList));
                            tooltip = "Every projection: the views of a document, and the projections that combine them"),
        make_window_command("About", editor -> _reach_tool!(editor, AboutPage, about);
                            tooltip = "What this program is, and its version"),
    ]))

"""
    make_window_menu_bar(; recorded = RECORDED_TOOLS, extra = [], about = _ -> AboutPage(),
                         gesture_help = false, command_palette = false) -> WidgetMenu

The menu bar both binaries share: [`make_window_file_menu`](@ref), then
[`make_window_view_menu`](@ref), which takes `recorded`, then the menus of
`extra`, then [`make_window_help_menu`](@ref), which takes `about`,
`gesture_help` and `command_palette`. Help is the last menu, as on a desktop. A
host that wants another bar builds a `WidgetMenu` from the menus it wants.

**A menu item here performs its command.** `WidgetShell` fires a menu shortcut
**before the focused widget sees the key**, so an item that carries a shortcut it
cannot perform does not merely say nothing — it takes the key away from whatever
could have answered it. An item therefore goes on the bar only once it has a
callback that does the work, and the callback is the pane slice's own verb, so
the menu is a second way to reach one implementation and never a copy of it.

What is not here yet, and why: **Save** and **Reload** belong to the file tab's
own gesture table, and the clipboard's five to the clipboard wrapper. Each needs a
verb that reaches its owner through the editor. Until one has that, the key
answers and the menu says nothing about it, which is the honest half of the two.

A host adds its own menus with `extra`, and this package names none of them.
They go after File and View and before Help, so the bar reads the same way in
every binary until the host's own menus begin.
"""
make_window_menu_bar(; recorded = RECORDED_TOOLS, extra = [], about = _ -> AboutPage(),
                     gesture_help = false, command_palette = false) =
    WidgetMenu(Any[make_window_file_menu(), make_window_view_menu(; recorded), extra...,
                   make_window_help_menu(; about, gesture_help, command_palette)];
               orientation = :horizontal)

"""
    make_window_toolbar(; assistant = nothing, explorer = nothing, recorded = RECORDED_TOOLS,
                        extra = []) -> WidgetToolbar

The tools of the window, one button each: the explorer, the assistant, the
evaluator, the message log, the gesture log, the fault log, the frame
statistics, the frame times, the selection, the appearance and the settings.
Each button shows a picture and says its name as a tooltip, and a press reaches
the tool or opens it — see
[`make_window_tool_command`](@ref).

The tools are what a person looks for and cannot type the name of. A new tab is
not here: the tab strip of every group has a button for it, beside the group
that gets the tab.

Two tools need what only the window knows, and the window gives them as
functions of the editor:

- `assistant` makes the assistant of this window, with its backend, its model and
  its greeting. When it is `nothing` the window has no assistant, and the
  toolbar has no button for one: a blank assistant with no backend answers
  nothing.
- `explorer` makes the file explorer of this window, over its folder. When it is
  `nothing` the button opens what `Ctrl+T` and `explorer` open: the working
  directory.

Five tools show what the window records, and each fills only when a wrapper of
`build_editor` fills it: the message log with `message_log`, the gesture log with
`gesture_log`, the fault log with `fault_log`, and the statistics and the frame
times with `frame_statistics`. `recorded` holds the keywords of the wrappers that
are on, and the toolbar has no button for a tool that stays empty.

A host appends its own buttons with `extra`, which is where a command that only
one binary has belongs.
"""
make_window_toolbar(; assistant = nothing, explorer = nothing, recorded = RECORDED_TOOLS, extra = []) =
    WidgetToolbar(Any[
        make_window_tool_command("Explorer", Workspace; icon = :folder,
                                 tooltip = "Explorer: the files of this window's folder",
                                 make = something(explorer, _make_default_tool(Workspace))),
        (assistant === nothing ? () :
            (make_window_tool_command("Assistant", Assistant; icon = :chat,
                                      tooltip = "Assistant: ask a model about what this window shows",
                                      make = assistant),))...,
        make_window_tool_command("Evaluator", EvaluatorToplevel; icon = :terminal,
                                 tooltip = "Evaluator: type Julia, and Enter evaluates it"),
        _make_recorded_tool_commands(recorded)...,
        make_window_tool_command("Selection", SelectionInspector; icon = :crosshair,
                                 tooltip = "Selection: what the selection of this window names"),
        make_window_tool_command("Appearance", Appearance; icon = :palette,
                                 tooltip = "Appearance: the zoom and the scales of this window",
                                 make = _make_appearance_tool),
        make_window_tool_command("Settings", Settings; icon = :settings,
                                 tooltip = "Settings: how this editor works",
                                 make = _find_tool_settings),
        extra...,
    ])

"""
    RECORDED_TOOLS

The keywords of the wrappers of `build_editor` that fill the tools that show what
a window records: `message_log`, `gesture_log`, `fault_log` and
`frame_statistics`. The default of `recorded` of the bands, for a window that has
all of them.
"""
const RECORDED_TOOLS = (:message_log, :gesture_log, :fault_log, :frame_statistics)

# The buttons of the tools that show what the window records, each when the
# wrapper that fills it is in `recorded`.
_make_recorded_tool_commands(recorded) = (
    (:message_log in recorded ?
        (make_window_tool_command("Message log", MessageLog; icon = :list,
                                  tooltip = "Message log: what the program said in this session"),) : ())...,
    (:gesture_log in recorded ?
        (make_window_tool_command("Gesture log", GestureLog; icon = :keyboard,
                                  tooltip = "Gesture log: every gesture of this session, and what each one did"),) :
        ())...,
    (:fault_log in recorded ?
        (make_window_tool_command("Fault log", FaultLog; icon = :warning,
                                  tooltip = "Fault log: what failed in this session, and how often"),) : ())...,
    (:frame_statistics in recorded ?
        (make_window_tool_command("Statistics", FrameStatistics; icon = :chart,
                                  tooltip = "Statistics: how long the frames of this window take"),
         make_window_tool_command("Frame times", FrameTimeSeries; icon = :chart_line,
                                  tooltip = "Frame times: the time of each recent frame")) : ())...)

"""
    make_window_tool_command(label, type; icon = nothing, tooltip = nothing,
                             make = editor -> make_insertion_document(type))
        -> WidgetToolbarItem

A toolbar button for one tool of the window: a tab that holds a document of
`type`.

**A press reaches the tool, and makes one only when there is none.** It gives
the focus to a tab that holds a `type`: the first one in the focused group, else
the first one in the window. When no tab holds one, it opens `make(editor)` in a
new tab. So a second press never shows the same tool twice, and a person who
wants a second one opens it with `Ctrl+T` and the name of the tool.

A tab counts when the document it wraps is a `type`, so a tool kept inside a
history counts too. `make` takes the editor, because a window can know the
folder of its explorer only through the editor. By default it makes what
`Ctrl+T` and the name of the tool make.

The button shows `icon` alone and says `tooltip`; see [`WidgetToolbarItem`](@ref).
"""
make_window_tool_command(label, type::Type; icon = nothing, tooltip = nothing,
                         make = _make_default_tool(type)) =
    WidgetToolbarItem(label; action = Action(label; icon = icon,
                                             callback = editor -> _reach_tool!(editor, type, make)),
                             tooltip = tooltip)

_make_default_tool(type::Type) = _ -> make_insertion_document(type)

# The appearance tab shows the `Appearance` of the editor. An editor with no
# `appearance` wrapper has none, and the tab shows a new one.
_make_appearance_tool(editor) = something(find_editor_appearance(; editor), Appearance())

# The settings that the settings tab shows: those of the editor. An editor with no
# `settings` wrapper gets a `Settings` that nothing applies.
_find_tool_settings(editor) = something(find_editor_settings(; editor), make_settings())

# A list of the Help menu is longer than a pane, and a tab page gets no scroll of
# its own, so the list opens inside a scroll pane.
_make_scrolling_tool(type::Type) = _ -> WidgetScrollPane(make_insertion_document(type))

# What a tool tab shows: the content of the scroll pane that a scrolling tool
# opens in, else the document itself.
_get_tool_document(document) = document isa WidgetScrollPane ? document.content : document

# The pane slice's own edits, in the pane tree that holds the focus. A menu
# command is a second way to the one implementation. It runs while the editor
# evaluates the command, so it posts its edit, made through the readers, and the
# loop evaluates it at the top of the next frame.
function _find_focused_tree(editor)
    reference = find_pane_tree_reference(; editor)
    reference === nothing ? nothing : (reference, evaluate_reference(editor.document, reference))
end

function _post_tree_operation!(editor, tree_reference, operation, description)
    operation === nothing && return nothing
    rooted = read_rooted_operation(editor, tree_reference, operation; description)
    rooted === nothing || post_pane_operation!(editor, rooted)
    nothing
end

# A command for a wrapper around the shell. The operation goes to the content of
# the shell, so every reader around the shell reads it on its way up, and the
# wrapper that owns it answers in its place. What reaches the root is posted. An
# operation that comes back as it went found no wrapper, and nothing evaluates it.
function _post_shell_content_operation!(editor, operation, description)
    place = _find_shell_content_reference(editor)
    place === nothing && return nothing
    rooted = read_rooted_operation(editor, place, operation; description)
    (rooted === nothing || rooted isa typeof(operation)) || post_operation!(editor, rooted)
    nothing
end

# The content of the shell of the window, as a reference from the root. It is
# there with and without panes. `nothing` when no shell is found.
function _find_shell_content_reference(editor)
    shell = _find_shell_reference(editor.document)
    shell === nothing ? nothing : extend_reference(shell, FieldReferenceStep("content"))
end

# The first shell on the path of the selection, else the only shell of the
# document. The search does not go into a shell, because the documents are there.
function _find_shell_reference(root)
    selection = get_selection(root)
    if selection !== nothing
        steps = collect(get_reference_steps(strip_reference_types(selection)))
        for n in 0:length(steps)
            prefix = foldr(ConcreteReference, steps[1:n]; init = EmptyReference())
            try_evaluate_reference(root, prefix, nothing) isa WidgetShell && return prefix
        end
    end
    found = search_references(root, node -> node isa WidgetShell;
                              descend = (parent, child) -> !(parent isa WidgetShell))
    length(found) == 1 ? only(found) : nothing
end

function _open_tab!(editor)
    found = _find_focused_tree(editor)
    found === nothing && return nothing
    tree_reference, tree = found
    group = get_pane_focused_group(tree)
    group === nothing && return nothing
    _post_tree_operation!(editor, tree_reference,
                          make_pane_open_tab_operation(tree, group, default_new_pane_tab()),
                          "Open a new tab")
end

function _close_tab!(editor)
    found = _find_focused_tree(editor)
    found === nothing && return nothing
    tree_reference, tree = found
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    index == 0 && return nothing
    _post_tree_operation!(editor, tree_reference, make_pane_close_tab_operation(tree, group, index),
                          "Close the pane " * get_pane_tab_title_string(group.tabs[index]))
end

# A tool of the window, in a tab. A tab that already holds a `type` takes the
# focus instead, so a press never shows one tool twice. A session log is the log
# its recorder has written since the window opened, so it holds what happened
# before the tab existed.
function _reach_tool!(editor, type::Type, make)
    found = _find_focused_tree(editor)
    found === nothing && return nothing
    tree_reference, tree = found
    tool = _find_tool_tab(tree, type)
    if tool === nothing
        document = make(editor)
        shown = _get_tool_document(document)
        # A tool in a scroll pane is titled by what it shows, not by the pane.
        title = shown === document ? nothing : get_document_title(shown)
        post_pane_operation!(editor, make_open_pane_operation(document; title = title, editor))
    else
        group, index = tool
        _post_tree_operation!(editor, tree_reference, make_pane_focus_operation(tree, group, index),
                              "Focus the pane " * get_pane_tab_title_string(group.tabs[index]))
    end
    nothing
end

# The tab that holds a `type`: the first one in the focused group, which is the
# one nearest to the person, else the first one in the window.
function _find_tool_tab(tree, type::Type)
    focused = get_pane_focused_group(tree)
    groups = get_pane_groups(tree)
    ordered = focused === nothing ? groups :
              Any[focused, (group for group in groups if group !== focused)...]
    for group in ordered
        for (index, tab) in enumerate(group.tabs)
            _get_tool_document(get_wrapped_document(tab.content)) isa type && return (group, index)
        end
    end
    nothing
end

function _split!(editor, orientation::Symbol)
    found = _find_focused_tree(editor)
    found === nothing && return nothing
    tree_reference, tree = found
    group = get_pane_focused_group(tree)
    group === nothing && return nothing
    _post_tree_operation!(editor, tree_reference,
                          make_pane_split_operation(tree, group; orientation,
                                                    side = orientation === :vertical ? :right : :below,
                                                    tab = default_new_pane_tab()),
                          "Split the pane")
end

"""
    make_window_status_bar(document; extra = String[]) -> WidgetStatusBar

What the window says about where the person is: the title of the focused tab,
the selection in the document of that tab, and whatever the host appends. The
part of the selection that leads to the tab, through the splits and the groups
of the panes, names no place in a document, so the band leaves it out, and it
says nothing while the selection is not in the document of a tab.

**Each segment is a computed cell, so the band follows the window.** It
re-derives whenever what it read changes. A status bar built from strings would
say where the person was when the window opened and never again.

A window that holds no pane tree says nothing about a tab it does not have.
"""
make_window_status_bar(document; extra = String[]) =
    WidgetStatusBar(Any[Cell(@computation _window_status_title(document)),
                        Cell(@computation _window_status_selection(document)),
                        extra...])

# The pane tree of the window `document`, or `nothing` when it holds none.
function _find_window_tree(document)
    try
        get_window_tree(document)
    catch
        nothing
    end
end

function _window_status_title(document)
    tree = _find_window_tree(document)
    # A window that holds no pane tree has no focused tab to name.
    tree === nothing && return ""
    focus = get_pane_focus(tree)
    focus === nothing && return ""
    group, index = focus
    index == 0 && return ""
    get_pane_tab_title_string(group.tabs[index])
end

# The reference as it is written, and not as a person would say it. Saying it
# readably is `ReferenceToHumanReadableText`, which is a projection: it belongs
# in what the band draws, not in a string built here. The band is one short line,
# so it asks for the compact form, in which a place a projection introduced reads
# as its path between ‹ and ›. In a window with a pane tree it is the part inside
# the document of the focused tab, and a selection of that whole document says
# nothing more than the title does.
function _window_status_selection(document)
    tree = _find_window_tree(document)
    selection = tree === nothing ? get_selection(document) : find_pane_content_selection(tree)
    (selection === nothing || selection isa EmptyReference) && return ""
    sprint(show, selection; context = :compact => true)
end
