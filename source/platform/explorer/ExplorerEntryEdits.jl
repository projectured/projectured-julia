# Fragment of `ExplorerModule` — the edits of the entries of an explorer: the add
# of an entry, which the editor evaluates, and the keys of an explorer that add,
# remove and move the entry of the selected node.

const _ENTRIES_STEP = FieldReferenceStep("entries")
const _ENTRIES = extend_reference(EmptyReference(), _ENTRIES_STEP)

# The section that takes the entry of `operation`, and the place of the entry in it.
function _get_added_place(editor, operation::AddExplorerEntryOperation)
    section = something(operation.section, get_session_explorer_content(; editor))
    count = length(section.entries)
    index = operation.index === nothing ? count + 1 : clamp(operation.index, 1, count + 1)
    (section, index)
end

# The entry goes into its section first. The page of the navigator and the
# selection of the node follow after it, because neither the page nor the node
# exists before the add.
function evaluate_operation(editor, operation::AddExplorerEntryOperation)
    (section, index) = _get_added_place(editor, operation)
    evaluate_operation(editor, make_insert_elements_operation(_ENTRIES, index, Any[operation.document];
                                                              root = section))
    navigator = operation.navigator
    if navigator !== nothing
        visit = make_navigator_open_operation(navigator, section,
                                              extend_reference(_ENTRIES, ElementReferenceStep(index)))
        visit === nothing || evaluate_operation(editor, _get_visit_writes(visit))
    end
    selection = operation.selection
    selection === nothing ||
        evaluate_operation(editor, ReplaceSelectionOperation(
            annotate_reference_types(getfield(editor, :document), strip_reference_types(selection))))
    nothing
end

# An undo takes the entry out of its section again. The page and the selection
# are view state, and an undo leaves them.
function make_inverse_operation(document, operation::AddExplorerEntryOperation)
    (section, index) = _get_added_place(find_evaluation_editor(), operation)
    make_delete_elements_operation(_ENTRIES, index; root = section)
end

# The writes of a visit of a navigator with no selection: the page beside the
# tree changes, and the selection stays where the caller puts it.
_get_visit_writes(visit::CompoundOperation) =
    CompoundOperation(Any[part for part in visit.operations if !(part isa ReplaceSelectionOperation)])

# ── The place of the selected node ───────────────────────────────────────────

# The place of the node that `selection`, a path from `explorer`, names: the
# section that holds the node or the entry above the node, the steps from the root
# section to that section, the index of that entry, and whether the node is the
# entry itself. The index of the root section is `nothing`. `nothing` when the
# selection names no node of the tree.
function _find_selected_place(explorer::Explorer, selection)
    steps = _find_node_steps(selection)
    steps === nothing ? nothing : _find_entry_place(getfield(explorer, :tree)[].root, steps)
end

function _find_entry_place(root::ExplorerSection, steps)
    (section, prefix, k) = (root, ReferenceStep[], 1)
    isempty(steps) && return (; section, steps = prefix, index = nothing, is_entry = true)
    while true
        (k + 1 <= length(steps) && steps[k] == _ENTRIES_STEP && steps[k + 1] isa RangeReferenceStep) ||
            return nothing
        index = steps[k + 1].stop
        1 <= index <= length(section.entries) || return nothing
        entry = section.entries[index]
        is_entry = k + 1 == length(steps)
        (!is_entry && entry isa ExplorerSection && steps[k + 2] == _ENTRIES_STEP) ||
            return (; section, steps = prefix, index, is_entry)
        append!(prefix, steps[k:(k + 1)])
        (section, k) = (entry, k + 2)
    end
end

# The section and the index at which an entry is added at `place`: at the end of
# a selected section, and after any other selected entry, or after the entry above
# the selected node.
function _get_new_entry_place(place)
    place.index === nothing && return (place.section, place.steps, length(place.section.entries) + 1)
    entry = place.section.entries[place.index]
    place.is_entry && entry isa ExplorerSection &&
        return (entry, vcat(place.steps, _ENTRIES_STEP, ElementReferenceStep(place.index)),
                length(entry.entries) + 1)
    (place.section, place.steps, place.index + 1)
end

# The path from `explorer` of the node of the entry `index` of the section at
# `steps` from the root section.
_make_entry_node_path(steps, index) =
    extend_reference(EmptyReference(), FieldReferenceStep("tree"), FieldReferenceStep("root"), steps...,
                     _ENTRIES_STEP, ElementReferenceStep(index))

# ── The keys ─────────────────────────────────────────────────────────────────

# Insert and `+`: the menu of the kinds that a person adds, and another document
# by its name, at the point of `gesture` when it has one. The new entry comes after
# the entry at `place`, and its node is selected and its page shows.
function _make_add_menu_operation(explorer::Explorer, place, gesture)
    place === nothing && return nothing
    (section, steps, index) = _get_new_entry_place(place)
    navigator = getfield(explorer, :navigator)[]
    add(document) = AddExplorerEntryOperation(document; section, index, navigator,
                                              selection = _make_entry_node_path(steps, index))
    items = Any[WidgetMenuItem(name; operation = add(make_insertion_document(type)))
                for (name, type) in _collect_entry_kinds()]
    push!(items, WidgetMenuItem("Other document"; operation = add(DocumentInsertion(""))))
    make_context_menu_operation(explorer, WidgetMenu(items), gesture)
end

# A new section after the selected entry, as the item "Section" of Insert adds.
function _make_new_section_operation(explorer::Explorer, selection)
    place = _find_selected_place(explorer, selection)
    place === nothing && return nothing
    (section, steps, index) = _get_new_entry_place(place)
    AddExplorerEntryOperation(make_insertion_document(ExplorerSection); section, index,
                              navigator = getfield(explorer, :navigator)[],
                              selection = _make_entry_node_path(steps, index))
end

# Delete: the selected entry leaves its section, and the node of the section is
# selected with its page. The document stays as it is. A node below an entry is no
# entry, and the root section is none.
function _make_remove_entry_operation(explorer::Explorer, selection)
    place = _find_selected_place(explorer, selection)
    (place === nothing || !place.is_entry || place.index === nothing) && return nothing
    CompoundOperation(Any[make_delete_elements_operation(_ENTRIES, place.index; root = place.section),
                          _make_show_section_operations(explorer, place.steps)...])
end

# The selection of the node of the section at `steps` from the root section, and
# the visit of its page.
function _make_show_section_operations(explorer::Explorer, steps)
    tree_path = extend_reference(EmptyReference(), FieldReferenceStep("tree"), FieldReferenceStep("root"), steps...)
    operations = Any[ReplaceSelectionOperation(annotate_reference_types(explorer, tree_path))]
    visit = make_navigator_open_operation(getfield(explorer, :navigator)[], extend_reference(EmptyReference(), steps...))
    visit === nothing || push!(operations, _get_visit_writes(visit))
    operations
end

# Ctrl+Shift+Up and Ctrl+Shift+Down: the selected entry moves one place earlier or
# later in its section, and stays selected with its page. At an end of its section
# it stays, and so does the selection.
function _make_move_entry_operation(explorer::Explorer, selection, offset::Int)
    place = _find_selected_place(explorer, selection)
    (place === nothing || !place.is_entry || place.index === nothing) && return nothing
    target = place.index + offset
    1 <= target <= length(place.section.entries) || return DoNothingOperation()
    entry = place.section.entries[place.index]
    CompoundOperation(Any[
        make_delete_elements_operation(_ENTRIES, place.index; root = place.section),
        AddExplorerEntryOperation(entry; section = place.section, index = target,
                                  navigator = getfield(explorer, :navigator)[],
                                  selection = _make_entry_node_path(place.steps, target))])
end

# F2 on the node of a section: the caret goes to the end of the title on the page
# of the section, where each key edits the title.
function _make_rename_operation(explorer::Explorer, selection)
    place = _find_selected_place(explorer, selection)
    (place === nothing || !place.is_entry) && return nothing
    (section, steps) = place.index === nothing ? (place.section, place.steps) :
        (place.section.entries[place.index], vcat(place.steps, _ENTRIES_STEP, ElementReferenceStep(place.index)))
    section isa ExplorerSection || return nothing
    navigator = getfield(explorer, :navigator)[]
    operations = Any[]
    visit = make_navigator_open_operation(navigator, extend_reference(EmptyReference(), steps...))
    visit === nothing || push!(operations, _get_visit_writes(visit))
    count = length(section.title)
    caret = extend_reference(EmptyReference(), FieldReferenceStep("navigator"), FieldReferenceStep("content"), steps...,
                             FieldReferenceStep("title"), RangeReferenceStep(count, count))
    push!(operations, ReplaceSelectionOperation(annotate_reference_types(explorer, caret)))
    CompoundOperation(operations)
end

# Ctrl+F on a node: the caret goes to the end of the text of the filter.
function _make_filter_caret_operation(explorer::Explorer)
    count = length(getfield(explorer, :filter)[].text)
    caret = extend_reference(EmptyReference(), FieldReferenceStep("filter"), FieldReferenceStep("text"),
                             RangeReferenceStep(count, count))
    ReplaceSelectionOperation(annotate_reference_types(explorer, caret))
end

# The keys work while the selection is on a row of the tree or of the tree of the
# matches, so a key on the page goes to the page; a key that edits an entry finds
# its entry in the tree only. The tree moves its selection with Up and Down
# whatever the modifiers, so the keys that move an entry claim their chords.
@gestures Explorer begin
    when(_find_shown_node_steps(doc, sel) !== nothing)
    KeyDown(:insert) => "Add an entry" =>
        _make_add_menu_operation(doc, _find_selected_place(doc, get_selection(doc)), nothing)
    KeyDown(:f; ctrl) => "Put the keyboard in the filter" => _make_filter_caret_operation(doc)
    KeyDown(:delete) => "Remove from explorer" => _make_remove_entry_operation(doc, get_selection(doc))
    KeyDown(:f2) => "Rename the section" => _make_rename_operation(doc, get_selection(doc))
    override(KeyDown(:up; ctrl, shift)) => "Move the entry earlier" =>
        _make_move_entry_operation(doc, get_selection(doc), -1)
    override(KeyDown(:down; ctrl, shift)) => "Move the entry later" =>
        _make_move_entry_operation(doc, get_selection(doc), 1)
    nothing => "New section" => _make_new_section_operation(doc, get_selection(doc))
end
