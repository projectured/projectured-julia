# Fragment of `FocusModule` — the part that the person selected and the part
# under the pointer, as a model of an assistant reads them.

# The deepest document on the path `reference` from `root`, with the reference
# that reaches it: a caret inside a string or a range of text names a value, and
# the part is the document that holds that value. `nothing` when the path
# reaches no document below the root.
function _find_deepest_part(root, reference)
    steps = collect(get_reference_steps(strip_reference_types(reference)))
    for count in length(steps):-1:1
        prefix = foldr(ConcreteReference, steps[1:count]; init = EmptyReference())
        node = try_evaluate_reference(root, prefix, missing)
        node isa Document || continue
        return ReferencedDocument(node, annotate_reference_types(root, prefix))
    end
    nothing
end

"""
    find_selected_part(; editor = get_evaluation_editor()) -> ReferencedDocument or nothing

The part that the person selected: the document that the selection of the
window names as a whole after an Alt+click, or the document that holds the caret.
The answer acts like the document and carries its complete reference from the
root, so a verb that takes a part takes it. `nothing` when nothing is selected.

Use it to answer a question about "this", "here" or "the selected one": to read
the text of the part, to say what it is, or to change it.

# Example

    part_1 = find_selected_part()
    println(describe_document(part_1))
    println(print_natural_text(part_1))

See also `find_part_under_pointer`, `select_part!`, `print_natural_text`.
"""
function find_selected_part(; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "find_selected_part") do
        root = getfield(editor, :document)
        selection = get_selection(root)
        selection isa Reference || return nothing
        _find_deepest_part(root, selection)
    end
end

"""
    find_part_under_pointer(; editor = get_evaluation_editor()) -> ReferencedDocument or nothing

The part under the mouse pointer: the deepest document that the pointer is over,
with its complete reference from the root. `nothing` when the pointer is not over
the window.

Use it to answer a question about the part the person points at, such as "what is
this?" when nothing is selected.

# Example

    part_1 = find_part_under_pointer()
    part_1 === nothing || println(describe_document(part_1))

See also `find_selected_part`, `describe_document`.
"""
function find_part_under_pointer(; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "find_part_under_pointer") do
        root = getfield(editor, :document)
        target = get_mouse_target(root)
        target isa Reference || return nothing
        _find_deepest_part(root, target)
    end
end

"""
    select_part!(part; editor = get_evaluation_editor()) -> part

Select `part` as a whole, as an Alt+click on it does: the window shows it
selected, the tab that holds it gets the focus, and the keys of the person act on
it. `part` is a `ReferencedDocument` that a verb answered, such as a value read
from `get_edited_document(tab)`. It is the one verb that moves the selection of
the person; the other verbs leave it where the person put it.

Use it to show the person the part that you talk about.

# Example

    people_1 = get_edited_document(find_pane("people.json"))
    select_part!(people_1[2])

See also `find_selected_part`, `focus_pane!`.
"""
function select_part!(part::ReferencedDocument; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "select_part!") do
        evaluate_operation(editor, ReplaceSelectionOperation(get_reference(part)))
    end
    part
end
