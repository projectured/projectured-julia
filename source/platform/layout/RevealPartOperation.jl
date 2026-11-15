# Fragment of `LayoutModule` — the request that the scroll panes around a part
# bring it into view.

"""
    RevealPartOperation(reference)

The request to bring the part at `reference` into view, with no change of the
selection. Each scroll pane on the way up whose content draws the part scrolls
the least amount that shows it, and its top when the part is taller than the
view; a pane that shows the part already does not move. Every reader on the way
up maps `reference`, as any path, so a pane further out shows the inner pane
that shows the part. Applying it does nothing, and undo records nothing.

Use it to show a part that a person must see, such as the line that a search
found or the row that a run changed, while the caret stays where the person put
it.

# Example

    RevealPartOperation(@reference(table, rows[120]))

See also `ShowSelectionOperation`, which selects a part and shows it, and the
option `is_selection_revealed` of `WidgetScrollPane`, which shows the selection
of the content of a pane when the pane starts.
"""
struct RevealPartOperation <: Operation
    reference::Reference
end

operation_reference(operation::RevealPartOperation) = operation.reference
retarget_operation(::RevealPartOperation, reference) = RevealPartOperation(reference)
evaluate_operation(editor, ::RevealPartOperation) = nothing
