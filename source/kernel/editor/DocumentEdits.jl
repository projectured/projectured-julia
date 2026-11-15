# Fragment of `EditorModule` — the verbs that edit the document at a reference.

"""
    find_rooted_operation(editor, reference, make_operation; description = "")
        -> Operation or nothing

The operation that `make_operation(relative)` makes for the part at `reference`,
rooted at the deepest place on `reference` from which the readers of the editor
carry it to the root; `nothing` when no place does. `relative` is the rest of
`reference` from that place.

The deepest place is the one closest to the part, so every reader between the part
and the root has its turn: a history that holds the part records the edit, as it
records an edit of the person, and the history above it records that it did. A
place that no reader follows a route into is passed over for the one above it.

Use it to make an edit of a part that a verb writes, so it is undone, checked and
logged as an edit of the person is.
"""
function find_rooted_operation(editor::Editor, reference::Reference, make_operation;
                               description::AbstractString = "")
    root = editor.document
    steps = get_reference_steps(strip_reference_types(reference))
    for depth in (length(steps) - 1):-1:1
        place = annotate_reference_types(root,
                    extend_reference(EmptyReference(), steps[1:depth]...))
        node = try_evaluate_reference(root, place, nothing)
        node === nothing && continue
        relative = annotate_reference_types(node,
                       extend_reference(EmptyReference(), steps[(depth + 1):end]...))
        rooted = read_rooted_operation(editor, place, make_operation(relative);
                                       description)
        rooted isa Operation && return rooted
    end
    nothing
end

"""
    RootedOperation(operation, description)

A change that [`make_change`](@ref) makes: `operation`, from the root of the
editor's document, carried there by the readers of the editor, so each history on
the way records it; and `description`, which says in words what it does. To
evaluate it is to evaluate `operation`. It shows as `a change: ` and its
description.

Only [`combine_changes`](@ref) and [`apply_change!`](@ref) take it, so an operation
that went through no reader is never applied as a change.
"""
struct RootedOperation <: Operation
    operation::Operation
    description::String
end

OperationModule.evaluate_operation(editor, change::RootedOperation) = evaluate_operation(editor, change.operation)
OperationModule.describe_operation(change::RootedOperation) = change.description
Base.show(io::IO, change::RootedOperation) = print(io, "a change: ", change.description)

"""
    make_change(verb, arguments...; keywords...) -> RootedOperation

The change that `verb(arguments...; keywords...)` makes, as a value. It routes and
checks as the verb does, and it changes nothing. [`apply_change!`](@ref) applies
it, and [`combine_changes`](@ref) joins several changes into one, which an undo
takes back in one step. Each verb that can make a change has a method:
`methods(make_change)` lists them.

Use it to make several edits one step of the undo, or to read what an edit does
before it applies.

# Example

    a = make_change(close_pane!, pane_1)
    b = make_change(insert_elements!, items_1, 1, [item_1])
    apply_change!(combine_changes(a, b))

See also `combine_changes`, `apply_change!`.

For the assistant.
"""
function make_change end

"""
    combine_changes(changes...) -> RootedOperation

One change that applies `changes` in their order. An undo takes it back in one
step: a history that records changes of the group one after the other records
them as one step.

Each change is made from the document as it is before any change of the group
applies, so a place by position names the document before the group. Make the
changes of one collection from its last position to its first, so a change does
not move the place of the next one.

Use it to make several edits, of one document or of many, one step of the undo.

# Example

    apply_change!(combine_changes(make_change(delete_elements!, items_1, 3),
                                  make_change(delete_elements!, items_1, 1)))

See also `make_change`, `apply_change!`.

For the assistant.
"""
function combine_changes end

function combine_changes(changes::RootedOperation...)
    isempty(changes) && throw(ArgumentError("combine_changes takes one change or more."))
    RootedOperation(_join_operations(Any[change.operation for change in changes]),
                    join((change.description for change in changes), "; "))
end

# The members of a group in their order, and the members of a compound among
# them. A run of members one after the other that sit in the same wrapper, such
# as the record of one history, is held by that wrapper once, so the history
# records the run as one step.
function _join_operations(operations::Vector{Any})
    members = Any[]
    for operation in operations
        operation isa CompoundOperation ? append!(members, operation.operations) : push!(members, operation)
    end
    runs = Vector{Any}[]
    for member in members
        if !isempty(runs) && _is_same_wrapper(first(runs[end]), member)
            push!(runs[end], member)
        else
            push!(runs, Any[member])
        end
    end
    joined = Any[length(run) == 1 ? only(run) :
                 rewrap_operation(first(run), _join_operations(Any[get_wrapped_operation(member) for member in run]))
                 for run in runs]
    length(joined) == 1 ? only(joined) : CompoundOperation(joined)
end

# Two wrappers are the same when the one, rewrapped around what the other holds,
# is the other.
_is_same_wrapper(wrapper, operation) =
    wrapper isa WrappingOperation && operation isa WrappingOperation &&
    typeof(wrapper) === typeof(operation) &&
    rewrap_operation(wrapper, get_wrapped_operation(operation)) == operation

"""
    apply_change!(change; editor = get_evaluation_editor()) -> Nothing

Apply `change`, which [`make_change`](@ref) or [`combine_changes`](@ref) made, as
an edit of the editor: Ctrl+Z undoes it in one step, each history that holds a
part of it records it, and the editor checks and logs it. It runs on the editor's
task.

Use it to apply a change that `make_change` made, or a group that
`combine_changes` joined.

# Example

    apply_change!(make_change(close_pane!, pane_1))

See also `make_change`, `combine_changes`.

For the assistant.
"""
function apply_change! end

apply_change!(change::RootedOperation; editor = get_evaluation_editor()) =
    run_on_editor_task!(editor; description = "apply_change!") do
        evaluate_operation(editor, change)
        nothing
    end

# A part as a reference from the root of the editor's document.
_get_part_reference(part::Reference) = part
_get_part_reference(part::ReferencedDocument) = get_reference(part)

# The change that replaces the range `start:stop` of the collection at `collection`
# by `values`. `words` says what the edit does, and the description names the
# collection after them, as a log shows it.
function _make_replace_elements(editor::Editor, collection, start::Integer, stop::Integer,
                                values, words::AbstractString)
    reference = _get_part_reference(collection)
    description = words * " " * describe_reference(reference, editor.document)
    target = extend_reference(strip_reference_types(reference),
                              RangeReferenceStep(start, stop))
    stored = Any[get_stored_value(value) for value in values]
    operation = find_rooted_operation(editor, target,
        relative -> ReplaceReferencedValueOperation(nothing, relative, stored);
        description)
    operation === nothing &&
        throw(ArgumentError("No reader of the editor takes an edit of " *
                            string(strip_reference_types(reference)) * "."))
    RootedOperation(operation, description)
end

# Applies `change` to the collection at `collection`, and answers the collection as
# it is after the edit.
function _replace_elements!(editor::Editor, collection, change::RootedOperation)
    apply_change!(change; editor)
    find_referenced_document(DocumentLocator(editor, _get_part_reference(collection)))
end

"""
    insert_elements!(collection, index, values; editor = get_evaluation_editor()) -> ReferencedDocument

Insert `values` into the collection that `collection` names, so that the first of them is
at `index`, and answer the collection as it is after the edit. `collection` is a
`ReferencedDocument` or a `Reference`; `index` is 1-based, and `length(collection) + 1`
appends. It is an edit of the editor, as `make_insert_elements_operation` makes it: Ctrl+Z
undoes it, the history of the document that holds the collection records it, and the
editor checks and logs it. It evaluates the edit at once and reads the IoMap that the
frame prints, so it runs on the editor's task; another task calls it through
`run_on_editor_task!`.

Use it to add an item to a list, a record to a table, or an element to any
collection of a document that the editor shows.

# Example

    insert_elements!(items_1, length(items_1) + 1, [item_1])   # appends item_1

See also `delete_elements!` and `replace_referenced_value!`.

For the assistant.
"""
function insert_elements! end

insert_elements!(collection, index::Integer, values; editor::Editor = get_evaluation_editor()) =
    run_on_editor_task!(editor; description = "insert_elements!") do
        _replace_elements!(editor, collection, make_change(insert_elements!, collection, index, values; editor))
    end

make_change(::typeof(insert_elements!), collection, index::Integer, values;
            editor::Editor = get_evaluation_editor()) =
    run_on_editor_task!(editor; description = "make_change") do
        _make_replace_elements(editor, collection, index - 1, index - 1, values,
                               "Insert " * string(length(values)) * " into")
    end

"""
    delete_elements!(collection, index; count = 1, editor = get_evaluation_editor()) -> ReferencedDocument

Remove `count` elements from the collection that `collection` names, starting at
the 1-based `index`, and answer the collection as it is after the edit.
`collection` is a `ReferencedDocument` or a `Reference`. It is an edit of the
editor, as `make_delete_elements_operation` makes it: Ctrl+Z undoes it, the history of the
document that holds the collection records it, and the editor checks and logs it.
Like `insert_elements!`, it runs on the editor's task.

Use it to remove an item from a list, a record from a table, or an element from
any collection of a document that the editor shows.

# Example

    delete_elements!(items_1, 2)      # the second item

See also `insert_elements!` and `replace_referenced_value!`.

For the assistant.
"""
function delete_elements! end

delete_elements!(collection, index::Integer; count::Integer = 1,
                 editor::Editor = get_evaluation_editor()) =
    run_on_editor_task!(editor; description = "delete_elements!") do
        _replace_elements!(editor, collection, make_change(delete_elements!, collection, index; count, editor))
    end

make_change(::typeof(delete_elements!), collection, index::Integer; count::Integer = 1,
            editor::Editor = get_evaluation_editor()) =
    run_on_editor_task!(editor; description = "make_change") do
        _make_replace_elements(editor, collection, index - 1, index - 1 + count, Any[],
                               "Delete " * string(count) * " from")
    end
