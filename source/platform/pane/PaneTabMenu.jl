# Fragment of `PaneModule` — the menu of a tab: a right click on the header of a
# tab opens the commands of that tab, each with the keys that run the same
# command on the focused tab.

# The group and the index of the tab whose header the pointer is on, or `nothing`.
# The header is the view of the title of the tab, so the mouse target of the tree
# then goes into the title. A part of the page that its content does not claim
# names the tab itself, and is no header.
function _find_pointed_tab_header(tree::PaneTree)
    path = get_mouse_target(tree)
    path isa ConcreteReference || return nothing
    group = nothing
    node = tree
    for step in get_reference_steps(path)
        if node isa PaneTab
            (step isa FieldReferenceStep && step.name == "title" && group !== nothing) || return nothing
            index = findfirst(tab -> tab === node, group.tabs)
            return index === nothing ? nothing : (group, index)
        end
        node = try_evaluate_reference(node, extend_reference(EmptyReference(), step), nothing)
        node === nothing && return nothing
        node isa PaneGroup && (group = node)
    end
    nothing
end

# The menu of tab `index` of `group`. Each item acts on that tab, also when another
# tab has the focus, and shows the keys of the table of the tree that do the same
# to the focused tab. An item that can not act now is greyed.
function _make_tab_menu(tree::PaneTree, group::PaneGroup, index::Integer)
    tab = group.tabs[index]
    item(label, operation, command = nothing) =
        WidgetMenuItem(label; operation, enabled = operation !== nothing,
                       keys = command === nothing ? GesturePattern[] : find_bound_keys(PaneTree, command))
    duplicate = has_document_duplicate(tab.content) ?
                make_pane_duplicate_tab_operation(tree, group, index) : nothing
    maximized = find_pane_maximized_group(tree) !== nothing
    # A window of one group has nothing to maximize, also when a split holds it.
    maximize = maximized ? make_pane_restore_operation(tree) :
               length(get_pane_groups(tree)) < 2 ? nothing : make_pane_maximize_operation(tree, group)
    WidgetMenu(Any[
        item("Duplicate", duplicate, "Duplicate the focused tab"),
        item("Rename", make_pane_title_caret_operation(tree, group, index), "Put the caret in the tab name"),
        WidgetSeparator(),
        item("Split right",
             make_pane_split_operation(tree, group; orientation = :vertical, side = :right,
                                       tab = default_new_pane_tab()),
             "Split vertically — the new pane on the right"),
        item("Split down",
             make_pane_split_operation(tree, group; orientation = :horizontal, side = :below,
                                       tab = default_new_pane_tab()),
             "Split horizontally — the new pane below"),
        item(maximized ? "Restore layout" : "Maximize group", maximize,
             "Maximize the focused group, or give back the layout"),
        WidgetSeparator(),
        item("Add to explorer", AddExplorerEntryOperation(_get_tab_document(tab))),
        WidgetSeparator(),
        item("Close", make_pane_close_tab_operation(tree, group, index), "Close the focused tab")])
end

# The menu of the tab under the pointer, as a layer named by the tab.
function _make_tab_menu_operation(tree::PaneTree, gesture)
    found = _find_pointed_tab_header(tree)
    found === nothing && return nothing
    group, index = found
    make_context_menu_operation(tree, _make_tab_menu(tree, group, index), gesture;
                                title = get_pane_tab_title_string(group.tabs[index]))
end

# A right click on the header of a tab opens its menu. The tree holds the rule,
# because Close and Split need the group of the tab and the focus of the tree.
const _PANE_TAB_MENU_BINDINGS = GestureBinding[
    GestureBinding(MouseClickPattern(:right), _make_tab_menu_operation;
                   applicable = (tree, selection) -> _find_pointed_tab_header(tree) !== nothing,
                   description = "Show the menu of the tab", domain = "context menu",
                   name = "Show the menu of the tab")]
