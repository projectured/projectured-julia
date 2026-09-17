# Fragment of `FocusModule` — the whole-element selection: the gesture that
# makes one, the test that tells one from a caret, and the answer a container
# gives for the child a press hit.
#
# A whole-element selection is a path that ends AT a document. Any object can be
# selected this way, so no document declares that it can be: a container applies
# the rule to whatever child is under the pointer.

"""
    is_whole_selection_press(event) -> Bool

Whether `event` selects the object under the pointer as a whole: a left press
with Alt held and no other modifier. A plain press keeps its own meaning, so a
button still fires and a caret still lands.
"""
is_whole_selection_press(event) =
    event isa MousePress && event.button === :left &&
    event.modifiers == ModifierKeys(alt = true)

"""
    is_whole_selection(document, reference) -> Bool

Whether `reference`, read inside `document`, names a document as a whole. A
caret and a range of text name no document, so neither is a whole selection. A
path that does not resolve in `document` is not one either.
"""
is_whole_selection(document, reference) =
    reference isa Reference && try_evaluate_reference(document, reference, missing) isa Document

"""
    convert_to_whole_selection(operation, child) -> ReplaceSelectionOperation

The answer a container gives for an Alt+press that hit `child`, where
`operation` is what `child` itself answered.

A whole selection inside `child` is kept, so the innermost object under the
pointer wins. Any other answer becomes the selection of `child` as a whole:
nothing, a caret, and a control's action alike. An Alt+press therefore never
acts, because the action a button answered is dropped here, and a reader has no
side effect of its own.
"""
convert_to_whole_selection(operation, child) =
    (operation isa ReplaceSelectionOperation && is_whole_selection(child, operation.path)) ?
        operation : ReplaceSelectionOperation(EmptyReference())

"""
    find_whole_selected_index(selection, field) -> Int | Nothing

The 1-based index `i` when `selection` names element `i` of the vector field
`field` as a whole (`field[i]` and nothing after it), else `nothing`. The node
types a path carries are ignored.
"""
function find_whole_selected_index(selection, field::AbstractString)
    selection isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(selection))
    length(steps) == 2 || return nothing
    head, index = steps
    (head isa FieldReferenceStep && head.name == field) || return nothing
    (index isa RangeReferenceStep && index.stop == index.start + 1) || return nothing
    index.start + 1
end

"""
    is_whole_selected_field(selection, field) -> Bool

Whether `selection` names the document in field `field` as a whole (`field` and
nothing after it). The node types a path carries are ignored.
"""
function is_whole_selected_field(selection, field::AbstractString)
    selection isa ConcreteReference || return false
    steps = get_reference_steps(strip_reference_types(selection))
    length(steps) == 1 && steps[1] isa FieldReferenceStep && steps[1].name == field
end
