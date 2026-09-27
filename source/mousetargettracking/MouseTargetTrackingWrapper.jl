# Fragment of `MouseTargetTrackingModule` — the wrapper, a `(document, projection)`
# pair of transforms that a host applies around the document it shows.

"""
    make_mouse_target_tracking_document(document) -> MouseTargetTrackingState

Wrap `document` in the state of the target tracking. The selection of
`document` becomes the selection of the wrapper, through its `content` field.
"""
function make_mouse_target_tracking_document(document)
    state = MouseTargetTrackingState(; content = document)
    inner = get_selection(document)
    inner === nothing ||
        replace_selection!(state,
            concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                              strip_reference_types(inner)))
    state
end

"""
    make_mouse_target_tracking_projection(projection) -> MouseTargetTrackingProjection

The projection half of the same wrapper: `projection` shows the content.
"""
make_mouse_target_tracking_projection(projection) =
    MouseTargetTrackingProjection(; inner = projection)
