# Fragment of `ExplorerModule` — the menu of a row of an explorer: open it in a new
# tab, add it to the explorer or remove it, rename a section and add to it, open
# a long list of children as a page, and the commands of the document of the row
# from its own gesture table.

# The count of children past which a node offers its children as a page.
const _LIST_CHILD_COUNT = 50

# The menu of the row under the pointer, or of the selected row for a command with
# no pointer, as one layer named by the row: the items of the explorer, then the
# commands of the document of the row, each rerooted from the place of the
# document in the tree, so it acts on the document. An item that edits an entry
# works on the tree, also from a row of the matches.
function _make_row_menu_operation(explorer::Explorer, gesture)
    path = gesture isa MouseClick ? get_mouse_target(explorer) : get_selection(explorer)
    steps = _find_shown_node_steps(explorer, path)
    steps === nothing && return nothing
    tree = getfield(explorer, :tree)[]
    navigator = getfield(explorer, :navigator)[]
    address = _make_steps(steps...)
    document = try_evaluate_reference(tree.root, address, nothing)
    document === nothing && return nothing
    node_steps = (FieldReferenceStep("tree"), FieldReferenceStep("root"), steps...)
    node = _make_steps(node_steps...)
    place = _find_entry_place(tree.root, steps)
    items = Any[WidgetMenuItem("Open in a new tab"; operation = OpenPageOperation(navigator.content, address, :new_tab))]
    if place !== nothing && place.is_entry && place.index !== nothing
        push!(items, WidgetMenuItem("Remove from explorer"; operation = _make_remove_entry_operation(explorer, node)))
    elseif place !== nothing && !place.is_entry
        push!(items, WidgetMenuItem("Add to explorer"; operation = AddExplorerEntryOperation(document)))
    end
    _has_title_field(document) && place !== nothing && place.is_entry &&
        push!(items, WidgetMenuItem("Rename"; operation = _make_rename_operation(explorer, node)))
    if document isa ExplorerSection && place !== nothing && place.is_entry
        push!(items, WidgetMenuItem("New section"; operation = _make_new_section_operation(explorer, node)),
              WidgetMenuItem("Add…"; operation = _make_add_menu_operation(explorer, place, nothing)))
    end
    list = _find_long_children_steps(document)
    if list !== nothing
        # The navigator beside the tree shows the list, as a press on a row shows a
        # page.
        visit = make_navigator_open_operation(navigator, concat_references(address, list))
        visit === nothing || push!(items, WidgetMenuItem("Open as a list"; operation = _get_visit_writes(visit)))
    end
    commands = _make_command_items(document, node_steps)
    isempty(commands) || push!(items, WidgetSeparator(), commands...)
    point = gesture isa MouseClick ? (gesture.x, gesture.y) : nothing
    ReplaceViewStateOperation(OpenContextMenuOperation(
        Tuple{String,Document,Int}[(format_tree_node_label(document), WidgetMenu(items), 0)],
        annotate_reference_types(explorer, EmptyReference()), point))
end

# The path from `document` to its collection of children that is a lazy list, or
# that holds more than `_LIST_CHILD_COUNT` children, or `nothing`.
function _find_long_children_steps(document)
    for steps in get_tree_children_steps(document)
        reference = _make_steps(steps...)
        collection = try_evaluate_reference(document, reference, nothing)
        (collection isa ListNode || (collection !== nothing && length(collection) > _LIST_CHILD_COUNT)) &&
            return reference
    end
    nothing
end

# The commands of `document` that its gesture table names and that apply to it
# now, as items of a menu whose part is the explorer: each runs the command, with
# no gesture, rerooted by `steps` from the explorer to the document.
function _make_command_items(document, steps)
    bindings = compute_applicable_gesture_bindings(document, collect_document_gesture_bindings(typeof(document)))
    items = Any[]
    for binding in bindings
        binding.name === nothing && continue
        pattern = binding.pattern
        # A rule of the pointer, such as a menu or a tooltip, is no command.
        (pattern === nothing || pattern isa GesturePattern{KeyDown} || pattern isa GesturePattern{KeyPress}) || continue
        operation = binding.operation(document, nothing)
        operation isa Operation || continue
        push!(items, WidgetMenuItem(binding.description; operation = reroot_operation(operation, steps)))
    end
    items
end

# A right click on a row opens its menu, wherever the selection is.
const _EXPLORER_POINTER_BINDINGS = GestureBinding[
    GestureBinding(MouseClickPattern(:right), (explorer, gesture) -> _make_row_menu_operation(explorer, gesture);
                   description = "Show the menu of the row", domain = "context menu",
                   name = "Show the menu of the row")]
