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
    document = try_evaluate_reference(getfield(explorer, :tree)[].root, _make_steps(steps...), nothing)
    document === nothing && return nothing
    items = Any[WidgetMenuItem(command.name; command.operation,
                               tooltip = isempty(command.keys) ? command.text :
                                         TooltipNote(; command.keys, command.text))
                for command in _collect_row_commands(explorer, steps)]
    commands = _make_command_items(document, (FieldReferenceStep("tree"), FieldReferenceStep("root"), steps...))
    isempty(commands) || push!(items, WidgetSeparator(), commands...)
    point = gesture isa MouseClick ? (gesture.x, gesture.y) : nothing
    ReplaceViewStateOperation(OpenContextMenuOperation(
        Tuple{String,Document,Int}[(format_tree_node_label(document), WidgetMenu(items), 0)],
        annotate_reference_types(explorer, EmptyReference()), point))
end

# The commands of the explorer for the row of the node at `steps` from the root
# section, in the order of the menu of the row: each a name, its operation relative
# to `explorer`, the keys that run it, and the text of its tooltip. With `selects`,
# as for a person, the selection and the page follow an edit: a new or a moved
# entry is selected with its page, and a removal selects its section. The list then
# also has Rename, which puts the caret in the title, and Add…, which opens the
# menu of the kinds. Without `selects`, as for a verb of an assistant, no edit moves
# the selection or the page, and the list has neither of the two.
function _collect_row_commands(explorer::Explorer, steps; selects::Bool = true)
    tree = getfield(explorer, :tree)[]
    navigator = getfield(explorer, :navigator)[]
    address = _make_steps(steps...)
    document = try_evaluate_reference(tree.root, address, nothing)
    commands = NamedTuple[]
    document === nothing && return commands
    add!(name, operation, text) = push!(commands, (; name, operation, keys = find_bound_keys(Explorer, name), text))
    node = _make_steps(FieldReferenceStep("tree"), FieldReferenceStep("root"), steps...)
    place = _find_entry_place(tree.root, steps)
    is_entry = place !== nothing && place.is_entry
    add!("Open in a new tab", OpenPageOperation(navigator.content, address, :new_tab), nothing)
    if is_entry && place.index !== nothing
        add!("Remove from explorer", _make_remove_entry_operation(explorer, node; selects),
             "Take the entry out of the explorer; its document stays as it is.")
        place.index > 1 &&
            add!("Move the entry earlier", _make_move_entry_operation(explorer, node, -1; selects),
                 "Move the entry one place up in its section.")
        place.index < length(place.section.entries) &&
            add!("Move the entry later", _make_move_entry_operation(explorer, node, 1; selects),
                 "Move the entry one place down in its section.")
    elseif place !== nothing && !is_entry
        add!("Add to explorer", AddExplorerEntryOperation(document), "Keep this document as an entry of the explorer.")
    end
    selects && is_entry && _has_title_field(document) &&
        add!("Rename", _make_rename_operation(explorer, node), "Edit the title of the entry.")
    if document isa ExplorerSection && is_entry
        add!("New section", _make_new_section_operation(explorer, node; selects),
             "Add an empty section at the end of this section.")
        selects && add!("Add…", _make_add_menu_operation(explorer, place, nothing),
                        "Choose the kind of document to add at the end of this section.")
    end
    list = _find_long_children_steps(document)
    if list !== nothing
        # The navigator beside the tree shows the list, as a press on a row shows a
        # page.
        visit = make_navigator_open_operation(navigator, concat_references(address, list))
        visit === nothing || add!("Open as a list", _get_visit_writes(visit),
                                  "Show the children of this row as a page, for a row with many children.")
    end
    commands
end

# The commands of the row of the node at `steps` from `explorer`, for a verb that
# acts at the node, such as `run_command!` of an assistant: the commands of its
# menu that move neither the selection nor the page of the person.
function collect_part_commands(explorer::Explorer, steps)
    node_steps = _find_shown_node_steps(explorer, _make_steps(steps...))
    node_steps === nothing && return GestureRow[]
    GestureRow[GestureRow(join(describe_gesture_pattern.(command.keys), ", "), command.name, "explorer",
                          command.operation)
               for command in _collect_row_commands(explorer, node_steps; selects = false)]
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
