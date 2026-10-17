# Fragment of `WidgetModule` — the request to add a document to an explorer: the
# document, the place of the new entry, and what shows it.

"""
    AddExplorerEntryOperation(document; section = nothing, index = nothing,
                              navigator = nothing, selection = nothing)

The request to add `document` as an entry of an explorer. "Add to explorer" in
the menu of a part answers it, and so do `+` and Insert in an explorer. It goes
up to the editor, which evaluates it.

- `section` is the section that takes the entry, or `nothing` for the root
  section of the editor.
- `index` is the place of the new entry among the entries of `section`, or
  `nothing` for the end.
- `navigator` is the navigator whose page shows the new entry after the add, or
  `nothing` to leave every page as it is.
- `selection` is the path of the node of the new entry from the part that
  answers, which every reader on the way up maps, so the node is selected after
  the add; `nothing` moves no selection.

An undo takes the entry out again.

Use it to add a document to an explorer from a menu or a key.

# Example

    evaluate_operation(editor, AddExplorerEntryOperation(WorkspaceFolder("data", "/home/person/data")))

See also `OpenPageOperation`.
"""
struct AddExplorerEntryOperation <: Operation
    document::Any
    section::Any
    index::Union{Int,Nothing}
    navigator::Any
    selection::Union{Reference,Nothing}
end

AddExplorerEntryOperation(document; section = nothing, index::Union{Integer,Nothing} = nothing,
                          navigator = nothing, selection::Union{Reference,Nothing} = nothing) =
    AddExplorerEntryOperation(document, section, index === nothing ? nothing : Int(index), navigator, selection)

operation_reference(operation::AddExplorerEntryOperation) = operation.selection
retarget_operation(operation::AddExplorerEntryOperation, reference::Reference) =
    AddExplorerEntryOperation(operation.document, operation.section, operation.index, operation.navigator,
                              reference)
is_self_contained_operation(operation::AddExplorerEntryOperation) = operation.selection === nothing

describe_operation(::AddExplorerEntryOperation) = "Add to explorer"
