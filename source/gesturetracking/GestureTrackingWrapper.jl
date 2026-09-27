# Fragment of `GestureTrackingModule` — the wrapper, a `(document, projection)`
# pair of transforms that a host applies around the document it shows.

"""
    make_gesture_tracking_document(document) -> GestureTrackingState

Wrap `document` in the state of the gesture tracking. The selection of
`document` becomes the selection of the wrapper, through its `content` field.
"""
function make_gesture_tracking_document(document)
    state = GestureTrackingState(; content = document)
    inner = get_selection(document)
    inner === nothing ||
        replace_selection!(state,
            concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                              strip_reference_types(inner)))
    state
end

"""
    make_gesture_tracking_projection(projection; keywords...) -> GestureTrackingProjection

The projection half of the same wrapper: `projection` shows the content, and the
keywords go to [`GestureTrackingProjection`](@ref).
"""
make_gesture_tracking_projection(projection; keywords...) =
    GestureTrackingProjection(; inner = projection, keywords...)
