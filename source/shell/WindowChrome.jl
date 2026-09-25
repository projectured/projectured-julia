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
                          tooltip = tooltip,
                          # Room around the label: the rows stand apart, and the
                          # hover surface is larger than the words.
                          padding = Inset(4, 4, 12, 12))

# The room around the name of a menu on the bar. It is as tall as the room
# around a command, so a row of the menu that opens below it is as tall as the
# name.
const _WINDOW_MENU_PADDING = Inset(4, 4, 6, 6)

"""
    make_window_file_menu() -> WidgetMenuItem

The File menu: the name on the bar, and the menu that opens below it. Its
commands open a tab in the focused group and close the focused tab.
"""
make_window_file_menu() =
    WidgetMenuItem("File"; padding = _WINDOW_MENU_PADDING, submenu = WidgetMenu(Any[
        make_window_command("New tab", _open_tab!;
                            shortcut = Shortcut(:t; ctrl = true)),
        make_window_command("Close tab", _close_tab!;
                            shortcut = Shortcut(:w; ctrl = true)),
    ]))

"""
    make_window_view_menu() -> WidgetMenuItem

The View menu: the name on the bar, and the menu that opens below it. Its
commands split the focused group, and open the gesture log.

**Gesture log** opens the session's log in a tab. The recorder is always on, so
the tab holds what happened before it opened, and a person opens it after a
fault rather than before one.
"""
make_window_view_menu() =
    WidgetMenuItem("View"; padding = _WINDOW_MENU_PADDING, submenu = WidgetMenu(Any[
        make_window_command("Split vertically",
                            editor -> _split!(editor, :vertical);
                            shortcut = Shortcut(:backslash; ctrl = true)),
        make_window_command("Split horizontally",
                            editor -> _split!(editor, :horizontal);
                            shortcut = Shortcut(:backslash; ctrl = true, shift = true)),
        make_window_command("Gesture log",
                            editor -> _reach_tool!(editor, GestureLog,
                                                   _make_default_tool(GestureLog));
                            tooltip = "Every gesture of this session, and what each one did"),
    ]))

"""
    make_window_help_menu(; about = _ -> AboutPage()) -> WidgetMenuItem

The Help menu: the name on the bar, and the menu that opens below it. Its
commands open a tab with every document type that an empty tab can make, a tab
with every projection, and the page about the program. Each reaches the tab
that already shows one, and opens one only when there is none.

`about` makes the page of the program that the window runs, from the editor.
The default page describes ProjecturEd; a window of another program gives its
own.
"""
make_window_help_menu(; about = _ -> AboutPage()) =
    WidgetMenuItem("Help"; padding = _WINDOW_MENU_PADDING, submenu = WidgetMenu(Any[
        make_window_command("Documents",
                            editor -> _reach_tool!(editor, DocumentTypeList,
                                                   _make_default_tool(DocumentTypeList));
                            tooltip = "Every document type that an empty tab can make"),
        make_window_command("Projections",
                            editor -> _reach_tool!(editor, ProjectionList,
                                                   _make_default_tool(ProjectionList));
                            tooltip = "Every projection: the views of a document, and the projections that combine them"),
        make_window_command("About", editor -> _reach_tool!(editor, AboutPage, about);
                            tooltip = "What this program is, and its version"),
    ]))

"""
    make_window_menu_bar(; extra = [], about = _ -> AboutPage()) -> WidgetMenu

The menu bar both binaries share: [`make_window_file_menu`](@ref), then
[`make_window_view_menu`](@ref), then the menus of `extra`, then
[`make_window_help_menu`](@ref), which takes `about`. Help is the last menu, as
on a desktop. A host that wants another bar builds a `WidgetMenu` from the menus
it wants.

**A menu item here performs its command.** `WidgetShell` fires a menu shortcut
**before the focused widget sees the key**, so an item that carries a shortcut it
cannot perform does not merely say nothing — it takes the key away from whatever
could have answered it. An item therefore goes on the bar only once it has a
callback that does the work, and the callback is the pane slice's own verb, so
the menu is a second way to reach one implementation and never a copy of it.

What is not here yet, and why: **Save** and **Reload** belong to the file tab's
own gesture table, **Command palette** and **Gesture help** to the wrappers that
draw them, and the clipboard's five to the clipboard wrapper. Each needs a verb
that reaches its owner through the editor. Until one has that, the key answers
and the menu says nothing about it, which is the honest half of the two.

A host adds its own menus with `extra`, and this package names none of them.
They go after File and View and before Help, so the bar reads the same way in
every binary until the host's own menus begin.
"""
make_window_menu_bar(; extra = [], about = _ -> AboutPage()) =
    WidgetMenu(Any[make_window_file_menu(), make_window_view_menu(), extra...,
                   make_window_help_menu(; about = about)];
               orientation = :horizontal, padding = Inset(2, 2, 2, 2))

"""
    make_window_toolbar(; assistant = nothing, explorer = nothing, extra = []) -> WidgetToolbar

The tools of the window, one button each: the explorer, the assistant, the
evaluator, the message log, the gesture log, the fault log, the frame
statistics, the frame plot and the selection. Each button shows a picture and
says its name as a tooltip, and a press reaches the tool or opens it — see
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

A host appends its own buttons with `extra`, which is where a command that only
one binary has belongs.
"""
make_window_toolbar(; assistant = nothing, explorer = nothing, extra = []) =
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
        make_window_tool_command("Message log", MessageLog; icon = :list,
                                 tooltip = "Message log: what the program said in this session"),
        make_window_tool_command("Gesture log", GestureLog; icon = :keyboard,
                                 tooltip = "Gesture log: every gesture of this session, and what each one did"),
        make_window_tool_command("Fault log", FaultLog; icon = :warning,
                                 tooltip = "Fault log: what failed in this session, and how often"),
        make_window_tool_command("Statistics", FrameStatistics; icon = :chart,
                                 tooltip = "Statistics: how long the frames of this window take"),
        make_window_tool_command("Frame plot", FramePlot; icon = :chart_line,
                                 tooltip = "Frame plot: the time of each recent frame"),
        make_window_tool_command("Selection", SelectionInspector; icon = :crosshair,
                                 tooltip = "Selection: what the selection of this window names"),
        extra...,
    ]; padding = Inset(4, 4, 4, 4))

"""
    run_with_window_tools(run) -> the answer of `run`

Open a window with what the tools of [`make_window_toolbar`](@ref) need, and
answer what `run` answers.

`run(feeds, start)` opens the window: it gives `feeds` to `make_editor`, it
calls `start(editor)` with the editor that `make_editor` answers, and then it
runs the loop with `run_editor!(editor)`. Then:

- the message log holds what the program logs while the window is open. The
  capture is installed before `run` and removed after it, also when it throws,
  so the logger the window replaced comes back.
- the message log and the frame statistics follow the window, one feed each.
- the fault log holds every fault the editor catches, because `start` attaches
  the session's log to the store of the editor.

Every binary with the toolbar opens its window through this, so a button on it
never opens a tool that stays empty in one of them.

# Example

    run_with_window_tools() do feeds, start
        editor = make_editor(document, projection, "Title"; backend = backend,
                             feeds = feeds)
        start(editor)
        run_editor!(editor)
    end
"""
function run_with_window_tools(run)
    previous = install_message_log_capture!()
    try
        run(Feed[MessageLogFeed(), FrameStatisticsFeed()], _start_window_tools!)
    finally
        remove_message_log_capture!(previous)
    end
end

# A fault reaches a log only when the log is attached to the store of the
# editor, and only an editor has a store.
function _start_window_tools!(editor)
    hasproperty(editor, :faults) || return nothing
    attach_fault_target!(editor.faults, get_session_fault_log())
    nothing
end

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
                             tooltip = tooltip,
                             # Room around the picture: the buttons stand apart,
                             # and the hover surface is larger than the glyph.
                             padding = Inset(4, 4, 4, 4))

_make_default_tool(type::Type) = _ -> make_insertion_document(type)

# The pane slice's own edits, in the pane tree that holds the focus. A menu
# command is a second way to the one implementation. It runs while the editor
# evaluates the command, so it posts its edit, made through the readers, and the
# loop evaluates it at the top of the next frame.
function _find_focused_tree(editor)
    reference = find_pane_tree_reference(editor)
    reference === nothing ? nothing : (reference, evaluate_reference(editor.document, reference))
end

function _post_tree_operation!(editor, tree_reference, operation, description)
    operation === nothing && return nothing
    rooted = read_rooted_operation(editor, tree_reference, operation; description)
    rooted === nothing || post_pane_operation!(editor, rooted)
    nothing
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
        post_pane_operation!(editor, make_open_pane_operation(editor, make(editor)))
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
            get_wrapped_document(tab.content) isa type && return (group, index)
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
the selection, and whatever the host appends.

**Each segment is a computed cell, so the band follows the window.** It
re-derives whenever what it read changes. A status bar built from strings would
say where the person was when the window opened and never again.

A window that holds no pane tree says nothing about a tab it does not have.
"""
make_window_status_bar(document; extra = String[]) =
    WidgetStatusBar(Any[Cell(@computation _window_status_title(document)),
                        Cell(@computation _window_status_selection(document)),
                        extra...];
                    # Room around the text, so the line does not touch the
                    # window's edges or the panes above it.
                    padding = Inset(4, 4, 8, 8))

function _window_status_title(document)
    tree = try
        get_window_tree(document)
    catch
        # A window that holds no pane tree has no focused tab to name.
        return ""
    end
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
# as its path between ‹ and ›.
function _window_status_selection(document)
    selection = get_selection(document)
    selection === nothing ? "" : sprint(show, selection; context = :compact => true)
end
