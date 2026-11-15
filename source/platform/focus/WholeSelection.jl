# Fragment of `FocusModule` — the selection presses and the whole-element
# selection: the gestures that select and never act, the test that tells a whole
# selection from a caret, and the answer a container gives for the child a press
# hit.
#
# Alt means "select, do not act". A plain click does what the part under the
# pointer does, and puts the caret where the part does nothing. An Alt+click puts
# the caret at the character under the pointer, whatever the part does. An
# Alt+double click selects the innermost part as a whole: the part that holds the
# caret of its first click.
#
# A whole-element selection is a path that names a part of the document as a
# whole: a document, or a value that a field or one element of a collection
# holds. Any part can be selected this way, so no document declares that it can
# be: a container applies the rule to whatever child is under the pointer.

"""
    is_whole_selection_press(event) -> Bool

Whether `event` selects the object under the pointer as a whole: the second left
click of a double click with Alt held and no other modifier. Its first click put
the caret, and this one selects the part that holds the caret. A plain press keeps
its own meaning, so a button still fires and a caret still lands.
"""
is_whole_selection_press(event) =
    event isa MouseClick && event.button === :left && event.count >= 2 &&
    event.modifiers == ModifierKeys(alt = true)

"""
    is_caret_press(event) -> Bool

Whether `event` puts the caret at the character under the pointer, whatever the
part there does: a single left click with Alt held and no other modifier. A part
that acts on a plain click, such as a button or a chip, does not act on it.
"""
is_caret_press(event) =
    event isa MouseClick && event.button === :left && event.count == 1 &&
    event.modifiers == ModifierKeys(alt = true)

"""
    is_selection_press(event) -> Bool

Whether `event` selects and never acts: a caret press or a whole selection press.
"""
is_selection_press(event) = is_caret_press(event) || is_whole_selection_press(event)

"""
    convert_to_caret_selection(operation) -> ReplaceSelectionOperation or nothing

The answer a container gives for a caret press that hit a child, where
`operation` is what the child answered: the selection that the child answered,
such as the caret in its text, and nothing for any other answer. A caret press
therefore never acts, because the action that a control answered is dropped here.
"""
convert_to_caret_selection(operation) = operation isa ReplaceSelectionOperation ? operation : nothing

"""
    is_whole_selection(document, reference) -> Bool

Whether `reference`, read inside `document`, names a part of `document` as a
whole: a document, or a value that a field or one element of a collection
holds, such as the title of a card that is a `String`. A caret and a range of
text name a place inside a value, so neither is a whole selection. A path that
does not resolve in `document` is not one either.
"""
function is_whole_selection(document, reference)
    reference isa Reference || return false
    target = try_evaluate_reference(document, reference, missing)
    target !== missing && _is_whole_part(document, reference, target)
end

# Whether `path`, read inside `document`, names `target` as a whole: `target` is
# a document, or the last step of `path` is a field, or one element of a vector,
# a tuple or a collection document. A range of a text is none of these.
function _is_whole_part(document, path::Reference, target)
    target isa Document && return true
    steps = get_reference_steps(strip_reference_types(path))
    isempty(steps) && return false
    step = last(steps)
    step isa FieldReferenceStep && return true
    (step isa RangeReferenceStep && step.stop == step.start + 1) || return false
    holder = try_evaluate_reference(document, _prepend_steps(Tuple(steps[1:(end - 1)]), EmptyReference()),
                                    missing)
    holder isa AbstractVector || holder isa Tuple || holder isa CollectionDocument
end

"""
    find_whole_part(document, path) -> Reference

The innermost part that `path` reaches inside `document`, named as a whole.

A path that names a part as a whole (`is_whole_selection`) is the answer. A path
that ends in a place inside a value, such as a caret or a range of text, loses
the place, step by step, until a whole part is left: a caret in the title of a
card, `.title.value{3}`, gives the `String` in its field, `.title.value`. A
caret directly in `document` gives `document`, the empty path.

A part that a projection drew and that `document` does not hold, such as the
bracket of a call or the label of a row, is a part too. Its path ends in a
`ProjectionReferenceStep` at the innermost node that printed it, and the place is
cut inside the output path of that step: a field and one element reach a drawn
part, and any other last step is a place in it. So a caret beside the bracket,
`‹.open{0}›`, gives the bracket, `‹.open›`. An output path that loses every step
gives the node that printed it.

A path that does not resolve in `document` is the answer as it is. A container
can answer a path in its own terms that is not a path of its document, as a
tabbed pane names a widget page without the `element` step of the page, and the
level above maps it back.
"""
function find_whole_part(document, path)
    path isa ConcreteReference || return path
    step = _get_last_step(path)
    step isa ProjectionReferenceStep && return _cut_introduced_part(path, step)
    target = try_evaluate_reference(document, path, missing)
    (target === missing || _is_whole_part(document, path, target)) && return path
    find_whole_part(document, _drop_last_step(path))
end

# `path`, whose last step is the introduced `step`, with the place cut off the
# output path of that step.
function _cut_introduced_part(path, step::ProjectionReferenceStep)
    inner = _cut_output_place(step.output_path)
    inner isa EmptyReference && return _drop_last_step(path)
    inner === step.output_path && return path
    _replace_last_step(path, ProjectionReferenceStep(step.projection, inner))
end

# `output_path`, a path in the output of a projection, without the place at its
# end. No document of the output is at hand, so the steps decide: a field and one
# element reach a drawn part, and any other last step is a place in it.
function _cut_output_place(output_path)
    output_path isa ConcreteReference || return output_path
    step = _get_last_step(output_path)
    step isa ProjectionReferenceStep && return _cut_introduced_part(output_path, step)
    (step isa FieldReferenceStep || (step isa RangeReferenceStep && step.stop == step.start + 1)) &&
        return output_path
    _cut_output_place(_drop_last_step(output_path))
end

_get_last_step(path::ConcreteReference) =
    path.tail isa ConcreteReference ? _get_last_step(path.tail) : path.head

# `path` without its last step. The new end keeps the type of the node that the
# step stood on.
_drop_last_step(path::ConcreteReference) =
    path.tail isa ConcreteReference ? ConcreteReference(path.type, path.head, _drop_last_step(path.tail)) :
    EmptyReference(path.type)

_replace_last_step(path::ConcreteReference, step) =
    path.tail isa ConcreteReference ? ConcreteReference(path.type, path.head, _replace_last_step(path.tail, step)) :
    ConcreteReference(path.type, step, path.tail)

"""
    convert_to_whole_selection(operation, child) -> ReplaceSelectionOperation

The answer a container gives for an Alt+double click that hit `child`, where
`operation` is what `child` itself answered.

A selection inside `child` becomes the innermost whole part that it reaches
(`find_whole_part`), so the innermost part under the pointer wins: a document, a
value that a field or one element of a collection holds, or a part that a
projection drew. Any other answer becomes the selection of `child` as a whole:
nothing, and a control's action. An Alt+double click therefore never acts, because the
action a button answered is dropped here, and a reader has no side effect of its
own.
"""
function convert_to_whole_selection(operation, child)
    operation isa ReplaceSelectionOperation || return ReplaceSelectionOperation(EmptyReference())
    path = find_whole_part(child, operation.path)
    path === operation.path ? operation : ReplaceSelectionOperation(path)
end

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
    is_whole_selected_field(selection, field; document = nothing) -> Bool

Whether `selection` names the document in field `field` as a whole (`field` and
nothing after it). The node types a path carries are ignored.

With `document`, the holder of `field`, a selection of a value in one field of
the document in `field` that is not a document itself (`field.value`, the
`String` of a `PrimitiveString` title) counts too: that document draws no mark of
its own for the value, so the holder that marks the field marks it.
"""
function is_whole_selected_field(selection, field::AbstractString; document = nothing)
    selection isa ConcreteReference || return false
    steps = get_reference_steps(strip_reference_types(selection))
    (length(steps) == 1 || (length(steps) == 2 && _is_value_field(document, steps))) || return false
    steps[1] isa FieldReferenceStep && steps[1].name == field
end

# Whether `steps`, read in `document`, end in a field step that reaches a value that
# is not a document.
function _is_value_field(document, steps)
    (document !== nothing && last(steps) isa FieldReferenceStep) || return false
    target = try_evaluate_reference(document, _prepend_steps(Tuple(steps), EmptyReference()), missing)
    target !== missing && !(target isa Document)
end
