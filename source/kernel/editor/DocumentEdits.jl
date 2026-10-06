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

# A part as a reference from the root of the editor's document.
_get_part_reference(part::Reference) = part
_get_part_reference(part::ReferencedDocument) = get_reference(part)

# Evaluates the replace of the range `start:stop` of the collection at `collection`
# by `values`, as an edit, and answers the collection as it is after the edit.
# `words` says what the edit does, and the description names the collection after
# them, as a log shows it.
function _replace_elements!(editor::Editor, collection, start::Integer, stop::Integer,
                            values, words::AbstractString)
    reference = _get_part_reference(collection)
    description = words * " " * describe_reference(reference, editor.document)
    target = extend_reference(strip_reference_types(reference),
                              RangeReferenceStep(start, stop))
    stored = Any[get_document(value) for value in values]
    operation = find_rooted_operation(editor, target,
        relative -> ReplaceReferencedValueOperation(nothing, relative, stored);
        description)
    operation === nothing &&
        throw(ArgumentError("No reader of the editor takes an edit of " *
                            string(strip_reference_types(reference)) * "."))
    evaluate_operation(editor, operation)
    find_referenced_document(DocumentLocator(editor, reference))
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
"""
insert_elements!(collection, index::Integer, values; editor::Editor = get_evaluation_editor()) =
    _replace_elements!(editor, collection, index - 1, index - 1, values,
                       "Insert " * string(length(values)) * " into")

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
"""
delete_elements!(collection, index::Integer; count::Integer = 1,
                 editor::Editor = get_evaluation_editor()) =
    _replace_elements!(editor, collection, index - 1, index - 1 + count, Any[],
                       "Delete " * string(count) * " from")
