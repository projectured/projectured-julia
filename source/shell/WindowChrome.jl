# Fragment of `ShellModule` — the bands a window's shell draws, and the rule for
# what may go on them.
#
# **A menu item that does nothing teaches a person that the menu is a lie.**
# Every item here runs a gesture that the window already answers, so the menu is
# a second way to reach what a key reaches and never a promise of its own. An
# item for a command that does not exist waits until the command does.

"""
    make_window_menu_bar(; clipboard = true) -> WidgetMenu

The menu bar both binaries share: what a window does with its tabs, what the
clipboard does with a selection, and what the window shows.

`clipboard` says whether the window has the clipboard wrapper. A window without
it gets no Edit menu, because an item that answers nothing is worse than no item.

A host adds its own menus beside these — the interface adds Run and Stop — and
this package names none of them.
"""
function make_window_menu_bar(; clipboard::Bool = true)
    file = WidgetMenu([
        WidgetMenuItem("New tab";       action = Action("New tab"; shortcut = Shortcut(:t; ctrl = true))),
        WidgetMenuItem("Close tab";     action = Action("Close tab"; shortcut = Shortcut(:w; ctrl = true))),
        WidgetMenuItem("Duplicate tab"; action = Action("Duplicate tab"; shortcut = Shortcut(:d; ctrl = true, shift = true))),
        WidgetMenuItem("Save";          action = Action("Save"; shortcut = Shortcut(:s; ctrl = true))),
        WidgetMenuItem("Reload";        action = Action("Reload"; shortcut = Shortcut(:o; ctrl = true))),
    ])
    edit = WidgetMenu([
        WidgetMenuItem("Copy";       action = Action("Copy"; shortcut = Shortcut(:c; ctrl = true))),
        WidgetMenuItem("Cut";        action = Action("Cut"; shortcut = Shortcut(:x; ctrl = true))),
        WidgetMenuItem("Note";       action = Action("Note"; shortcut = Shortcut(:n; ctrl = true))),
        WidgetMenuItem("Paste";      action = Action("Paste"; shortcut = Shortcut(:v; ctrl = true))),
        WidgetMenuItem("Paste copy"; action = Action("Paste copy"; shortcut = Shortcut(:v; ctrl = true, shift = true))),
    ])
    view = WidgetMenu([
        WidgetMenuItem("Split vertically";   action = Action("Split vertically"; shortcut = Shortcut(:backslash; ctrl = true))),
        WidgetMenuItem("Split horizontally"; action = Action("Split horizontally"; shortcut = Shortcut(:backslash; ctrl = true, shift = true))),
        WidgetMenuItem("Command palette";    action = Action("Command palette"; shortcut = Shortcut(:p; ctrl = true, shift = true))),
        WidgetMenuItem("Gesture help";       action = Action("Gesture help"; shortcut = Shortcut(:f1))),
    ])
    menus = Any[WidgetMenuItem("File"; submenu = file)]
    clipboard && push!(menus, WidgetMenuItem("Edit"; submenu = edit))
    push!(menus, WidgetMenuItem("View"; submenu = view))
    WidgetMenu(menus; orientation = :horizontal)
end

"""
    make_window_toolbar() -> WidgetToolbar

The few commands a hand reaches for without a menu. It is deliberately short: a
toolbar that holds everything is a menu bar that draws twice.
"""
make_window_toolbar() =
    WidgetToolbar(Any[
        WidgetMenuItem("New tab"; action = Action("New tab"; shortcut = Shortcut(:t; ctrl = true))),
        WidgetMenuItem("Save";    action = Action("Save"; shortcut = Shortcut(:s; ctrl = true))),
    ]; padding = Inset(4, 4, 4, 4))

"""
    make_window_status_bar(document; extra = String[]) -> WidgetStatusBar

What the window says about where the person is: the title of the focused tab, the
selection in the words a person reads, and whatever the host appends.

The selection is read from `document`, which is the window's own document. A
window that holds no pane tree shows its two other fields and says nothing about
a tab it does not have.
"""
function make_window_status_bar(document; extra = String[])
    title = _window_status_title(document)
    selection = _window_status_selection(document)
    WidgetStatusBar(Any[title, selection, extra...])
end

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
