# Fragment of `GestureTrackingModule` — the state of the tracking, a document that
# wraps the document that the projection shows.

"""
    GestureTrackingState(; content)

The state of the gesture tracking, around `content`. A view state operation
writes each field, so a history does not record it:

- `states` — the state of each recognition of the projection, in the order of
  its list; a recognition that has read nothing yet has no entry, and its first
  state is `make_recognition_state` of it;
- `waiting` — the inputs that wait for the content, in order.

The values are immutable, so each write replaces a whole value.
"""
@document struct GestureTrackingState <: Document
    content::Document
    states::Any = ()
    waiting::Any = ()
end

get_wrapped_document(state::GestureTrackingState) = get_wrapped_document(state.content)
