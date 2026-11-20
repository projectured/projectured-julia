# Fragment of `DragTrackingModule` — the wrapper, a `(document, projection)` pair
# of transforms that a host applies around the document it shows.

"""
    make_drag_tracking_document(document) -> DragTrackingState

Wrap `document` in the state of the drag tracking. The selection of `document`
becomes the selection of the wrapper, through its `content` field.
"""
function make_drag_tracking_document(document)
    state = DragTrackingState(; content = document)
    inner = get_selection(document)
    inner === nothing ||
        replace_selection!(state,
            concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                              strip_reference_types(inner)))
    state
end

"""
    make_drag_tracking_projection(projection; find_window = nothing) -> DragTrackingProjection

The projection half of the same wrapper: `projection` shows the content.
`find_window` finds the window under the pointer of a global drag; see
[`DragTrackingProjection`](@ref).
"""
make_drag_tracking_projection(projection; find_window = nothing) =
    DragTrackingProjection(; inner = projection, find_window)
