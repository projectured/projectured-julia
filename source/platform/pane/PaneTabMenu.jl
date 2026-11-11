# Fragment of `PaneModule` — the menu of a tab: a right click on the header of a
# tab opens the commands of that tab, each with the keys that run the same
# command on the focused tab.

# The group and the index of the tab whose header the pointer is on, or `nothing`.
# The header is the view of the title of the tab, so the mouse target of the tree
# then goes into the title, or to the close button in the header. A part of the
# page that its content does not claim names the tab itself, and is no header.
function _find_pointed_tab_header(tree::PaneTree)
    path = get_mouse_target(tree)
    path isa ConcreteReference || return nothing
    group = nothing
    node = tree
    for step in get_reference_steps(path)
        if node isa PaneTab
            ((step isa FieldReferenceStep && step.name == "title") || _is_close_button_step(step)) &&
                group !== nothing || return nothing
            index = findfirst(tab -> tab === node, group.tabs)
            return index === nothing ? nothing : (group, index)
        end
        node = try_evaluate_reference(node, extend_reference(EmptyReference(), step), nothing)
        node === nothing && return nothing
        node isa PaneGroup && (group = node)
    end
    nothing
end

"""
    DuplicatePaneTabOperation(tree, group, tab)

Put a duplicate of `tab` of `group` right after it, and focus it, when the
operation runs. The copy of the content is made then, by
[`make_pane_duplicate_tab_operation`](@ref), so an operation that is made and
never runs, such as the item of a menu that a person does not choose, copies
nothing. `tab` names the tab itself, so the operation finds the tab where it is
when it runs. A tab that left `group`, and a content whose copy fails, give no
duplicate, and the refusal of a copy is logged.

The operation names the place of `tree`, so the readers carry it to the root of
the editor as they carry an edit of the tree, and a history on the way records
it. An undo takes the duplicate away again.
"""
struct DuplicatePaneTabOperation <: Operation
    tree::PaneTree
    group::PaneGroup
    tab::PaneTab
    place::Reference
end

DuplicatePaneTabOperation(tree::PaneTree, group::PaneGroup, tab::PaneTab) =
    DuplicatePaneTabOperation(tree, group, tab, EmptyReference(PaneTree))

OperationModule.operation_reference(operation::DuplicatePaneTabOperation) = operation.place
OperationModule.retarget_operation(operation::DuplicatePaneTabOperation, reference::Reference) =
    DuplicatePaneTabOperation(operation.tree, operation.group, operation.tab, reference)
OperationModule.describe_operation(::DuplicatePaneTabOperation) = "Duplicate the tab"

# The edit that puts the duplicate in the tree as the tree is now, with the paths
# from the place of the tree, or `nothing`.
function _make_placed_duplicate(operation::DuplicatePaneTabOperation)
    index = findfirst(tab -> tab === operation.tab, operation.group.tabs)
    index === nothing && return nothing
    duplicate = make_pane_duplicate_tab_operation(operation.tree, operation.group, index)
    duplicate === nothing && return nothing
    reroot_operation(duplicate, Tuple(get_reference_steps(strip_reference_types(operation.place))))
end

function OperationModule.evaluate_operation(editor, operation::DuplicatePaneTabOperation)
    duplicate = _make_placed_duplicate(operation)
    duplicate === nothing || evaluate_operation(editor, duplicate)
    nothing
end

# The way back is the way back of the edit that the operation makes when it runs.
# An operation that makes no edit changes no document.
function OperationModule.evaluate_invertible_operation!(editor, operation::DuplicatePaneTabOperation)
    duplicate = _make_placed_duplicate(operation)
    duplicate === nothing ? DoNothingOperation() : evaluate_invertible_operation!(editor, duplicate)
end

# The menu of tab `index` of `group`. Each item acts on that tab, also when another
# tab has the focus, and shows the keys of the table of the tree that do the same
# to the focused tab. An item that can not act now is greyed.
function _make_tab_menu(tree::PaneTree, group::PaneGroup, index::Integer)
    tab = group.tabs[index]
    item(label, operation, command = nothing) =
        WidgetMenuItem(label; operation, enabled = operation !== nothing,
                       keys = command === nothing ? GesturePattern[] : find_bound_keys(PaneTree, command))
    # The copy waits for the choice of the item. A content of a kind with a
    # duplicate whose tree holds something that a copy can not own shows the item,
    # and its choice logs the refusal, as the key does.
    duplicate = has_document_duplicate(tab.content) ? DuplicatePaneTabOperation(tree, group, tab) : nothing
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
        item("Close", make_pane_close_tab_operation(tree, group, index), "Close the focused tab"),
        item("Close others", make_pane_close_other_tabs_operation(tree, group, index)),
        item("Close to the right", make_pane_close_tabs_to_the_right_operation(tree, group, index))])
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
