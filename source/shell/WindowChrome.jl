# Fragment of `ShellModule` — the bands a window's shell draws, and the rule for
# what may go on them.
#
# **A menu item that does nothing teaches a person that the menu is a lie.**
# Every item here runs a gesture that the window already answers, so the menu is
# a second way to reach what a key reaches and never a promise of its own. An
# item for a command that does not exist waits until the command does.

"""
    make_window_menu_bar() -> WidgetMenu

The menu bar both binaries share.

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

A host adds its own menus beside these, and this package names none of them.
"""
make_window_menu_bar() =
    WidgetMenu(Any[
        WidgetMenuItem("File"; submenu = WidgetMenu(Any[
            WidgetMenuItem("New tab";
                           action = Action("New tab";
                                           shortcut = Shortcut(:t; ctrl = true),
                                           callback = _open_tab!)),
            WidgetMenuItem("Close tab";
                           action = Action("Close tab";
                                           shortcut = Shortcut(:w; ctrl = true),
                                           callback = _close_tab!)),
        ])),
        WidgetMenuItem("View"; submenu = WidgetMenu(Any[
            WidgetMenuItem("Split vertically";
                           action = Action("Split vertically";
                                           shortcut = Shortcut(:backslash; ctrl = true),
                                           callback = editor -> _split!(editor, :vertical))),
            WidgetMenuItem("Split horizontally";
                           action = Action("Split horizontally";
                                           shortcut = Shortcut(:backslash; ctrl = true, shift = true),
                                           callback = editor -> _split!(editor, :horizontal))),
        ])),
    ]; orientation = :horizontal)

"""
    make_window_toolbar() -> WidgetToolbar

The few commands a hand reaches for without a menu. It is deliberately short: a
toolbar that holds everything is a menu bar that draws twice.
"""
make_window_toolbar() =
    WidgetToolbar(Any[
        WidgetMenuItem("New tab";
                       action = Action("New tab"; callback = _open_tab!)),
    ]; padding = Inset(4, 4, 4, 4))

# The pane slice's own verbs, reached through the tree the editor shows. A menu
# command is a second way to the one implementation.
_window_tree(editor) = try
    get_window_tree(editor)
catch
    nothing
end

function _open_tab!(editor)
    tree = _window_tree(editor)
    tree === nothing && return nothing
    group = get_pane_focused_group(tree)
    group === nothing && return nothing
    apply_pane_operation!(tree, make_pane_open_tab_operation(tree, group,
                                                             default_new_pane_tab()))
    nothing
end

function _close_tab!(editor)
    tree = _window_tree(editor)
    tree === nothing && return nothing
    focus = get_pane_focus(tree)
    focus === nothing && return nothing
    group, index = focus
    index == 0 && return nothing
    apply_pane_operation!(tree, make_pane_close_tab_operation(tree, group, index))
    nothing
end

function _split!(editor, orientation::Symbol)
    tree = _window_tree(editor)
    tree === nothing && return nothing
    group = get_pane_focused_group(tree)
    group === nothing && return nothing
    apply_pane_operation!(tree, make_pane_split_operation(tree, group, orientation,
                                                          orientation === :vertical ? :right : :below,
                                                          default_new_pane_tab()))
    nothing
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
    WidgetStatusBar(Any[ComputedCell(() -> _window_status_title(document)),
                        ComputedCell(() -> _window_status_selection(document)),
                        extra...])

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
# in what the band draws, not in a string built here.
function _window_status_selection(document)
    selection = get_selection(document)
    selection === nothing ? "" : string(selection)
end
