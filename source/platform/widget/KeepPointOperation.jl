# Fragment of `WidgetModule` — the request that a scroll pane keeps a point of its
# content under the pointer while an operation moves that point.

"""
    KeepPointOperation(operation, move)

`operation`, which moves the point of a content under the pointer by `move`, a
pair `(dx, dy)` of pixels, with the request to keep that point under the
pointer. The nearest scroll pane on the way up answers `operation` and a scroll
by `move`, so the part under the pointer stays where it is, and a pane further
out gets `operation` alone. With no scroll pane on the way, applying it applies
`operation`.

Use it for a zoom of a view that changes the size of its content, such as the
zoom of the layout of a graph.

# Example

    zoom = ReplaceViewStateOperation(ReplaceReferencedValueOperation(layout, "zoom", (scale = 2.0, shift = (0.0, 0.0))))
    KeepPointOperation(zoom, (40, 25))

See also `ShowSelectionOperation`, the request that a scroll pane shows a
selected part.
"""
struct KeepPointOperation <: WrappingOperation
    operation::Any
    move::Tuple{Int,Int}
end

get_wrapped_operation(operation::KeepPointOperation) = operation.operation
rewrap_operation(operation::KeepPointOperation, inner) = KeepPointOperation(inner, operation.move)
evaluate_operation(editor, operation::KeepPointOperation) = evaluate_operation(editor, operation.operation)
